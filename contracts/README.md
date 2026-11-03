# contracts — 智能合约

## 规划文件

| 文件 | 说明 | 状态 |
| --- | --- | --- |
| `RoleControl.sol` | 参与主体注册、角色授权、白名单校验 | 待实现 |
| `Traceability.sol` | 批次创建、溯源记录追加、完整性校验 | 待实现 |
| `TraceabilityFactory.sol` | 可选：按产品品类部署独立溯源合约实例 | 待实现 |

## 合约设计原则

1. **只追加不修改**：溯源记录写入后不可变更，保证历史可审计。
2. **权限前置**：写操作先校验 `hasRole(msg.sender, ROLE)`，未授权地址调用直接 revert。
3. **最小上链**：链上只存标识、时间戳、哈希、状态码，避免区块膨胀。
4. **事件完备**：每个状态变更抛 `event`，便于后端订阅与监管审计。

## 编译与部署

合约通过 FISCO BCOS 控制台（console）编译部署：

```bash
# 进入 console 目录
bash console.sh

# 部署
deploy Traceability
```

> 也可使用 `scripts/deploy_contract.sh` 批量部署（待补充）。

## 编码规范

- Solidity 版本与目标链一致（FISCO BCOS 2.9.x 推荐 `0.4.25` 或 `0.6.10`）
- 函数顺序：`external` → `public` → `internal` → `private`
- 所有外部调用做好重入与越权防护
