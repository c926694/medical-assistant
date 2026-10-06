-- 医疗健康查询助手数据库初始化脚本
-- 适用 MySQL 8，字符集 utf8mb4
-- 表结构唯一来源；语义事实与情景经历记忆存 ChromaDB，不在本脚本中

CREATE DATABASE IF NOT EXISTS `medical_assistant`
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE `medical_assistant`;

-- 医院
CREATE TABLE IF NOT EXISTS `hospitals` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name`       VARCHAR(100) NOT NULL COMMENT '医院名称',
  `level`      ENUM('TERTIARY_A','TERTIARY','SECONDARY','PRIMARY') NOT NULL COMMENT '医院等级',
  `address`    VARCHAR(255) NULL COMMENT '地址',
  `phone`      VARCHAR(20) NULL COMMENT '联系电话',
  `intro`      TEXT NULL COMMENT '医院简介',
  `is_active`  TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='医院';

-- 科室
CREATE TABLE IF NOT EXISTS `departments` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `hospital_id` INT UNSIGNED NOT NULL COMMENT '所属医院',
  `name`        VARCHAR(100) NOT NULL COMMENT '科室名称',
  `intro`       TEXT NULL COMMENT '科室介绍',
  `is_active`   TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用',
  PRIMARY KEY (`id`),
  KEY `idx_departments_hospital_id` (`hospital_id`),
  CONSTRAINT `fk_departments_hospital` FOREIGN KEY (`hospital_id`) REFERENCES `hospitals` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='科室';

-- 症状到科室的映射
CREATE TABLE IF NOT EXISTS `department_symptom_mappings` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `department_id`   INT UNSIGNED NOT NULL COMMENT '科室',
  `symptom_keyword` VARCHAR(50) NOT NULL COMMENT '症状关键词',
  `weight`          INT NOT NULL DEFAULT 1 COMMENT '权重',
  PRIMARY KEY (`id`),
  KEY `idx_department_symptom_mappings_department_id` (`department_id`),
  CONSTRAINT `fk_department_symptom_mappings_department` FOREIGN KEY (`department_id`) REFERENCES `departments` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='症状到科室的映射';

-- 医生
CREATE TABLE IF NOT EXISTS `doctors` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `hospital_id`   INT UNSIGNED NOT NULL COMMENT '所属医院',
  `department_id` INT UNSIGNED NOT NULL COMMENT '所属科室',
  `name`          VARCHAR(50) NOT NULL COMMENT '姓名',
  `gender`        ENUM('MALE','FEMALE') NOT NULL COMMENT '性别',
  `title`         ENUM('CHIEF_PHYSICIAN','ASSOCIATE_CHIEF','ATTENDING','RESIDENT') NOT NULL COMMENT '职称',
  `specialty`     TEXT NULL COMMENT '擅长领域',
  `intro`         TEXT NULL COMMENT '医生简介',
  `avatar_url`    VARCHAR(255) NULL COMMENT '头像地址',
  `is_active`     TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用',
  `created_at`    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_doctors_hospital_id` (`hospital_id`),
  KEY `idx_doctors_department_id` (`department_id`),
  CONSTRAINT `fk_doctors_hospital` FOREIGN KEY (`hospital_id`) REFERENCES `hospitals` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_doctors_department` FOREIGN KEY (`department_id`) REFERENCES `departments` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='医生';

-- 医生评价
CREATE TABLE IF NOT EXISTS `doctor_reviews` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `doctor_id`      INT UNSIGNED NOT NULL COMMENT '医生',
  `user_id`        INT UNSIGNED NOT NULL COMMENT '评价用户',
  `appointment_id` INT UNSIGNED NULL COMMENT '关联挂号订单',
  `rating`         INT NOT NULL COMMENT '评分 1-5',
  `content`        TEXT NULL COMMENT '评价内容',
  `created_at`     DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_doctor_reviews_doctor_id` (`doctor_id`),
  CONSTRAINT `fk_doctor_reviews_doctor` FOREIGN KEY (`doctor_id`) REFERENCES `doctors` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='医生评价';

