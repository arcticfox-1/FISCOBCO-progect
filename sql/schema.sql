-- =============================================================
-- 农产品质量安全溯源系统 数据库脚本
-- MySQL 8.0 / utf8mb4
-- 说明：链上存证 + 链下业务明细，两库通过 batch_id / tx_hash 关联
-- =============================================================

CREATE DATABASE IF NOT EXISTS agri_trace
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_general_ci;

USE agri_trace;

-- -------------------------------------------------------------
-- 1. 参与主体
-- -------------------------------------------------------------
DROP TABLE IF EXISTS t_entity;
CREATE TABLE t_entity (
  id            BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  entity_code   VARCHAR(64)  NOT NULL                COMMENT '主体编码（统一社会信用代码/机构代码）',
  entity_name   VARCHAR(128) NOT NULL                COMMENT '主体名称',
  entity_type   TINYINT      NOT NULL                COMMENT '类型：1生产主体 2检测机构 3物流企业 4销售商 5监管',
  chain_address VARCHAR(64)  NOT NULL                COMMENT '链上账户地址',
  contact       VARCHAR(64)           DEFAULT NULL   COMMENT '联系人',
  phone         VARCHAR(32)           DEFAULT NULL   COMMENT '联系电话',
  address       VARCHAR(255)          DEFAULT NULL   COMMENT '经营地址',
  status        TINYINT      NOT NULL DEFAULT 0      COMMENT '状态：0待审核 1已启用 2已停用',
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_entity_code (entity_code),
  UNIQUE KEY uk_chain_address (chain_address),
  KEY idx_entity_type (entity_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='参与主体';

-- -------------------------------------------------------------
-- 2. 用户
-- -------------------------------------------------------------
DROP TABLE IF EXISTS t_user;
CREATE TABLE t_user (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  username    VARCHAR(64)  NOT NULL COMMENT '登录账号',
  password    VARCHAR(128) NOT NULL COMMENT 'BCrypt 密文',
  real_name   VARCHAR(64)           DEFAULT NULL,
  entity_id   BIGINT                COMMENT '所属主体，监管人员可为空',
  role_code   VARCHAR(32)  NOT NULL COMMENT 'PRODUCER / INSPECTOR / LOGISTICS / SELLER / REGULATOR',
  chain_address VARCHAR(64)         DEFAULT NULL COMMENT '该用户对应的链上地址',
  status      TINYINT      NOT NULL DEFAULT 1 COMMENT '1正常 0禁用',
  last_login  DATETIME              DEFAULT NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_username (username),
  KEY idx_entity (entity_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='系统用户';

-- -------------------------------------------------------------
-- 3. 农产品
-- -------------------------------------------------------------
DROP TABLE IF EXISTS t_product;
CREATE TABLE t_product (
  id           BIGINT       NOT NULL AUTO_INCREMENT,
  product_name VARCHAR(128) NOT NULL COMMENT '产品名称',
  category     VARCHAR(64)           DEFAULT NULL COMMENT '品类',
  variety      VARCHAR(64)           DEFAULT NULL COMMENT '品种',
  spec         VARCHAR(64)           DEFAULT NULL COMMENT '规格',
  producer_id  BIGINT       NOT NULL COMMENT '生产主体',
  image_url    VARCHAR(255)          DEFAULT NULL,
  created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_producer (producer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='农产品';

-- -------------------------------------------------------------
-- 4. 批次（溯源主线）
-- -------------------------------------------------------------
DROP TABLE IF EXISTS t_batch;
CREATE TABLE t_batch (
  id            BIGINT       NOT NULL AUTO_INCREMENT,
  batch_id      VARCHAR(64)  NOT NULL COMMENT '批次号，业务唯一，同步上链',
  product_id    BIGINT       NOT NULL,
  product_name  VARCHAR(128) NOT NULL COMMENT '冗余，便于查询展示',
  origin        VARCHAR(255) NOT NULL COMMENT '产地',
  producer_id   BIGINT       NOT NULL COMMENT '生产主体',
  status        TINYINT      NOT NULL DEFAULT 0 COMMENT '0已登记 1种植中 2已采收 3检测合格 4检测不合格 5运输中 6已上架 7已售出 8已处置',
  qr_code       VARCHAR(255)          DEFAULT NULL COMMENT '溯源码内容',
  tx_hash       VARCHAR(80)           DEFAULT NULL COMMENT '登记交易哈希',
  block_number  BIGINT                DEFAULT NULL,
  chain_status  TINYINT      NOT NULL DEFAULT 0 COMMENT '上链状态：0待上链 1成功 2失败',
  remark        VARCHAR(255)          DEFAULT NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_batch_id (batch_id),
  KEY idx_producer (producer_id),
  KEY idx_status (status),
  KEY idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='农产品批次';

-- -------------------------------------------------------------
-- 5. 溯源业务记录
-- -------------------------------------------------------------
DROP TABLE IF EXISTS t_trace_record;
CREATE TABLE t_trace_record (
  id           BIGINT       NOT NULL AUTO_INCREMENT,
  batch_id     VARCHAR(64)  NOT NULL COMMENT '批次号',
  stage        TINYINT      NOT NULL COMMENT '1种植 2采收 3检测 4运输 5销售 6更正',
  operator_id  BIGINT       NOT NULL COMMENT '操作主体',
  operator_name VARCHAR(128)         DEFAULT NULL COMMENT '冗余主体名称',
  summary      VARCHAR(500) NOT NULL COMMENT '环节摘要',
  detail_json  JSON                  COMMENT '环节明细（温度、车辆、门店等）',
  file_url     VARCHAR(255)          DEFAULT NULL COMMENT '附件地址（报告/照片），链下保存',
  file_hash    VARCHAR(80)           DEFAULT NULL COMMENT '附件 SHA-256 摘要，上链',
  qualified    TINYINT      NOT NULL DEFAULT 1 COMMENT '检测结论：1合格 0不合格',
  ref_index    INT          NOT NULL DEFAULT 0 COMMENT '更正时指向的原链上记录下标',
  record_index INT                   COMMENT '本条记录在链上的下标',
  tx_hash      VARCHAR(80)           DEFAULT NULL COMMENT '交易哈希，作为存证凭证',
  block_number BIGINT                DEFAULT NULL,
  chain_status TINYINT      NOT NULL DEFAULT 0 COMMENT '0待上链 1成功 2失败',
  occur_time   DATETIME     NOT NULL COMMENT '业务发生时间',
  created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_batch (batch_id),
  KEY idx_stage (stage),
  KEY idx_operator (operator_id),
  KEY idx_occur (occur_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='溯源业务记录';

-- -------------------------------------------------------------
-- 6. 质检报告
-- -------------------------------------------------------------
DROP TABLE IF EXISTS t_inspection_report;
CREATE TABLE t_inspection_report (
  id            BIGINT       NOT NULL AUTO_INCREMENT,
  batch_id      VARCHAR(64)  NOT NULL,
  record_id     BIGINT                COMMENT '关联溯源记录',
  report_no     VARCHAR(64)  NOT NULL COMMENT '报告编号',
  inspector_id  BIGINT       NOT NULL COMMENT '检测机构',
  item_json     JSON                  COMMENT '检测项目与结果',
  conclusion    TINYINT      NOT NULL COMMENT '1合格 0不合格',
  file_path     VARCHAR(255) NOT NULL COMMENT '报告原件路径（链下）',
  file_hash     VARCHAR(80)  NOT NULL COMMENT '报告摘要（上链）',
  issued_at     DATETIME     NOT NULL COMMENT '出具时间',
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_report_no (report_no),
  KEY idx_batch (batch_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='质检报告';

-- -------------------------------------------------------------
-- 7. 不合格批次处置
-- -------------------------------------------------------------
DROP TABLE IF EXISTS t_disposal;
CREATE TABLE t_disposal (
  id           BIGINT       NOT NULL AUTO_INCREMENT,
  batch_id     VARCHAR(64)  NOT NULL,
  method       VARCHAR(255) NOT NULL COMMENT '处置方式：退回/销毁/转饲料等',
  regulator_id BIGINT       NOT NULL COMMENT '处置人',
  remark       VARCHAR(500)          DEFAULT NULL,
  tx_hash      VARCHAR(80)           DEFAULT NULL,
  disposed_at  DATETIME     NOT NULL,
  created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_batch (batch_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='不合格批次处置记录';

-- -------------------------------------------------------------
-- 8. 链上交易回执（存证凭证，失败不得显示为已存证）
-- -------------------------------------------------------------
DROP TABLE IF EXISTS t_chain_tx;
CREATE TABLE t_chain_tx (
  id           BIGINT       NOT NULL AUTO_INCREMENT,
  tx_hash      VARCHAR(80)  NOT NULL,
  block_number BIGINT                DEFAULT NULL,
  biz_type     VARCHAR(32)  NOT NULL COMMENT 'CREATE_BATCH / PLANTING / HARVEST / INSPECTION / TRANSPORT / SALES / CORRECTION / DISPOSE',
  batch_id     VARCHAR(64)           DEFAULT NULL,
  status       TINYINT      NOT NULL COMMENT '0已发送 1成功 2失败',
  error_msg    VARCHAR(500)          DEFAULT NULL COMMENT '失败原因（合约 revert 信息）',
  gas_used     BIGINT                DEFAULT NULL,
  created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_tx_hash (tx_hash),
  KEY idx_batch (batch_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='链上交易回执';

-- -------------------------------------------------------------
-- 9. 操作日志
-- -------------------------------------------------------------
DROP TABLE IF EXISTS t_oper_log;
CREATE TABLE t_oper_log (
  id         BIGINT       NOT NULL AUTO_INCREMENT,
  user_id    BIGINT                DEFAULT NULL,
  action     VARCHAR(64)  NOT NULL,
  target     VARCHAR(128)          DEFAULT NULL,
  result     TINYINT      NOT NULL DEFAULT 1 COMMENT '1成功 0失败',
  message    VARCHAR(500)          DEFAULT NULL,
  ip         VARCHAR(64)           DEFAULT NULL,
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_user (user_id),
  KEY idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='操作日志';
