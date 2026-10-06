# 医疗健康查询助手 — 后端与 Agent 设计文档

## 一、目标与范围

网页端医疗健康查询助手：用户在聊天界面与问诊 Agent 对话，Agent 采集病情，判定可以挂号后推送医生推荐卡片，用户点击自动挂号按钮由挂号 Agent 下单，用户自行支付；另有独立的手动挂号接口。默认单医院。

本文档只描述后端与 Agent。前端是独立项目，前后端各自定义自己的数据类型，前端类型以本文档的接口与 SSE 事件契约为准。

## 二、技术选型与工程边界

- 后端：NestJS + TypeScript，`@Sse()` 流式输出，`@nestjs/schedule` 定时任务，`@nestjs/jwt` 认证，class-validator 参数校验
- 数据库：MySQL 8（业务数据）+ ChromaDB（RAG 知识库与跨会话记忆）
- 数据访问：mysql2 驱动，modules 各模块的 repository 层执行参数化 SQL，挂号下单与号源占号用连接事务；表结构以 `server/sql/schema.sql` 为唯一来源
- AI：`openai` npm SDK（对话与结构化输出，端点与模型可配）；embedding 使用 OpenAI 兼容接口（中文向量模型如 bge-m3），由后端计算向量后写入 Chroma；Chroma 客户端使用 `chromadb` npm 包
- 结构化输出：zod 定义 schema，LLM 输出经 zod 解析校验

工程边界：`medical-assistant/` 根目录只有 `server/` 与 `frontend/` 两个子目录和 README。server 与 frontend 是两个独立项目，各自拥有 package.json、tsconfig、.env、依赖安装，没有根 pnpm workspace，没有共享类型包。`docker-compose.yml`（MySQL 8 + ChromaDB）放在 server/ 内，属于后端基础设施。

## 三、server 目录结构

```text
server/
  docker-compose.yml      # MySQL 8 + ChromaDB
  sql/
    schema.sql            # 建库建表 DDL，表结构唯一来源
    seed.sql              # 种子数据（实现阶段创建）
  scripts/
    eval.ts               # 评测运行入口
  src/
    main.ts
    app.module.ts
    modules/
      auth/               # AuthModule：注册、登录、JWT
      chat/               # ChatModule：SSE 对话入口、会话管理、档案与历史问诊、skills 重载
      registration/       # RegistrationModule：科室/医生/排班/评价、就诊人、手动挂号、支付、取消、退款、超时取消任务
      database/          # DatabaseModule：mysql2 连接池
    agent-core/
      runtime/            # agent runtime：orchestrator、state-machine、runner
      agents/             # base.agent.ts + triage / registration / general / escalation
      intent/             # 意图识别：LLM 结构化输出 + 规则兜底
      red-flags/          # 红旗症状规则引擎
      skills/             # SKILL.md 医疗规范 + skill-manager
      rag/                # 查询改写、并行召回、LLM 重排
      memory/             # session-memory、semantic-memory、episodic-memory
      tools/              # 五个工具 + 工具注册表
      eval/               # 高危用例集 baseline.json + LLM-as-Judge
      prompts/            # 各 Agent 的 system prompt 与模板
      schemas/            # zod 结构化输出定义
      trace.ts            # agent_traces 审计写入
```

## 四、模块划分

- `AuthModule`：注册、登录、签发与校验 JWT
- `ChatModule`：SSE 对话入口、会话列表与消息查询、健康档案接口（读写 user_profile）、历史问诊接口（读 episodic）、skills 查看与重载；对话请求转交 agent-core 处理
- `RegistrationModule`：医院/科室/医生/排班/评价查询、就诊人管理、手动挂号下单、支付、取消、退款、超时取消定时任务、号源并发控制；业务 service 供 agent-core 的工具调用
- `DatabaseModule`：mysql2 连接池的创建与注入

各模块内部按 service + repository 分层：repository 负责全部 SQL（参数化查询、连接事务），service 负责业务规则与事务边界。

## 五、Agent 设计

### 5.1 Agent 清单与意图路由

四个 Agent：

- `TriageAgent`（问诊 Agent）：主导对话，结构化采集病情，判定采集完成
- `RegistrationAgent`（挂号 Agent）：推荐医生、查号源、下单、支付、取消
- `GeneralAgent`（通用 Agent）：医院信息、流程咨询、问候
- `EscalationAgent`（升级 Agent）：红旗急诊指引、转人工

每轮用户消息先做意图识别，输出 intent + 结构化实体 + 紧急度，按意图路由：

