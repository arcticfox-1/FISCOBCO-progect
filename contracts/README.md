# contracts — 智能合约

## 文件

| 文件 | 说明 | 状态 |
| --- | --- | --- |
| `RoleControl.sol` | 主体注册、监管审核、角色授予/撤销、权限查询 | ✅ 已实现 |
| `Traceability.sol` | 批次唯一登记、五环节记录、状态机、更正、不合格处置 | ✅ 已实现 |
| `TraceabilityFactory.sol` | 可选：按品类部署独立溯源实例（演示规模不需要） | ⬜ 暂不实现 |

## 角色位掩码

| 角色 | 值 | 可写环节 |
| --- | --- | --- |
| `ROLE_REGULATOR` | 1 | 处置不合格批次、发起更正、审核主体 |
| `ROLE_PRODUCER` | 2 | 登记批次、种植、采收 |
| `ROLE_INSPECTOR` | 4 | 提交质检结论 |
| `ROLE_LOGISTICS` | 8 | 运输交接 |
| `ROLE_SELLER` | 16 | 上架、销售 |

可叠加：`2 | 16 = 18` 表示既生产又自销。

## 环节与状态

| 环节 | 值 | 前置状态 | 写入后状态 | 允许角色 |
| --- | --- | --- | --- | --- |
| 种植 | 1 | 已登记(0) / 种植中(1) | 种植中(1) | 生产 |
| 采收 | 2 | 种植中(1) | 已采收(2) | 生产 |
| 检测 | 3 | 已采收(2) | 合格(3) / 不合格(4) | 检测 |
| 运输 | 4 | 合格(3) | 运输中(5) | 物流 |
| 销售 | 5 | 合格(3) / 运输中(5) / 已上架(6) | 已上架(6) / 已售出(7) | 销售 |
| 更正 | 6 | 任意 | 状态不变 | 原操作人 / 监管 |
| 处置 | — | 不合格(4) | 已处置(8) | 监管 |

## 设计原则

1. **只追加不修改**：无修改/删除接口，录入错误通过 `addCorrection` 追加更正（`refIndex` 指向原记录）。
2. **权限前置**：写操作先校验 `isActive` + `hasRole`，未授权直接 revert。
3. **状态驱动**：跳步、倒序、不合格流入销售全部在合约层拦截。
4. **最小上链**：只存标识、地址、时间、状态、`bytes32` 摘要。
5. **事件完备**：`BatchCreated` / `TraceRecordAdded` / `InspectionSubmitted` / `CorrectionAdded` / `BatchStatusChanged` / `BatchDisposed`。

## 编译与部署

使用 FISCO BCOS 控制台（与节点 2.9.1 配套）：

```bash
cd deploy/console
bash console.sh

[group:1]> deploy RoleControl
contract address: 0x1234...

[group:1]> deploy Traceability 0x1234...
contract address: 0x5678...
```

部署后把两个地址写入 `backend/src/main/resources/contract-address.properties`。

## 调用示例（控制台验证用）

```bash
# 查询批次
[group:1]> call Traceability 0x5678... getBatch "AG20260312001"

# 校验摘要
[group:1]> call Traceability 0x5678... verifyDigest "AG20260312001" 0 0x8f3a...

# 越权测试（用销售角色地址调用种植）
[group:1]> call Traceability 0x5678... addTraceRecord "AG..." 1 "test" 0x1234 --private-key <seller_key>
# 预期回滚：insufficient role
```

## 编码规范

- `pragma` 固定 `^0.4.25`，与控制台默认编译器一致；
- 函数顺序：`external` → `public` → `internal` → `private`；
- 所有 `require` 携带英文错误信息，便于后端解析回执失败原因；
- 修改合约后必须重新部署，地址变更同步更新后端配置。
