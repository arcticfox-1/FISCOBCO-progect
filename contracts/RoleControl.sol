pragma solidity ^0.4.25;

/**
 * @title RoleControl
 * @notice 参与主体注册与角色权限管理
 * @dev 仅监管方（ADMIN）可审核主体、授予角色。角色按位掩码存储，支持一址多角色。
 */
contract RoleControl {

    // ============ 角色定义（位掩码，可组合） ============
    uint8 public constant ROLE_ADMIN     = 1;   // 监管方
    uint8 public constant ROLE_FARMER    = 2;   // 农户 / 种植合作社
    uint8 public constant ROLE_PROCESSOR = 4;   // 加工企业
    uint8 public constant ROLE_LOGISTICS = 8;   // 物流企业
    uint8 public constant ROLE_SELLER    = 16;  // 销售终端

    // ============ 数据结构 ============
    struct Entity {
        string  entityId;     // 主体唯一编码（统一社会信用代码等）
        string  name;         // 主体名称
        uint8   roles;        // 角色位掩码
        bool    active;       // 是否启用（监管方审核通过）
        uint256 registeredAt; // 注册时间
    }

    address public admin;                          // 监管方合约管理员
    mapping(address => Entity) private _entities;  // 地址 => 主体信息
    address[] private _entityList;                 // 主体地址列表，便于遍历

    // ============ 事件 ============
    event EntityRegistered(address indexed account, string entityId, string name, uint256 timestamp);
    event RoleGranted(address indexed account, uint8 role, uint256 timestamp);
    event RoleRevoked(address indexed account, uint8 role, uint256 timestamp);
    event EntityStatusChanged(address indexed account, bool active, uint256 timestamp);

    // ============ 修饰器 ============
    modifier onlyAdmin() {
        require(msg.sender == admin, "RoleControl: caller is not admin");
        _;
    }

    modifier onlyActive() {
        require(_entities[msg.sender].active, "RoleControl: entity not active");
        _;
    }

    // ============ 构造 ============
    constructor() public {
        admin = msg.sender;
        _entities[msg.sender] = Entity({
            entityId: "REGULATOR",
            name: "Regulatory Authority",
            roles: ROLE_ADMIN,
            active: true,
            registeredAt: now
        });
        _entityList.push(msg.sender);
        emit EntityRegistered(msg.sender, "REGULATOR", "Regulatory Authority", now);
    }

    // ============ 主体管理 ============

    /**
     * @notice 注册新的参与主体（注册后需监管方审核启用）
     * @param entityId 主体唯一编码
     * @param name     主体名称
     * @param roles    初始角色位掩码
     */
    function registerEntity(string entityId, string name, uint8 roles) public {
        require(bytes(entityId).length > 0, "RoleControl: empty entityId");
        require(bytes(name).length > 0, "RoleControl: empty name");
        require(_entities[msg.sender].registeredAt == 0, "RoleControl: already registered");
        require(roles != ROLE_ADMIN, "RoleControl: cannot self-assign admin");

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
     * @notice 监管方审核主体，启用或停用
     */
    function setEntityStatus(address account, bool active) public onlyAdmin {
        require(_entities[account].registeredAt != 0, "RoleControl: entity not found");
        _entities[account].active = active;
        emit EntityStatusChanged(account, active, now);
    }

    /**
     * @notice 授予角色
     */
    function grantRole(address account, uint8 role) public onlyAdmin {
        require(_entities[account].registeredAt != 0, "RoleControl: entity not found");
        require(!hasRole(account, role), "RoleControl: role already granted");
        _entities[account].roles |= role;
        emit RoleGranted(account, role, now);
    }

    /**
     * @notice 撤销角色
     */
    function revokeRole(address account, uint8 role) public onlyAdmin {
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
}