- `symptom_report` / `symptom_followup` → TriageAgent：实体回填问诊草稿，继续追问或判定完成
- `registration_request`（明确要求挂号）→ 草稿不足时 TriageAgent 补一轮，齐备后定稿，交 RegistrationAgent 生成推荐
- `recommendation_accept`（点击自动挂号按钮）→ RegistrationAgent 下单
- `payment_request` / `cancel_request` → RegistrationAgent 支付、取消工具
- `general_question` → GeneralAgent：先走 RAG 检索再回答，不改草稿与状态
- `emergency`（红旗症状）→ EscalationAgent：急诊指引，状态置 `escalated`
- `human_handoff`（转人工、投诉）→ EscalationAgent

判定顺序：红旗规则引擎先跑，硬规则优先于模型判断；未命中红旗由 LLM 输出意图；一条消息携带多种诉求时先回填实体，再按优先级路由：emergency > human_handoff > registration 类 > symptom 类 > general。

前端点击自动挂号按钮等价于发送 `action=recommendation_accept` 的消息；点击支付直接调用 REST 支付接口，不经 Agent。

### 5.2 状态机

- `triaging`：采集病情中，symptom_report / symptom_followup 维持于此状态
- `recommend_ready`：triage_complete 或 registration_request 触发，进入推荐
- `registering`：recommendation_accept 触发，挂号中
- `payment`：订单创建后进入，支付完成后转 `done`
- `escalated`：emergency / human_handoff 进入，终态分支，阻断推荐与挂号

状态存 `conversations.state`，每次转移写 `agent_traces`（intent、实体、路由、耗时）。

### 5.3 agent runtime

- `orchestrator`：接收消息 → 意图识别 → 路由 Agent → 状态机转移 → 写 trace → 组装 SSE 事件返回
- `runner`：单次 Agent 执行器，组装上下文 → 调用 LLM → zod 解析结构化输出 → 必要时执行工具循环（工具调用 → 结果回填 → 再次生成）
- `state-machine`：状态定义与转移合法性校验

不做路由降权机制（每个 Agent 单实例，降权没有意义），只统计耗时与成功率写入 agent_traces。

### 5.4 skills

每个 Agent 对应一份医疗规范，文件形式为 SKILL.md，front matter 声明适用 Agent、触发关键词、是否启用：

- `triage/SKILL.md`：问诊规范（只追问缺失字段、轮次上限 5、红旗处置、不下诊断）
- `registration/SKILL.md`：挂号规范（下单前确认、号源重新校验、不承诺指定医生）
- `escalation/SKILL.md`：急诊与转人工规范（急诊指引话术、立即就医措辞、人工渠道）
- `general/SKILL.md`：通用接待规范（医院信息回答、禁止索取敏感信息）

`skill-manager` 启动时加载 skills 目录；base.agent 组装 system prompt 时按 Agent 类型与用户消息关键词匹配注入；`POST /api/skills/reload` 热加载，`GET /api/skills` 查看加载状态。

### 5.5 RAG

- collection `knowledge_base` 存医院文档：医院简介、科室介绍、就诊流程、挂号须知、常见问题，seed 时写入
- 意图为 `general_question` 时触发检索：LLM 查询改写生成 1-3 个子查询 → 并行召回 Top-K → LLM 重排 → 结果拼入 GeneralAgent 上下文
- 症状描述与挂号动作类意图不触发检索

### 5.6 各 Agent 内部逻辑

**TriageAgent**

- 输入：用户消息、问诊草稿、健康档案（语义事实）、会话摘要、最近 20 条消息
- 输出：回复文本 + 草稿更新 JSON + 动作（continue_followup / triage_complete / handover_emergency）
- 追问规则：只问草稿缺失字段，每轮最多 1-2 个，总轮次上限 5；已采集字段不重复问
- 完成条件：主诉、持续时长、关键伴随症状齐备，或达到轮次上限，或用户明确要求挂号
- 完成后：定稿 `conversations.final_triage`，触发语义事实提取与 episodic 写入，交给 RegistrationAgent 生成推荐

**RegistrationAgent**

- 工具链：search_doctors → get_schedules → book_appointment → pay_appointment → cancel_appointment
- 推荐排序：症状映射到科室 → 科室下医生按职称权重、评价均分、当日可用号源排序
- 自动挂号：推荐顺序第一个有可用号源的医生与时段下单，事务内原子占号，生成待支付订单；账号下多个就诊人时先在对话中确认给谁挂号
- 支付：用户点击支付 → mock 支付成功 → 订单 confirmed，返回挂号单号、就诊时间、就诊序号
- 手动挂号：前端表单直接调 RegistrationModule 的 REST 接口，与自动挂号共用同一 service 层

**GeneralAgent**：先按意图触发 RAG 检索，再基于检索结果回答，不修改草稿与状态。

**EscalationAgent**：红旗命中回复急诊指引模板并置 `escalated`；转人工回复人工渠道；两种情况都写 agent_traces。