-- 医生排班与号源
CREATE TABLE IF NOT EXISTS `doctor_schedules` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `doctor_id`     INT UNSIGNED NOT NULL COMMENT '医生',
  `department_id` INT UNSIGNED NOT NULL COMMENT '科室',
  `schedule_date` DATE NOT NULL COMMENT '出诊日期',
  `period`        ENUM('MORNING','AFTERNOON','EVENING') NOT NULL COMMENT '时段',
  `start_time`    VARCHAR(10) NOT NULL COMMENT '开始时间 HH:mm',
  `end_time`      VARCHAR(10) NOT NULL COMMENT '结束时间 HH:mm',
  `total_slots`   INT NOT NULL COMMENT '总号源数',
  `booked_slots`  INT NOT NULL DEFAULT 0 COMMENT '已预约号源数',
  `fee`           INT NOT NULL COMMENT '挂号费，单位分',
  `status`        ENUM('OPEN','CLOSED','FULL') NOT NULL DEFAULT 'OPEN' COMMENT '号源状态',
  `created_at`    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_doctor_schedules_doctor_date_period` (`doctor_id`,`schedule_date`,`period`),
  KEY `idx_doctor_schedules_doctor_date` (`doctor_id`,`schedule_date`),
  CONSTRAINT `fk_doctor_schedules_doctor` FOREIGN KEY (`doctor_id`) REFERENCES `doctors` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='医生排班与号源';

-- 用户账号
CREATE TABLE IF NOT EXISTS `users` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `phone`         VARCHAR(20) NOT NULL COMMENT '手机号',
  `password_hash` VARCHAR(255) NOT NULL COMMENT '密码哈希',
  `real_name`     VARCHAR(50) NOT NULL COMMENT '真实姓名',
  `id_card_no`    VARCHAR(255) NOT NULL COMMENT '身份证号，加密存储',
  `created_at`    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_users_phone` (`phone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='用户账号';

-- 就诊人
CREATE TABLE IF NOT EXISTS `patients` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`      INT UNSIGNED NOT NULL COMMENT '所属账号',
  `name`         VARCHAR(50) NOT NULL COMMENT '姓名',
  `gender`       ENUM('MALE','FEMALE') NOT NULL COMMENT '性别',
  `birth_date`   DATE NOT NULL COMMENT '出生日期',
  `id_card_no`   VARCHAR(255) NOT NULL COMMENT '身份证号，加密存储',
  `phone`        VARCHAR(20) NULL COMMENT '联系电话',
  `relationship` ENUM('SELF','SPOUSE','CHILD','PARENT','OTHER') NOT NULL COMMENT '与账号关系',
  `is_default`   TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否默认就诊人',
  `created_at`   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_patients_user_id` (`user_id`),
  CONSTRAINT `fk_patients_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='就诊人';

-- 挂号订单
CREATE TABLE IF NOT EXISTS `appointments` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `appointment_no`  VARCHAR(40) NOT NULL COMMENT '挂号单号',
  `user_id`         INT UNSIGNED NOT NULL COMMENT '下单账号',
  `patient_id`      INT UNSIGNED NOT NULL COMMENT '就诊人',
  `hospital_id`     INT UNSIGNED NOT NULL COMMENT '医院',
  `department_id`   INT UNSIGNED NOT NULL COMMENT '科室',
  `doctor_id`       INT UNSIGNED NOT NULL COMMENT '医生',
  `schedule_id`     INT UNSIGNED NOT NULL COMMENT '排班号源',
  `fee`             INT NOT NULL COMMENT '挂号费，单位分',
  `queue_no`        INT UNSIGNED NULL COMMENT '就诊序号',
  `status`          ENUM('PENDING','PAID','CONFIRMED','CANCELLED','VISITED') NOT NULL DEFAULT 'PENDING' COMMENT '订单状态',
  `auto_registered` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否自动挂号',
  `expire_at`       DATETIME(3) NULL COMMENT '待支付超时时间',
  `cancelled_at`    DATETIME(3) NULL COMMENT '取消时间',
  `cancel_reason`   VARCHAR(255) NULL COMMENT '取消原因',
  `created_at`      DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_appointments_appointment_no` (`appointment_no`),
  KEY `idx_appointments_user_id` (`user_id`),
  KEY `idx_appointments_patient_id` (`patient_id`),
  KEY `idx_appointments_doctor_id` (`doctor_id`),
  KEY `idx_appointments_status` (`status`),
  CONSTRAINT `fk_appointments_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_appointments_patient` FOREIGN KEY (`patient_id`) REFERENCES `patients` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_appointments_hospital` FOREIGN KEY (`hospital_id`) REFERENCES `hospitals` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_appointments_department` FOREIGN KEY (`department_id`) REFERENCES `departments` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_appointments_doctor` FOREIGN KEY (`doctor_id`) REFERENCES `doctors` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_appointments_schedule` FOREIGN KEY (`schedule_id`) REFERENCES `doctor_schedules` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='挂号订单';

-- 支付记录
CREATE TABLE IF NOT EXISTS `payments` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `appointment_id` INT UNSIGNED NOT NULL COMMENT '挂号订单',
  `user_id`        INT UNSIGNED NOT NULL COMMENT '支付账号',
  `amount`         INT NOT NULL COMMENT '金额，单位分',
  `channel`        ENUM('WECHAT','ALIPAY','MOCK') NOT NULL DEFAULT 'MOCK' COMMENT '支付渠道',
  `status`         ENUM('PENDING','SUCCESS','FAILED','REFUNDED') NOT NULL DEFAULT 'PENDING' COMMENT '支付状态',
  `paid_at`        DATETIME(3) NULL COMMENT '支付时间',
  `refunded_at`    DATETIME(3) NULL COMMENT '退款时间',
  `created_at`     DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_payments_appointment_id` (`appointment_id`),
  CONSTRAINT `fk_payments_appointment` FOREIGN KEY (`appointment_id`) REFERENCES `appointments` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='支付记录';

-- 会话
CREATE TABLE IF NOT EXISTS `conversations` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`      INT UNSIGNED NOT NULL COMMENT '所属账号',
  `patient_id`   INT UNSIGNED NULL COMMENT '关联就诊人',
  `scene`        ENUM('TRIAGE','REGISTRATION','GENERAL') NOT NULL DEFAULT 'TRIAGE' COMMENT '业务场景',
  `state`        ENUM('TRIAGING','RECOMMEND_READY','REGISTERING','PAYMENT','ESCALATED','DONE') NOT NULL DEFAULT 'TRIAGING' COMMENT '对话状态',
  `summary`      TEXT NULL COMMENT '会话摘要，压缩产物',
  `triage_draft` JSON NULL COMMENT '问诊草稿，结构化采集状态',
  `final_triage` JSON NULL COMMENT '问诊定稿，预问诊单',
  `created_at`   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_conversations_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='会话';

-- 消息
CREATE TABLE IF NOT EXISTS `messages` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `conversation_id` INT UNSIGNED NOT NULL COMMENT '所属会话',
  `role`            ENUM('USER','ASSISTANT','TOOL') NOT NULL COMMENT '消息角色',
  `content`         TEXT NOT NULL COMMENT '消息内容',
  `tool_calls`      JSON NULL COMMENT '工具调用记录',
  `meta`            JSON NULL COMMENT '附加信息：意图、实体、路由',
  `created_at`      DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_messages_conversation_id` (`conversation_id`),
  CONSTRAINT `fk_messages_conversation` FOREIGN KEY (`conversation_id`) REFERENCES `conversations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='消息';

-- Agent 决策审计
CREATE TABLE IF NOT EXISTS `agent_traces` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `conversation_id` INT UNSIGNED NOT NULL COMMENT '所属会话',
  `message_id`      INT UNSIGNED NULL COMMENT '关联消息',
  `agent_name`      VARCHAR(50) NOT NULL COMMENT 'Agent 名称',
  `intent`          VARCHAR(50) NOT NULL COMMENT '意图',
  `entities`        JSON NULL COMMENT '结构化实体',
  `routing`         JSON NULL COMMENT '路由决策',
  `duration_ms`     INT UNSIGNED NULL COMMENT '耗时毫秒',
  `created_at`      DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_agent_traces_conversation_id` (`conversation_id`),
  CONSTRAINT `fk_agent_traces_conversation` FOREIGN KEY (`conversation_id`) REFERENCES `conversations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Agent 决策审计';
