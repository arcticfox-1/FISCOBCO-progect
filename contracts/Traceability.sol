pragma solidity ^0.4.25;

/**
 * @notice RoleControl 最小接口，用于跨合约权限校验
 */
contract IRoleControl {
    function hasRole(address account, uint8 role) public view returns (bool);
    function isActive(address account) public view returns (bool);
}

/**
 * @title Traceability
 * @notice 农产品批次登记与全生命周期溯源存证
 * @dev 按实训要求实现：批次唯一登记、业务记录追加、授权主体校验、状态流转、
 *      不合格批次拦截、追加更正（不覆盖历史）、异常处置追溯。
 *
 * 设计原则：
 *   1. 只追加不修改 —— 原始记录永不移除，录入错误通过「更正记录」追加说明；
 *   2. 最小上链   —— 链上只存标识、主体、时间、状态、文件摘要，报告原文留链下；
 *   3. 状态驱动   —— 业务能否继续由批次状态决定，不合格批次无法进入正常销售。
 */
contract Traceability {

    // ============ 环节类型 ============
    uint8 public constant STAGE_PLANTING   = 1;  // 种植
    uint8 public constant STAGE_HARVEST    = 2;  // 采收
    uint8 public constant STAGE_INSPECTION = 3;  // 检测
    uint8 public constant STAGE_TRANSPORT  = 4;  // 运输
    uint8 public constant STAGE_SALES      = 5;  // 销售
    uint8 public constant STAGE_CORRECTION = 6;  // 更正说明

    // ============ 批次状态 ============
    uint8 public constant STATUS_REGISTERED = 0;  // 已登记
    uint8 public constant STATUS_GROWING    = 1;  // 种植中
    uint8 public constant STATUS_HARVESTED  = 2;  // 已采收
    uint8 public constant STATUS_PASSED     = 3;  // 检测合格
    uint8 public constant STATUS_FAILED     = 4;  // 检测不合格（禁止流入销售）
    uint8 public constant STATUS_IN_TRANSIT = 5;  // 运输中
    uint8 public constant STATUS_ON_SALE    = 6;  // 已上架
    uint8 public constant STATUS_SOLD       = 7;  // 已售出
    uint8 public constant STATUS_DISPOSED   = 8;  // 已处置（不合格批次的最终状态）

    // ============ 数据结构 ============
    struct TraceRecord {
        uint8   stage;      // 环节类型
        address operator;   // 上链主体地址
        string  summary;    // 环节摘要
        bytes32 dataHash;   // 链下数据 / 报告文件的 SHA-256 摘要
        uint256 timestamp;  // 上链时间
        bool    qualified;  // 检测结论（仅检测环节有意义，其余恒为 true）
        uint256 refIndex;   // 更正记录指向的原记录下标（非更正记录为 0）
    }

    struct Batch {
        string  batchId;      // 批次号（业务主键，全局唯一）
        string  productName;  // 产品名称
        string  origin;       // 产地
        address creator;      // 登记人
        uint256 createdAt;    // 登记时间
        uint8   status;       // 当前状态
        uint256 recordCount;  // 记录条数
        bool    exists;
    }

    address public admin;
    IRoleControl public roleControl;
    bool public paused;

    mapping(string => Batch) private _batches;
    mapping(string => TraceRecord[]) private _records;
    mapping(string => uint256[]) private _corrections;  // batchId => 更正记录下标集合
    string[] private _batchIds;

    // ============ 事件 ============
    event BatchCreated(string indexed batchId, string productName, address indexed creator, uint256 timestamp);
    event TraceRecordAdded(string indexed batchId, uint8 stage, address indexed operator, bytes32 dataHash, uint256 timestamp);
    event InspectionSubmitted(string indexed batchId, address indexed inspector, bytes32 reportHash, bool qualified, uint256 timestamp);
    event CorrectionAdded(string indexed batchId, uint256 targetIndex, address indexed operator, bytes32 newHash, uint256 timestamp);
    event BatchStatusChanged(string indexed batchId, uint8 fromStatus, uint8 toStatus, uint256 timestamp);
    event BatchDisposed(string indexed batchId, string method, address indexed regulator, uint256 timestamp);
    event ContractPaused(address indexed by, uint256 timestamp);

    // ============ 修饰器 ============
    modifier onlyAdmin() {
        require(msg.sender == admin, "Traceability: caller is not admin");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Traceability: contract paused");
        _;
    }

    modifier onlyRole(uint8 role) {
        require(roleControl.isActive(msg.sender), "Traceability: entity not active");
        require(roleControl.hasRole(msg.sender, role), "Traceability: insufficient role");
        _;
    }

    // ============ 构造 ============
    constructor(address _roleControl) public {
        require(_roleControl != address(0), "Traceability: invalid role contract");
        admin = msg.sender;
        roleControl = IRoleControl(_roleControl);
    }

    // ============ 批次登记 ============

    /**
     * @notice 登记农产品批次，批次号全局唯一
     * @param batchId     批次号，重复登记直接回滚
     * @param productName 产品名称
     * @param origin      产地
     */
    function createBatch(string batchId, string productName, string origin)
        public
        whenNotPaused
        onlyRole(2)                       // 仅生产主体可登记
    {
        require(bytes(batchId).length > 0, "Traceability: empty batchId");
        require(bytes(productName).length > 0, "Traceability: empty productName");
        require(!_batches[batchId].exists, "Traceability: batch already exists");

        _batches[batchId] = Batch({
            batchId: batchId,
            productName: productName,
            origin: origin,
            creator: msg.sender,
            createdAt: now,
            status: STATUS_REGISTERED,
            recordCount: 0,
            exists: true
        });
        _batchIds.push(batchId);

        emit BatchCreated(batchId, productName, msg.sender, now);
    }

    // ============ 业务记录 ============

    /**
     * @notice 追加种植、采收、运输、销售记录
     * @dev 状态校验保证流程顺序，跳步或倒序会被回滚
     */
    function addTraceRecord(string batchId, uint8 stage, string summary, bytes32 dataHash)
        public
        whenNotPaused
    {
        require(_batches[batchId].exists, "Traceability: batch not found");
        require(dataHash != bytes32(0), "Traceability: empty dataHash");
        require(
            stage == STAGE_PLANTING || stage == STAGE_HARVEST ||
            stage == STAGE_TRANSPORT || stage == STAGE_SALES,
            "Traceability: invalid stage"
        );
        require(roleControl.isActive(msg.sender), "Traceability: entity not active");

        Batch storage b = _batches[batchId];
        uint8 nextStatus = b.status;

        if (stage == STAGE_PLANTING) {
            require(roleControl.hasRole(msg.sender, 2), "Traceability: producer required");
            require(
                b.status == STATUS_REGISTERED || b.status == STATUS_GROWING,
                "Traceability: planting not allowed at current status"
            );
            nextStatus = STATUS_GROWING;
        } else if (stage == STAGE_HARVEST) {
            require(roleControl.hasRole(msg.sender, 2), "Traceability: producer required");
            require(b.status == STATUS_GROWING, "Traceability: harvest requires growing status");
            nextStatus = STATUS_HARVESTED;
        } else if (stage == STAGE_TRANSPORT) {
            require(roleControl.hasRole(msg.sender, 8), "Traceability: logistics required");
            require(b.status == STATUS_PASSED, "Traceability: transport requires passed inspection");
            nextStatus = STATUS_IN_TRANSIT;
        } else if (stage == STAGE_SALES) {
            require(roleControl.hasRole(msg.sender, 16), "Traceability: seller required");
            require(
                b.status == STATUS_PASSED || b.status == STATUS_IN_TRANSIT ||
                b.status == STATUS_ON_SALE,
                "Traceability: unqualified batch cannot be sold"
            );
            nextStatus = (b.status == STATUS_ON_SALE) ? STATUS_SOLD : STATUS_ON_SALE;
        }

        uint256 index = _records[batchId].length;
        _records[batchId].push(TraceRecord({
            stage: stage,
            operator: msg.sender,
            summary: summary,
            dataHash: dataHash,
            timestamp: now,
            qualified: true,
            refIndex: 0
        }));
        b.recordCount = index + 1;

        if (nextStatus != b.status) {
            emit BatchStatusChanged(batchId, b.status, nextStatus, now);
            b.status = nextStatus;
        }

        emit TraceRecordAdded(batchId, stage, msg.sender, dataHash, now);
    }

    /**
     * @notice 提交质检结论，合格放行、不合格拦截
     * @param reportHash 质检报告文件的摘要，报告原文保存在链下
     * @param qualified  检测是否合格
     */
    function submitInspection(string batchId, string summary, bytes32 reportHash, bool qualified)
        public
        whenNotPaused
        onlyRole(4)                       // 仅检测机构
    {
        require(_batches[batchId].exists, "Traceability: batch not found");
        require(reportHash != bytes32(0), "Traceability: empty reportHash");

        Batch storage b = _batches[batchId];
        require(b.status == STATUS_HARVESTED, "Traceability: inspection requires harvested status");

        uint256 index = _records[batchId].length;
        _records[batchId].push(TraceRecord({
            stage: STAGE_INSPECTION,
            operator: msg.sender,
            summary: summary,
            dataHash: reportHash,
            timestamp: now,
            qualified: qualified,
            refIndex: 0
        }));
        b.recordCount = index + 1;

        uint8 nextStatus = qualified ? STATUS_PASSED : STATUS_FAILED;
        emit BatchStatusChanged(batchId, b.status, nextStatus, now);
        b.status = nextStatus;

        emit InspectionSubmitted(batchId, msg.sender, reportHash, qualified, now);
    }

    /**
     * @notice 追加更正说明，不修改原始记录
     * @dev 录入错误一律以新记录更正，历史可追溯
     * @param targetIndex 被更正的原记录下标
     */
    function addCorrection(string batchId, uint256 targetIndex, string reason, bytes32 newHash)
        public
        whenNotPaused
    {
        require(_batches[batchId].exists, "Traceability: batch not found");
        require(roleControl.isActive(msg.sender), "Traceability: entity not active");
        require(targetIndex < _records[batchId].length, "Traceability: target index out of range");
        require(newHash != bytes32(0), "Traceability: empty newHash");

        // 仅原记录主体本人或监管方可发起更正
        require(
            _records[batchId][targetIndex].operator == msg.sender ||
            roleControl.hasRole(msg.sender, 1),
            "Traceability: only original operator or regulator can correct"
        );

        uint256 index = _records[batchId].length;
        _records[batchId].push(TraceRecord({
            stage: STAGE_CORRECTION,
            operator: msg.sender,
            summary: reason,
            dataHash: newHash,
            timestamp: now,
            qualified: true,
            refIndex: targetIndex
        }));
        _batches[batchId].recordCount = index + 1;
        _corrections[batchId].push(index);

        emit CorrectionAdded(batchId, targetIndex, msg.sender, newHash, now);
    }

    /**
     * @notice 不合格批次处置，记录处置方式后归档
     */
    function disposeBatch(string batchId, string method)
        public
        whenNotPaused
        onlyRole(1)                       // 仅监管方
    {
        require(_batches[batchId].exists, "Traceability: batch not found");
        Batch storage b = _batches[batchId];
        require(b.status == STATUS_FAILED, "Traceability: only failed batch can be disposed");
        require(bytes(method).length > 0, "Traceability: empty disposal method");

        uint256 index = _records[batchId].length;
        _records[batchId].push(TraceRecord({
            stage: STAGE_CORRECTION,
            operator: msg.sender,
            summary: method,
            dataHash: keccak256(abi.encodePacked(batchId, method)),
            timestamp: now,
            qualified: true,
            refIndex: 0
        }));
        b.recordCount = index + 1;

        emit BatchStatusChanged(batchId, b.status, STATUS_DISPOSED, now);
        b.status = STATUS_DISPOSED;
        emit BatchDisposed(batchId, method, msg.sender, now);
    }

    // ============ 查询 ============

    function getBatch(string batchId)
        public
        view
        returns (string productName, string origin, address creator, uint256 createdAt, uint8 status, uint256 recordCount)
    {
        require(_batches[batchId].exists, "Traceability: batch not found");
        Batch storage b = _batches[batchId];
        return (b.productName, b.origin, b.creator, b.createdAt, b.status, b.recordCount);
    }

    function getBatchStatus(string batchId) public view returns (uint8) {
        require(_batches[batchId].exists, "Traceability: batch not found");
        return _batches[batchId].status;
    }

    function getRecordCount(string batchId) public view returns (uint256) {
        return _records[batchId].length;
    }

    function getRecord(string batchId, uint256 index)
        public
        view
        returns (uint8 stage, address operator, string summary, bytes32 dataHash, uint256 timestamp, bool qualified, uint256 refIndex)
    {
        require(index < _records[batchId].length, "Traceability: index out of range");
        TraceRecord storage r = _records[batchId][index];
        return (r.stage, r.operator, r.summary, r.dataHash, r.timestamp, r.qualified, r.refIndex);
    }

    /**
     * @notice 校验链下文件摘要与链上是否一致
     */
    function verifyDigest(string batchId, uint256 index, bytes32 digest) public view returns (bool) {
        require(index < _records[batchId].length, "Traceability: index out of range");
        return _records[batchId][index].dataHash == digest;
    }

    function getCorrectionCount(string batchId) public view returns (uint256) {
        return _corrections[batchId].length;
    }

    function getCorrectionAt(string batchId, uint256 i) public view returns (uint256) {
        require(i < _corrections[batchId].length, "Traceability: index out of range");
        return _corrections[batchId][i];
    }

    function getBatchCount() public view returns (uint256) {
        return _batchIds.length;
    }

    function getBatchIdAt(uint256 index) public view returns (string) {
        require(index < _batchIds.length, "Traceability: index out of range");
        return _batchIds[index];
    }

    // ============ 管理 ============

    function setPaused(bool _paused) public onlyAdmin {
        paused = _paused;
        emit ContractPaused(msg.sender, now);
    }

    function setRoleControl(address _roleControl) public onlyAdmin {
        require(_roleControl != address(0), "Traceability: invalid role contract");
        roleControl = IRoleControl(_roleControl);
    }

    function transferAdmin(address newAdmin) public onlyAdmin {
        require(newAdmin != address(0), "Traceability: invalid admin");
        admin = newAdmin;
    }
}
