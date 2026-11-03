# 基于 FISCO BCOS 联盟链的农产品质量安全溯源系统

> Agricultural Product Quality & Safety Traceability System Based on FISCO BCOS Consortium Blockchain

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![FISCO BCOS](https://img.shields.io/badge/FISCO%20BCOS-2.9.x-green.svg)](https://fisco-bcos-documentation.readthedocs.io/)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-2.7.x-brightgreen.svg)](https://spring.io/projects/spring-boot)
[![Vue](https://img.shields.io/badge/Vue-3.x-42b883.svg)](https://vuejs.org/)
[![WeChat](https://img.shields.io/badge/MiniProgram-WeChat-07c160.svg)](https://developers.weixin.qq.com/miniprogram/dev/framework/)

---

## 一、项目简介

本项目面向农产品"从农田到餐桌"的全链条质量安全管理需求，采用 **FISCO BCOS 联盟链** 作为底层可信基础设施，将种植、加工、仓储、物流、销售等环节的关键质量数据上链存证，实现**数据不可篡改、全程可追溯、责任可界定**。

消费者通过微信小程序扫描产品溯源码即可查看完整流转链路与质检报告；监管部门可对全链路数据进行审计核验；链上采用多机构节点共识，避免单一主体既当"运动员"又当"裁判员"的数据信任问题。

### 解决的核心问题

| 传统溯源痛点 | 本方案的技术应对 |
| --- | --- |
| 中心化数据库可被单方修改，溯源结果不可信 | 关键数据上链存证，哈希写入区块，篡改需攻破多数节点 |
| 参与主体互不信任，数据难以共享 | 联盟链多机构节点，准入许可 + 共识机制建立信任 |
| 溯源信息碎片化，链条断裂 | 统一数据模型，按批次 `batchId` 串联全生命周期 |
| 消费者无法验证真伪 | 小程序端可校验链上哈希与报告一致性 |

---

## 二、系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                        应用层 Application                     │
│   微信小程序（消费者溯源）│ Vue 管理后台（企业/监管）            │
└───────────────┬─────────────────────────┬───────────────────┘
                │ HTTPS / REST            │
┌───────────────▼─────────────────────────▼───────────────────┐
│                   服务层 Backend (Spring Boot)                │
│  · 业务接口  · 身份鉴权  · 链上/链下数据协同  · 二维码生成      │
│  · FISCO BCOS Java SDK  · 交易签名与回执解析                  │
└───────────────────────────┬─────────────────────────────────┘
                            │ Channel RPC / SDK
┌───────────────────────────▼─────────────────────────────────┐
│                  区块链层 FISCO BCOS 联盟链                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│  │ 监管节点  │  │ 生产节点  │  │ 物流节点  │  │ 销售节点  │     │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘     │
│  智能合约：角色权限 / 批次管理 / 溯源记录 / 质检存证            │
└─────────────────────────────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│              链下存储 Off-chain (MySQL + 对象存储)             │
│   业务明细、图片/视频、质检报告原件；仅哈希与关键字段上链        │
└─────────────────────────────────────────────────────────────┘
```

### 链上链下协同原则

- **链上**：批次标识、主体标识、环节类型、时间戳、数据哈希、操作人签名 —— 保证可信与轻量。
- **链下**：大文本、图片、PDF 报告等，仅存 `SHA-256` 摘要上链，兼顾性能与可验证性。

---

## 三、目录结构

```
fiscobcos/
├── contracts/          # 智能合约（Solidity）及编译脚本
│   ├── Traceability.sol        # 溯源核心合约
│   ├── RoleControl.sol         # 角色与权限合约
│   └── README.md
├── backend/            # 后端服务（Spring Boot + FISCO BCOS Java SDK）
│   └── README.md
├── frontend/           # 管理后台（Vue 3 + Element Plus）
│   └── README.md
├── miniprogram/        # 消费者端（微信小程序）
│   └── README.md
├── deploy/             # 联盟链搭建：节点配置、证书、启动脚本
│   └── README.md
├── scripts/            # 合约部署、数据初始化等运维脚本
├── docs/               # 需求、设计、接口、测试文档
├── .gitignore
├── LICENSE
└── README.md
```

---

## 四、核心业务流程

```
农户/合作社          加工企业           物流企业           销售终端          消费者
     │                   │                  │                 │                │
  ① 建档上链          ② 加工记录         ③ 运输记录        ④ 上架销售      ⑤ 扫码溯源
  种植批次            质检报告            温湿度             批次关联        查看全链路
     │                   │                  │                 │                │
     └───────────────────┴──────────────────┴─────────────────┘                │
                    所有环节写入同一 batchId 溯源链 ──────────────────────────►│
```

1. **生产环节**：农户录入地块、品种、施肥/用药记录，生成批次号并上链。
2. **加工环节**：加工企业补充加工工艺、质检报告哈希，形成流转记录。
3. **物流环节**：物流企业记录承运信息、冷链温湿度，异常自动告警。
4. **销售环节**：销售终端绑定批次与门店，生成消费者可扫的溯源码。
5. **消费溯源**：小程序扫码 → 后端按 `batchId` 聚合链上记录 → 逐环节展示并校验哈希。

---

## 五、智能合约设计（概要）

| 合约 | 职责 | 关键方法 |
| --- | --- | --- |
| `RoleControl.sol` | 主体注册与角色授权（农户/加工/物流/销售/监管） | `registerEntity` `grantRole` `hasRole` |
| `Traceability.sol` | 批次创建、环节记录追加、溯源查询 | `createBatch` `addTraceRecord` `getTraceRecords` `verifyHash` |

**设计要点**

- 采用 **RBAC + 主体白名单**，只有通过监管方审核的机构地址才可写入数据。
- 溯源记录采用**追加式（append-only）**结构，历史记录不可修改、不可删除。
- 每条记录存 `dataHash`，配合链下原文实现完整性校验。
- 关键事件通过 `event` 抛出发送，便于后端订阅与审计。

---

## 六、技术栈

| 层次 | 技术选型 |
| --- | --- |
| 联盟链 | FISCO BCOS 2.9.x（PBFT 共识，4 节点） |
| 智能合约 | Solidity 0.4.25 / 0.6.10 |
| 后端 | Java 17、Spring Boot 2.7、MyBatis-Plus、fisco-bcos-java-sdk 2.9.x |
| 数据库 | MySQL 8.0、Redis（缓存/会话） |
| 管理后台 | Vue 3、Vite、Element Plus、ECharts |
| 消费者端 | 微信小程序原生框架 |
| 部署 | Docker / 宝塔、Nginx |

---

## 七、快速开始

### 7.1 环境准备

- JDK 17+、Maven 3.8+
- Node.js 18+、npm / pnpm
- MySQL 8.0
- FISCO BCOS 2.9.x 节点（本地单机或使用 `build_chain.sh` 搭建）
- 微信开发者工具

### 7.2 搭建联盟链

```bash
cd deploy
bash build_chain.sh -l 127.0.0.1:4 -p 30300,20200,8545
bash nodes/127.0.0.1/start_all.sh
```

### 7.3 部署合约

```bash
# 依赖 FISCO BCOS 控制台 console
cd scripts
bash deploy_contract.sh
```

### 7.4 启动后端

```bash
cd backend
mvn clean package -DskipTests
java -jar target/*.jar
```

### 7.5 启动管理后台

```bash
cd frontend
npm install
npm run dev
```

### 7.6 运行小程序

用微信开发者工具导入 `miniprogram/` 目录，修改 `app.js` 中的后端地址后即可预览。

---

## 八、接口约定（示例）

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/api/auth/login` | 主体登录 |
| POST | `/api/batch` | 创建农产品批次 |
| POST | `/api/trace/record` | 追加溯源环节记录 |
| GET | `/api/trace/{batchId}` | 查询完整溯源链路 |
| GET | `/api/trace/verify/{batchId}` | 校验链上数据完整性 |
| GET | `/api/qrcode/{batchId}` | 生成溯源码 |

统一响应结构：

```json
{
  "code": 200,
  "message": "success",
  "data": {}
}
```

---

## 九、开发进度

- [x] 项目初始化与仓库搭建
- [ ] 联盟链节点部署与网络连通验证
- [ ] 智能合约编写与单元测试
- [ ] 后端接口开发与 SDK 集成
- [ ] 管理后台页面开发
- [ ] 微信小程序溯源页开发
- [ ] 系统联调与性能测试
- [ ] 文档整理与答辩材料准备

---

## 十、文档

| 文档 | 说明 |
| --- | --- |
| [docs/需求分析.md](docs/需求分析.md) | 业务需求与用例 |
| [docs/系统设计.md](docs/系统设计.md) | 架构与数据库设计 |
| [docs/接口文档.md](docs/接口文档.md) | RESTful 接口定义 |
| [docs/部署手册.md](docs/部署手册.md) | 环境搭建与上线步骤 |

---

## 十一、贡献与协作

```bash
git clone https://gitee.com/arctic-fox-1/fiscobcos.git
cd fiscobcos
git checkout -b feature/your-feature
# 开发...
git commit -m "feat: 新增溯源链路查询接口"
git push origin feature/your-feature
```

提交信息遵循 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/)：`feat` / `fix` / `docs` / `refactor` / `test` / `chore`。

---

## 十二、许可证

本项目采用 [MIT License](LICENSE) 开源。

---

## 十三、致谢

- [FISCO BCOS](https://github.com/FISCO-BCOS/FISCO-BCOS) — 国产开源联盟链底层平台
- [FISCO BCOS 文档](https://fisco-bcos-documentation.readthedocs.io/)
- [WeBASE](https://github.com/WeBankBlockchain/WeBASE) — 区块链中间件参考

> 本项目为设计与实现类课题成果，仅用于学习与研究，生产环境使用请自行完成安全评估与合规审查。
