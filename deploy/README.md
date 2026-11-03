# deploy — 联盟链部署

本目录存放 FISCO BCOS 联盟链的搭建脚本与节点配置说明。

## 网络规划

| 机构 | 节点 | 端口（P2P / Channel / RPC） | 职责 |
| --- | --- | --- | --- |
| 监管部门 | node0 | 30300 / 20200 / 8545 | 共识 + 主体审核 |
| 生产企业 | node1 | 30301 / 20201 / 8546 | 共识 + 生产数据上链 |
| 物流企业 | node2 | 30302 / 20202 / 8547 | 共识 + 运输数据上链 |
| 销售企业 | node3 | 30303 / 20203 / 8548 | 共识 + 销售数据上链 |

## 单机四节点快速搭建

```bash
# 下载建链脚本
curl -#LO https://github.com/FISCO-BCOS/FISCO-BCOS/releases/download/v2.9.1/build_chain.sh
chmod +x build_chain.sh

# 生成四节点
bash build_chain.sh -l 127.0.0.1:4 -p 30300,20200,8545

# 启动
bash nodes/127.0.0.1/start_all.sh

# 检查进程
ps -ef | grep -v grep | grep fisco-bcos
```

## 推荐目录约定（不入库）

```
deploy/
├── build_chain.sh
├── nodes/              # 生成的节点目录，已加入 .gitignore
│   └── 127.0.0.1/
├── console/            # FISCO BCOS 控制台
└── cert/               # SDK 证书（严禁提交）
```

> ⚠️ **安全提示**：`nodes/`、`*.key`、`*.crt`、`*.pem` 已在 `.gitignore` 中排除。任何私钥、节点证书都不得提交到公开仓库。

## 证书分发

后端 SDK 连接链需要三个文件，从节点目录拷贝：

```bash
cp nodes/127.0.0.1/sdk/ca.crt   backend/src/main/resources/conf/
cp nodes/127.0.0.1/sdk/sdk.crt  backend/src/main/resources/conf/
cp nodes/127.0.0.1/sdk/sdk.key  backend/src/main/resources/conf/
```

这三个文件同样不入库，由部署人员本地拷贝或通过配置中心下发。
