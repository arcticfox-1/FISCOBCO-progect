# backend — 后端服务

Spring Boot + FISCO BCOS Java SDK 的业务服务层，负责链上链下数据协同。

## 技术栈

- Java 8 / Spring Boot 2.7.18
- MyBatis-Plus 3.5.3.1 + MySQL 8.0
- Redis（缓存、登录态）
- `fisco-bcos-java-sdk` 2.9.1

## 规划包结构

```
com.fiscobcos.trace
├── TraceApplication.java
├── config/          # SDK 配置、跨域、拦截器
├── controller/      # REST 接口
├── service/         # 业务逻辑
│   └── impl/
├── blockchain/      # 合约调用封装、交易回执处理
├── entity/          # 数据库实体
├── mapper/          # MyBatis-Plus Mapper
├── dto/             # 请求/响应对象
├── common/          # 统一响应、异常、常量
└── util/            # 二维码、哈希、签名工具
```

## SDK 连接配置（application.yml 示例）

```yaml
fisco:
  channel:
    peers:
      - 127.0.0.1:20200
      - 127.0.0.1:20201
    ca-cert: classpath:conf/ca.crt
    ssl-cert: classpath:conf/sdk.crt
    ssl-key: classpath:conf/sdk.key
  group-id: 1
  contract:
    trace-address: "0x..."
```

## 核心服务职责

| 服务 | 职责 |
| --- | --- |
| `BatchService` | 批次登记，落链下明细 + 上链 + 回执校验 |
| `TraceService` | 种植/采收/运输/销售记录追加，按批次聚合全链路 |
| `InspectionService` | 报告上传、SHA-256 计算、质检结论上链 |
| `DisposalService` | 不合格批次处置，同步链上状态 |
| `VerifyService` | 用链上摘要与链下文件比对，返回完整性结论 |
| `ChainTxService` | 交易回执统一处理，失败落库并回滚业务状态 |
| `QrCodeService` | 生成携带 `batchId` 的溯源码（小程序页面路径） |

## 本地启动

```bash
mvn clean package -DskipTests
java -jar target/trace-backend-1.0.0.jar --spring.profiles.active=local
```

> 启动前需将 `ca.crt` / `sdk.crt` / `sdk.key` 放入 `src/main/resources/conf/`，并确保链上节点已运行、合约已部署。