### 5.7 工具定义

- `search_doctors`：入参（department_id、symptom 关键词、date），出参医生列表（职称、擅长、评价均分、当日可用号源）
- `get_schedules`：入参（doctor_id、date），出参时段列表（period、时间、剩余号源、挂号费）
- `book_appointment`：入参（patient_id、doctor_id、schedule_id），事务内原子占号，出参待支付订单
- `pay_appointment`：入参（appointment_id），mock 支付，出参支付结果与订单状态
- `cancel_appointment`：入参（appointment_id），取消与退款，出参取消结果

### 5.8 问诊草稿

问诊草稿是问诊 Agent 在对话过程中维护的结构化采集状态，存 MySQL 的 `conversations.triage_draft`（JSON 列），记录已采集字段、内容、缺失字段清单与红旗标记。示例：

```json
{
  "chief_complaint": "咳嗽三天，夜间加重",
  "duration": "3天",
  "symptoms": ["咳嗽", "咽痛"],
  "allergies": null,
  "medical_history": null,
  "medications": null,
  "patient_id": null,
  "collected_fields": ["chief_complaint", "duration", "symptoms"],
  "missing_fields": ["伴随症状细节", "过敏史", "既往史", "用药史", "就诊人"],
  "red_flag_hit": false
}
```

三个作用：

1. 决定下一轮追问：每轮把草稿注入 prompt，Agent 只追问缺失字段，不重复询问
2. 抵抗压缩损失：长对话压缩原始消息时，草稿的结构化字段保留完整关键信息，摘要与草稿互补
3. 供下游消费：定稿后成为 `conversations.final_triage`，挂号 Agent 推荐、语义事实提取、情景记录写入都消费这份结构化数据，不读原始对话全文

## 六、记忆设计（三层）

### 6.1 第一层：会话记忆（MySQL）

三部分全部存 MySQL：

- 工作记忆：`messages` 表中最近 20 条消息
- 会话摘要：压缩产物，存 `conversations.summary`
- 问诊草稿：结构化采集状态，存 `conversations.triage_draft`

每轮组装上下文：会话摘要 + 最近 20 条消息 + 问诊草稿 + 语义事实 + 相关情景 + RAG 检索结果（按意图可选）。

压缩机制：会话消息数超过 20 条时，超出窗口的最早消息交给 LLM 压缩为摘要，与已有 summary 合并后存回；后续再超阈值时增量压缩新溢出的消息。原始消息全量保留，MySQL 不删除任何消息，压缩只缩小每轮 prompt 范围。

### 6.2 第二层：语义事实记忆（Chroma `user_profile`）

文档为事实条目（"青霉素过敏""高血压病史""长期服用氨氯地平"），metadata 携带 patient_id、category、content_hash、updated_at。

提取方式：问诊定稿后 LLM 从 final_triage 同步提取事实，按 content_hash 增量合并去重，内容变化时更新；失败记录 agent_traces，不影响已定稿的问诊单。

注入方式：新会话开始时按 patient_id 取全部事实注入 prompt，已采集过的信息不重复询问；问诊过程中也可按当前主诉做语义检索取相关事实。

### 6.3 第三层：情景经历记忆（Chroma `episodic`）

文档为结构化问诊单文本（主诉、症状、建议科室、风险等级、结论摘要），metadata 携带 patient_id、conversation_id、date、department_id、doctor_id、risk_level。

写入时机：问诊定稿写一条；挂号确认后再写一条挂号事件（含医生与时段）。

检索方式：按 patient_id 过滤 + 语义相似度取 Top-K。

用途：复诊时参考上次就诊的科室、医生与结论摘要，推荐同一医生。

## 七、数据库表与 Chroma 集合

MySQL 表（DDL 见 `server/sql/schema.sql`）：

- `users`：id、phone、password_hash、real_name、id_card_no（加密存储）、created_at、updated_at
- `patients`：id、user_id、name、gender、birth_date、id_card_no、phone、relationship、is_default
- `hospitals`：id、name、level、address、phone、intro、is_active（种子仅一条默认医院）
- `departments`：id、hospital_id、name、intro、is_active
- `department_symptom_mappings`：id、department_id、symptom_keyword、weight
- `doctors`：id、hospital_id、department_id、name、gender、title、specialty、intro、avatar_url、is_active
- `doctor_reviews`：id、doctor_id、user_id、appointment_id、rating、content、created_at
- `doctor_schedules`：id、doctor_id、department_id、schedule_date、period、start_time、end_time、total_slots、booked_slots、fee、status
- `appointments`：id、appointment_no、user_id、patient_id、hospital_id、department_id、doctor_id、schedule_id、fee、queue_no、status（pending/paid/confirmed/cancelled/visited）、auto_registered、expire_at、cancelled_at、cancel_reason
- `payments`：id、appointment_id、user_id、amount、channel（mock）、status（pending/success/failed/refunded）、paid_at、refunded_at
- `conversations`：id、user_id、patient_id、scene、state、summary、triage_draft（JSON）、final_triage（JSON）、created_at、updated_at
- `messages`：id、conversation_id、role、content、tool_calls（JSON）、meta（JSON）、created_at
- `agent_traces`：id、conversation_id、message_id、agent_name、intent、entities（JSON）、routing（JSON）、duration_ms、created_at

