# scripts — 运维脚本

| 脚本 | 用途 | 状态 |
| --- | --- | --- |
| `deploy_contract.sh` | 调用控制台批量部署合约并回填地址 | 待实现 |
| `init_data.sh` | 初始化测试主体与批次数据 | 待实现 |
| `check_env.sh` | 检查 JDK / Maven / Node / 节点连通性 | 待实现 |

## 约定

- 所有脚本需支持 `set -euo pipefail`，失败立即退出
- 涉及密钥的脚本从环境变量读取，不硬编码
- 脚本执行后输出的合约地址写入 `backend/src/main/resources/contract-address.properties`
