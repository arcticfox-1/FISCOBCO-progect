pragma solidity ^0.4.25;

/**
 * @notice RoleControl 的最小接口，用于跨合约权限校验
 */
contract IRoleControl {
    function hasRole(address account, uint8 role) public view returns (bool);
    function isActive(address account) public view returns (bool);
}

/**
 * @title Traceability
 * @notice 农产品批次与全生命周期溯源记录，追加式存储，不可篡改
 * @dev 每批次维护一条记录链；链上仅存哈希与关键字段，原文留在链下。
 */
contract Traceability {

    // ============ 环节类型 ============
    uint8 public constant STAGE_PLANTING  = 1;  // 种植/养殖
    uint8 public constant STAGE_QUALITY   = 2;  // 质检
    uint8 public constant STAGE_PROCESS   = 3;  // 加工
    uint8 public constant STAGE_LOGISTICS = 4;  // 物流
    uint8 public constant STAGE_SALES     = 5;  // 销售

    // ============ 数据结构 ============
    struct TraceRecord {
        uint8   stage;        // 环节类型
        address operator;     // 上链主体地址
        string  summary;      // 环节摘要（简短描述）
        bytes32 dataHash;     // 链下完整数据的 SHA-256
        uint256 timestamp;    // 上链时间
        int256  temperature;  // 冷链温度（摄氏度 * 100），非冷链填 0
    }

    struct Batch {
        string  batchId;      // 批次号（业务主键）
        string  productName;  // 产品名称
        string  origin;       // 产地
        address creator;      // 创建者
        uint256 createdAt;    // 创建时间
        uint256 recordCount;  // 记录数量
        bool    exists;
    }

    address public admin;
    IRoleControl public roleControl;
    bool public paused;                       // 全局开关，异常时紧急暂停

    mapping(string => Batch) private _batches;                      // batchId => 批次
    mapping(string => TraceRecord[]) private _records;              // batchId => 记录数组
    string[] private _batchIds;                                     // 全部批次号

    // ============ 事件 ============
    event BatchCreated(string indexed batchId, string productName, address indexed creator, uint256 timestamp);
    event TraceRecordAdded(string indexed batchId, uint8 stage, address indexed operator, bytes32 dataHash, uint256 timestamp);
    event ContractPaused(address indexed by, uint256 timestamp);
    event ContractResumed(address indexed by, uint256 timestamp);

    // ============ 修饰器 ============
    modifier onlyAdmin() {
        require(msg.sender == admin, "Traceability: caller is not admin");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Traceability: contract paused");
        _;
    }

    modifier onlyAuthorized(uint8 role) {
        require(roleControl.isActive(msg.sender), "Traceability: entity not active");
        require(roleControl.hasRole(msg.sender, role), "Traceability: insufficient role");
        _;
    }

    // ============ 构造 ============
    constructor(address _roleControl) public {
        require(_roleControl != address(0), "Traceability: invalid role contract");
        admin = msg.sender;
        roleControl = IRoleControl(_roleControl);
        paused = false;
    }

    // ============ 批次管理 ============

    /**
     * @notice 创建农产品批次（仅农户/加工方可创建）
     * @param batchId     批次号，业务唯一
     * @param productName 产品名称
     * @param origin      产地
     */
    function createBatch(string batchId, string productName, string origin)
        public
        whenNotPaused
    {
        require(bytes(batchId).length > 0, "Traceability: empty batchId");
        require(bytes(productName).length > 0, "Traceability: empty productName");
        require(!_batches[batchId].exists, "Traceability: batch already exists");
        require(
            roleControl.isActive(msg.sender) &&
            (roleControl.hasRole(msg.sender, 2) || roleControl.hasRole(msg.sender, 4)),
            "Traceability: only farmer or processor can create batch"
        );

        _batches[batchId] = Batch({
            batchId: batchId,
            productName: productName,
            origin: origin,
            creator: msg.sender,
            createdAt: now,
            recordCount: 0,
            exists: true
        });
        _batchIds.push(batchId);

        emit BatchCreated(batchId, productName, msg.sender, now);
    }

    // ============ 溯源记录 ============

    /**
     * @notice 追加溯源环节记录（只增不改）
     * @param batchId     批次号
     * @param stage       环节类型
     * @param summary     环节摘要
     * @param dataHash    链下数据哈希
     * @param temperature 温度（*100），非冷链传 0
     */
    function addTraceRecord(
        string batchId,
        uint8 stage,
        string summary,
        bytes32 dataHash,
        int256 temperature
    )
        public
        whenNotPaused
    {
        require(_batches[batchId].exists, "Traceability: batch not found");
        require(stage >= STAGE_PLANTING && stage <= STAGE_SALES, "Traceability: invalid stage");
        require(dataHash != bytes32(0), "Traceability: empty dataHash");
        require(roleControl.isActive(msg.sender), "Traceability: entity not active");

        // 按环节校验写入角色
        require(_hasStagePermission(msg.sender, stage), "Traceability: no permission for this stage");

        _records[batchId].push(TraceRecord({
            stage: stage,
            operator: msg.sender,
            summary: summary,
            dataHash: dataHash,
            timestamp: now,
            temperature: temperature
        }));
        _batches[batchId].recordCount += 1;

        emit TraceRecordAdded(batchId, stage, msg.sender, dataHash, now);
    }

    function _hasStagePermission(address account, uint8 stage) internal view returns (bool) {
        if (stage == STAGE_PLANTING)  return roleControl.hasRole(account, 2);  // 农户
        if (stage == STAGE_QUALITY)   return roleControl.hasRole(account, 1) || roleControl.hasRole(account, 4); // 监管/加工
        if (stage == STAGE_PROCESS)   return roleControl.hasRole(account, 4);  // 加工
        if (stage == STAGE_LOGISTICS) return roleControl.hasRole(account, 8);  // 物流
        if (stage == STAGE_SALES)     return roleControl.hasRole(account, 16); // 销售
        return false;
    }

    // ============ 查询 ============

    function getBatch(string batchId)
        public
        view
        returns (string productName, string origin, address creator, uint256 createdAt, uint256 recordCount)
    {
        require(_batches[batchId].exists, "Traceability: batch not found");
        Batch storage b = _batches[batchId];
        return (b.productName, b.origin, b.creator, b.createdAt, b.recordCount);
    }

    function getRecordCount(string batchId) public view returns (uint256) {
        return _records[batchId].length;
    }

    /**
     * @notice 按索引读取单条记录，便于分页
     */
    function getRecord(string batchId, uint256 index)
        public
        view
        returns (uint8 stage, address operator, string summary, bytes32 dataHash, uint256 timestamp, int256 temperature)
    {
        require(index < _records[batchId].length, "Traceability: index out of range");
        TraceRecord storage r = _records[batchId][index];
        return (r.stage, r.operator, r.summary, r.dataHash, r.timestamp, r.temperature);
    }

    /**
     * @notice 校验某条记录的链下数据是否与链上哈希一致
     */
    function verifyRecord(string batchId, uint256 index, bytes32 dataHash) public view returns (bool) {
        require(index < _records[batchId].length, "Traceability: index out of range");
        return _records[batchId][index].dataHash == dataHash;
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
        if (_paused) {
            emit ContractPaused(msg.sender, now);
        } else {
            emit ContractResumed(msg.sender, now);
        }
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