Chroma 集合：`knowledge_base`（医院文档）、`user_profile`（语义事实）、`episodic`（情景经历）。

## 八、后端接口

AuthModule：

- `POST /api/auth/register`
- `POST /api/auth/login`

ChatModule：

- `POST /api/chat`（SSE 流式，Agent 入口）
- `GET /api/conversations`
- `GET /api/conversations/:id/messages`
- `GET /api/health-records`、`POST /api/health-records`、`DELETE /api/health-records/:id`（读写 user_profile）
- `GET /api/episodes`（历史问诊，读 episodic）
- `GET /api/skills`、`POST /api/skills/reload`

RegistrationModule：

- `GET /api/departments`
- `GET /api/doctors`（支持 symptom、departmentId 参数）
- `GET /api/schedules?doctorId=&date=`
- `GET /api/patients`、`POST /api/patients`
- `POST /api/appointments`（手动挂号）
- `GET /api/appointments`
- `POST /api/appointments/:id/pay`（模拟支付）
- `POST /api/appointments/:id/cancel`

SSE 事件：

- `message_delta`：回复文本增量
- `recommendation`：推荐卡片数据（科室、医生列表、可用号源）
- `order_created`：待支付订单（订单号、费用、支付入口）
- `escalation`：急诊或转人工引导
- `error`：错误信息

## 九、关键业务规则

- 号源并发：挂号在事务内原子占号（条件 UPDATE：booked_slots 小于 total_slots 且 status 为 open 时递增），占号失败返回号源已满
- 订单状态机：pending → paid → confirmed → visited；取消 → cancelled；已支付取消触发 mock 退款 → refunded
- 超时释放：待支付订单超过 15 分钟由定时任务取消并释放号源
- 实名与权限：挂号必须选择已实名就诊人，接口校验就诊人归属当前账号
- 数据安全：密码 bcrypt；身份证号加密存储、展示脱敏
- 支付：mock 渠道，状态流转完整，不接真实支付
- 红旗症状：命中立即 `escalated`，阻断推荐与挂号

## 十、配置项（server/.env）

- `LLM_BASE_URL`、`LLM_API_KEY`、`LLM_MODEL`：对话与结构化输出端点
- `EMBEDDING_BASE_URL`、`EMBEDDING_API_KEY`、`EMBEDDING_MODEL`：向量计算端点（默认 bge-m3 类中文模型）
- `DATABASE_URL`：MySQL 连接串
- `CHROMA_URL`：Chroma 服务地址
- `JWT_SECRET`：令牌密钥
- `DEFAULT_HOSPITAL_ID`：默认医院
- `APPOINTMENT_EXPIRE_MINUTES`：待支付订单超时分钟数（默认 15）

## 十一、实现顺序与验收

1. Docker Compose（MySQL 8 + ChromaDB）、执行 `sql/schema.sql` 建表、`sql/seed.sql` 种子数据（默认医院、科室、症状映射、医生、两周排班、测试账号与就诊人）、医院文档写入 knowledge_base
2. AuthModule 与 RegistrationModule 业务接口（手动挂号、支付、取消、超时任务）
3. agent-core：意图识别、红旗规则引擎、四个 Agent、runtime、skills、RAG、三层记忆、工具
4. ChatModule SSE 对接 agent-core
5. 测试：单元测试（红旗规则引擎、状态机、意图解析、事实合并去重、摘要压缩、skills 匹配注入）+ e2e 全链路（问诊 → 推荐 → 自动挂号 → 支付 → 确认；手动挂号；红旗急诊；并发占号；取消退款；超时释放；跨会话记忆注入与情景检索；RAG 检索回答）+ eval 高危用例集回归

## 十二、待确认的假设

- 自动挂号默认选择推荐顺序第一个有可用号源的医生与时段，指定医生走手动挂号或在对话中说明
- 账号下多个就诊人时，自动挂号前由 Agent 在对话中确认
- 待支付订单超时 15 分钟自动取消并释放号源
- 支付使用 mock 渠道，不接真实支付
- embedding 使用 OpenAI 兼容端点，模型通过环境变量配置
