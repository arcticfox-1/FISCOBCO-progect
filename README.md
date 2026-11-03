# 基于 FISCO BCOS 联盟链的农产品质量安全溯源系统

> Agricultural Product Quality & Safety Traceability System Based on FISCO BCOS Consortium Blockchain

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![FISCO BCOS](https://img.shields.io/badge/FISCO%20BCOS-2.9.1-green.svg)](https://fisco-bcos-documentation.readthedocs.io/)
[![Solidity](https://img.shields.io/badge/Solidity-0.4.25-363636.svg)](https://solidity.readthedocs.io/)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-2.7.18-brightgreen.svg)](https://spring.io/projects/spring-boot)
[![Vue](https://img.shields.io/badge/Vue-3.4-42b883.svg)](https://vuejs.org/)
[![WeChat](https://img.shields.io/badge/MiniProgram-WeChat-07c160.svg)](https://developers.weixin.qq.com/miniprogram/dev/framework/)

---

## 一、项目简介

以**一种农产品**为对象、以**批次**为主线，打通「种植 → 采收 → 检测 → 运输 → 销售」五个环节，将关键质量数据摘要写入 **FISCO BCOS 联盟链**，实现全程可追溯、数据不可篡改、责任可界定、异常可处置。

消费者扫码即可查看完整履历与质检报告摘要；监管方可审计全链、处置不合格批次并追查上下游。

### 解决的核心问题

| 传统溯源痛点 | 本方案的技术应对 |
| --- | --- |
| 中心化数据库可被单方修改 | 关键记录上链，交易回执可核验，篡改需攻破多数节点 |
| 参与主体互不信任 | 联盟链多机构节点 + 准入审核 + 角色位掩码授权 |
| 溯源信息碎片化 | 统一以 `batchId` 串联五环节，状态机保证流程完整 |
| 不合格品流入市场 | 检测不合格即锁定状态，合约层面拒绝运输与销售 |

> **边界声明**：本系统为教学实训成果，业务数据为人工模拟录入，不接入真实物联网设备；链上存证仅证明"记录在何时由谁提交且未被篡改"，**不等同于实物质量证明**。

---

## 二、系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                        接入层                                 │
│   Vue 3 管理端（生产/检测/物流/销售/监管）                     │
│   微信小程序（消费者扫码溯源）                                 │
└───────────────┬─────────────────────────┬───────────────────┘
                │ HTTPS + JWT             │
┌───────────────▼─────────────────────────▼───────────────────┐
│                服务层 Spring Boot 2.7 (JDK 8)                 │
│  Controller → Service → ChainService → FISCO BCOS Java SDK    │
│  · 鉴权与角色拦截 · 状态机校验 · 文件摘要 · 二维码 · 回执处理   │
└───────────────┬─────────────────────────┬───────────────────┘
                │ JDBC                    │ Channel RPC
┌───────────────▼──────────────┐  ┌───────▼─────────────────────┐
│  MySQL 8.0（链下明细）        │  │  FISCO BCOS 2.9.1（4 节点） │
│  批次/记录/报告/回执/日志     │  │  RoleControl + Traceability  │
│  报告原件与图片存本地/MinIO   │  │  PBFT 共识 · 单群组          │
└──────────────────────────────┘  └─────────────────────────────┘
```

### 链上链下协同

- **链上**：批次号、主体地址、业务时间、状态、环节摘要、文件 SHA-256 —— 保证可信且轻量；
- **链下**：明细 JSON、质检报告 PDF、图片、交易回执索引 —— 兼顾存储与性能。

---

## 三、目录结构

```
fiscobcos/
├── contracts/                # 智能合约（Solidity 0.4.25）
│   ├── RoleControl.sol       # 主体注册、监管审核、角色授权
│   └── Traceability.sol      # 批次登记、五环节记录、状态机、更正、处置
├── backend/                  # Spring Boot 服务（Java SDK 接入链）
├── frontend/                 # Vue 3 管理端
├── miniprogram/              # 微信小程序（扫码溯源）
├── deploy/                   # 4 节点联盟链搭建与证书
├── sql/                      # 数据库脚本（schema.sql）
├── scripts/                  # 部署、初始化数据脚本
├── docs/                     # 需求、设计、技术栈、计划、测试
├── .gitignore
├── LICENSE
└── README.md
```

---

## 四、业务主线

```
生产主体          检测机构          物流企业         销售商        消费者
   │                 │                 │               │             │
 ①登记批次          │                 │               │             │
 ②种植记录          │                 │               │             │
 ③采收记录          │                 │               │             │
   ├────────────────►④质检（合格/不合格）              │             │
   │                 │  不合格 → 监管处置 ⑧            │             │
   │                 ├────────────────►⑤运输交接       │             │
   │                 │                 ├──────────────►⑥上架销售    │
   │                 │                 │               │     ⑦扫码  │
   └─────────────────┴─────────────────┴───────────────┴────────────►│
                        全链路按 batchId 串联，时间正序展示
```

### 批次状态机

```
已登记(0) → 种植中(1) → 已采收(2) → 合格(3) → 运输中(5) → 已上架(6) → 已售出(7)
                              └────→ 不合格(4) → 已处置(8)
```

> 未采收不能检测；不合格不能运输、不能销售；状态只能前进，不可回退。

---

## 五、智能合约

| 合约 | 职责 | 关键方法 |
| --- | --- | --- |
| `RoleControl.sol` | 主体注册、监管审核、角色授权（位掩码） | `registerEntity` `setEntityStatus` `grantRole` `hasRole` |
| `Traceability.sol` | 批次唯一登记、记录追加、状态流转、更正、处置 | `createBatch` `addTraceRecord` `submitInspection` `addCorrection` `disposeBatch` |

**角色位掩码**：`1` 监管 / `2` 生产 / `4` 检测 / `8` 物流 / `16` 销售，可叠加。

**三条铁律**

1. **批次唯一**：`batchId` 已存在直接 revert，数据库唯一索引双保险；
2. **只追加不修改**：没有任何改/删接口，录入错误用 `addCorrection` 追加更正记录（`refIndex` 指向原记录）；
3. **状态驱动**：能否继续由链上状态决定，不合格批次在合约层就无法进入销售。

---

## 六、技术栈

| 层次 | 选型 | 版本 |
| --- | --- | --- |
| 联盟链 | FISCO BCOS | 2.9.1（4 节点 PBFT） |
| 合约 | Solidity | 0.4.25 |
| 后端 | Spring Boot + MyBatis-Plus | 2.7.18 / 3.5.3.1，JDK 8 |
| 链 SDK | fisco-bcos-java-sdk | 2.9.1 |
| 数据库 | MySQL | 8.0 |
| 前端 | Vue 3 + Vite + Element Plus | 3.4 / 5.x / 2.7 |
| 消费者端 | 微信小程序原生 | — |
| 二维码 | ZXing | 3.5.2 |

完整选型理由、依赖坐标与环境自检见 [docs/技术栈.md](docs/技术栈.md)。

---

## 七、快速开始

```bash
# 1. 建链（4 节点单群组）
cd deploy
bash build_chain.sh -l 127.0.0.1:4 -p 30300,20200,8545
bash nodes/127.0.0.1/start_all.sh
ps -ef | grep fisco-bcos        # 确认 4 个进程

# 2. 建库
mysql -uroot -p < sql/schema.sql

# 3. 部署合约（使用 FISCO BCOS 控制台）
cd deploy/console && bash console.sh
[group:1]> deploy RoleControl
[group:1]> deploy Traceability <RoleControl地址>

# 4. 后端
cd backend && mvn clean package -DskipTests && java -jar target/*.jar

# 5. 前端
cd frontend && npm install && npm run dev

# 6. 小程序：微信开发者工具导入 miniprogram/，改 app.js 中的 baseUrl
```

> 启动后端前，需从 `deploy/nodes/127.0.0.1/sdk/` 拷贝 `ca.crt`、`sdk.crt`、`sdk.key` 到 `backend/src/main/resources/conf/`。这三个文件已被 `.gitignore` 排除，**严禁提交**。

---

## 八、接口概览

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/api/auth/login` | 登录，返回 JWT |
| POST | `/api/batch` | 登记批次（上链） |
| POST | `/api/trace/planting` | 种植记录 |
| POST | `/api/trace/harvest` | 采收记录 |
| POST | `/api/inspection` | 提交质检（含报告上传） |
| POST | `/api/trace/transport` | 运输交接 |
| POST | `/api/trace/sales` | 销售登记 |
| POST | `/api/trace/correction` | 追加更正 |
| POST | `/api/batch/{batchId}/dispose` | 不合格处置 |
| GET | `/api/trace/{batchId}` | 完整溯源履历（公开） |
| GET | `/api/trace/{batchId}/verify` | 摘要完整性校验 |
| GET | `/api/qrcode/{batchId}` | 生成溯源码 |

完整清单见 [docs/系统设计.md](docs/系统设计.md)。

---

## 九、开发进度

- [x] 需求分析与总体设计
- [x] 数据库表结构
- [x] 智能合约（角色 + 溯源 + 状态机 + 更正 + 处置）
- [ ] 联盟链 4 节点部署与连通验证
- [ ] 合约编译、部署与单元测试
- [ ] 后端接口与 SDK 集成
- [ ] 管理端页面
- [ ] 小程序溯源页
- [ ] 10 批次测试数据准备
- [ ] 集成测试与异常场景验证
- [ ] 部署手册与实训报告

---

## 十、文档索引

| 文档 | 内容 |
| --- | --- |
| [docs/需求分析.md](docs/需求分析.md) | 角色权限矩阵、业务流程、23 项功能需求、测试矩阵 |
| [docs/系统设计.md](docs/系统设计.md) | 架构、链上结构、状态机、数据库关系、接口清单、时序 |
| [docs/技术栈.md](docs/技术栈.md) | 选型理由、版本对齐、依赖坐标、环境自检 |
| [docs/开发计划.md](docs/开发计划.md) | 100 学时六阶段任务拆解与里程碑 |
| [docs/测试方案.md](docs/测试方案.md) | 10 条用例、测试数据规格、报告模板 |
| [sql/schema.sql](sql/schema.sql) | 9 张核心表建表语句 |
| [contracts/README.md](contracts/README.md) | 合约设计说明与编译部署 |

---

## 十一、协作约定

```bash
git clone https://gitee.com/arctic-fox-1/fiscobcos.git
cd fiscobcos
git checkout -b feature/your-feature
git commit -m "feat(trace): 新增采收记录接口"
git push origin feature/your-feature
```

提交信息遵循 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/)：`feat` / `fix` / `docs` / `refactor` / `test` / `chore`。

**禁止提交**：`*.key`、`*.crt`、`*.pem`、`nodes/`、`application-local.yml`、任何真实账号密码。

---

## 十二、许可证

[MIT License](LICENSE)

---

## 十三、致谢

- [FISCO BCOS](https://github.com/FISCO-BCOS/FISCO-BCOS) — 国产开源联盟链底层
- [FISCO BCOS 文档](https://fisco-bcos-documentation.readthedocs.io/)
- [WeBASE](https://github.com/WeBankBlockchain/WeBASE) — 区块链中间件参考
