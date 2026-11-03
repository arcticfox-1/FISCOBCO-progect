pragma solidity ^0.4.25;

/**
 * @title RoleControl
 * @notice 参与主体注册与角色权限管理
 * @dev 仅监管方可审核主体、授予角色。角色按位掩码存储，支持一个地址承担多个角色。
 *
 * 角色划分依据实训要求：
 *   生产主体（种植 / 采收）、检测机构、物流企业、销售商、监管人员
 */
contract RoleControl {

    // ============ 角色定义（位掩码，可组合） ============
    uint8 public constant ROLE_REGULATOR = 1;   // 监管人员：审核主体、审计全链
    uint8 public constant ROLE_PRODUCER  = 2;   // 生产主体：种植、采收
    uint8 public constant ROLE_INSPECTOR = 4;   // 检测机构：出具质检报告
    uint8 public constant ROLE_LOGISTICS = 8;   // 物流企业：承运交接
    uint8 public constant ROLE_SELLER    = 16;  // 销售商：上架、销售

    // ============ 数据结构 ============
    struct Entity {
        string  entityId;     // 主体唯一编码（统一社会信用代码 / 机构代码）
        string  name;         // 主体名称
        uint8   roles;        // 角色位掩码
        bool    active;       // 是否启用（监管方审核通过后方可写链）
        uint256 registeredAt; // 注册时间
    }

    address public regulator;                      // 监管方合约管理员
    mapping(address => Entity) private _entities;  // 地址 => 主体信息
    address[] private _entityList;                 // 主体地址列表

    // ============ 事件 ============
    event EntityRegistered(address indexed account, string entityId, string name, uint256 timestamp);
    event RoleGranted(address indexed account, uint8 role, uint256 timestamp);
    event RoleRevoked(address indexed account, uint8 role, uint256 timestamp);
    event EntityStatusChanged(address indexed account, bool active, uint256 timestamp);

    // ============ 修饰器 ============
    modifier onlyRegulator() {
        require(msg.sender == regulator, "RoleControl: caller is not regulator");
        _;
    }

    // ============ 构造 ============
    constructor() public {
        regulator = msg.sender;
        _entities[msg.sender] = Entity({
            entityId: "REGULATOR-000",
            name: "Regulatory Authority",
            roles: ROLE_REGULATOR,
            active: true,
            registeredAt: now
        });
        _entityList.push(msg.sender);
        emit EntityRegistered(msg.sender, "REGULATOR-000", "Regulatory Authority", now);
    }

    // ============ 主体管理 ============

    /**
     * @notice 注册参与主体，注册后需监管方审核启用
     * @param entityId 主体唯一编码
     * @param name     主体名称
     * @param roles    申请的初始角色位掩码（不可自行申请监管角色）
     */
    function registerEntity(string entityId, string name, uint8 roles) public {
        require(bytes(entityId).length > 0, "RoleControl: empty entityId");
        require(bytes(name).length > 0, "RoleControl: empty name");
        require(_entities[msg.sender].registeredAt == 0, "RoleControl: already registered");
        require((roles & ROLE_REGULATOR) == 0, "RoleControl: cannot self-assign regulator");

        _entities[msg.sender] = Entity({
            entityId: entityId,
            name: name,
            roles: roles,
            active: false,          // 待监管方审核
            registeredAt: now
        });
        _entityList.push(msg.sender);

        emit EntityRegistered(msg.sender, entityId, name, now);
    }

    /**
     * @notice 监管方审核主体：启用 / 停用
     */
    function setEntityStatus(address account, bool active) public onlyRegulator {
        require(_entities[account].registeredAt != 0, "RoleControl: entity not found");
        _entities[account].active = active;
        emit EntityStatusChanged(account, active, now);
    }

    /**
     * @notice 监管方授予角色
     */
    function grantRole(address account, uint8 role) public onlyRegulator {
        require(_entities[account].registeredAt != 0, "RoleControl: entity not found");
        require(!hasRole(account, role), "RoleControl: role already granted");
        _entities[account].roles |= role;
        emit RoleGranted(account, role, now);
    }

    /**
     * @notice 监管方撤销角色
     */
    function revokeRole(address account, uint8 role) public onlyRegulator {
        require(hasRole(account, role), "RoleControl: role not granted");
        _entities[account].roles &= ~role;
        emit RoleRevoked(account, role, now);
    }

    // ============ 查询 ============

    function hasRole(address account, uint8 role) public view returns (bool) {
        return (_entities[account].roles & role) == role;
    }

    function isActive(address account) public view returns (bool) {
        return _entities[account].active;
    }

    function getEntity(address account)
        public
        view
        returns (string entityId, string name, uint8 roles, bool active, uint256 registeredAt)
    {
        Entity storage e = _entities[account];
        return (e.entityId, e.name, e.roles, e.active, e.registeredAt);
    }

    function getEntityCount() public view returns (uint256) {
        return _entityList.length;
    }

    function getEntityAt(uint256 index) public view returns (address) {
        require(index < _entityList.length, "RoleControl: index out of range");
        return _entityList[index];
    }

    function transferRegulator(address newRegulator) public onlyRegulator {
        require(newRegulator != address(0), "RoleControl: invalid regulator");
        regulator = newRegulator;
    }
}
