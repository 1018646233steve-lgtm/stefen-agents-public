# 8 周执行路线（每阶段带验收标准）

> 原则：每阶段都能独立演示；代码全程进 GitHub 私有仓库；
> 每阶段的 commit 即简历素材。括号内为该阶段主要产物/目录。

## Phase 0：基础设施（第 1 周 · 半天，别恋战）

- [ ] 买海外 VPS（2C4G，香港/新加坡等；大陆直连 Anthropic API / GitHub 的需要）
- [ ] Ubuntu 22.04/24.04；SSH 密钥登录（禁用密码）、ufw 仅放行 22/80/443、fail2ban
- [ ] 安装：git、curl、jq、Node 20+、OpenJDK 21、Maven（脚本见 `deploy/bootstrap-server.sh`）
- [x] （已完成）本地脚手架 `aiops-lab`（本仓库）

**验收**：`ssh user@host` 免密登录；`deploy/bootstrap-server.sh` 可一键完成软件安装。

## Phase 1：示例应用上线（第 1 周 · 产物 `demo-app/`）

- [ ] `mvn clean package` 产出 jar
- [ ] 用 `deploy/systemd/aiops-app.service` 部署到服务器，日志落到 `/var/log/aiops/app.log`
- [ ] 验证 `curl localhost:8080/actuator/health` → UP；`/api/boom` 后日志出现异常栈

**验收**：能演示「调用故障接口 → 服务器日志文件出现带时间戳的异常栈」。

## Phase 2：数据平面 + Incident 事件（第 2 周 · 产物 `monitor/`）★成败关键

- [x] 本地跑通：`bash monitor/test/run_local_test.sh`（不依赖 Java；含 R4 回归：同异常跨线程在窗口内只发 1 个 Incident）
- [x] 本地全链路演示：用真实 `demo-app` 产生的日志跑通 monitor（2026-09-03，11 条 ERROR → 2 个 Incident，含跨线程去抖聚合）
- [ ] 服务器安装 `monitor/` + `aiops-monitor.timer`（每 60s 跑 `run_once.sh`）
- [ ] 手动触发 `/api/flaky` → 60s 内 `incidents/` 出现新 Incident JSON
- [ ] 验证去抖：同一异常不重复产生 Incident；验证轮转：清空日志后仍能工作
- [ ] 资源告警（可选）：制造 CPU 尖峰，验证 `type=cpu` 的 Incident

**验收**：能演示「故障 → 10 秒内得到一份契约合法的 Incident JSON，且重复触发不刷屏」。
**本周在学**：事件建模、上下文裁剪、去抖 —— agent 系统的地基。

## Phase 3：OpenClaw 部署 + 官方/社区 skill 组装分析 Agent（第 3–4 周 · 产物 `worker/`）

- [ ] 服务器安装 OpenClaw（Node 20+）；先 CLI/cron 模式验证，再决定是否接 Telegram
- [ ] 写/装 3 个 skill：
  1. `collect_metrics` —— curl actuator/prometheus 拉当前指标
  2. `fetch_logs` —— 按 Incident 时间窗拉日志上下文（限量）
  3. `submit_report` —— 把 AnalysisReport(契约 v1) POST 到后端
- [ ] 配 cron：每 2–5 分钟消费一个新 Incident → 跑一次分析
- [ ] 故意喂不完整日志，观察 agent 是否会编造证据（幻觉第一课）

**验收**：故障发生几分钟后，得到一份契约合法的 AnalysisReport，含结论/证据/根因/修复建议。
> 本阶段开始前建议先完成本地 spike：在本地装 OpenClaw 验证「cron 触发 + 自定义 skill + 结构化输出」可行，
> 避免买完服务器才发现载体不合适（备选路线见 roadmap 末尾）。

## Phase 4：分析存储与 UI（第 4–5 周 · 产物 `backend/`）

- [ ] Spring Boot 3 + Postgres：`incidents` / `reports`(JSONB) 表
- [ ] REST：`POST /api/reports`（Agent 回调）、`GET /api/reports`、`GET /api/reports/{id}`
- [ ] 网页：报告列表页 + 详情页（结论、证据链、修复建议、时间线）
- [ ] 「手动重分析」按钮（把 Incident 重新丢给 agent）
- [ ] Incident 消费状态机：`new → analyzing → analyzed`，Agent 按状态取任务防重复

**验收**：一个网页能浏览 10+ 份历史 Agent 分析报告并按严重度/类型筛选。

## Phase 5：自研同款 Agent（第 5–7 周 · 产物 `self-built-agent/`）★转型核心产出

- [ ] **先读**：读透 OpenClaw 中你用的 skill/agent 源码，画出运行循环
      `系统提示词 → 观察(工具结果) → 决策(调哪个工具) → 执行 → 再观察 → 收敛`
- [ ] **裸写最小版**（TS 或 Python）：直调模型 function calling，实现同样 3 个工具 + 循环 + submit_report
- [ ] **Java 落点（可选）**：用 Spring AI / LangChain4j 移植成 Java agent 服务
- [ ] 与官方 agent 并跑：同一 Incident 队列、两个 worker、同 Schema 报告
- [ ] 评测：取 20 个历史 Incident，记录两方「结论是否正确 / 证据是否真实」，产出对比表

**验收**：官方/自研一键切换；有 20 条样本的评测表；能讲清 agent 循环的每一步。

## Phase 6：打磨与沉淀（第 8 周）

- [ ] 分析结果去重、失败重试、token 用量统计
- [ ] 日志脱敏后再喂 LLM；密钥全部走环境变量/secret
- [ ] 写项目博客/README：架构图 + 契约 + 踩坑记录 + 演示录屏（故障→告警→分析→UI）

**最终交付**：可演示仓库 —— README 含架构图、一次真实故障全链路录屏、自研 agent 源码与评测表。

## 备选路线（如实告知）

如果 Phase 3 spike 发现 OpenClaw 与你的场景拧巴（它以消息渠道为核心），可跳过它直接进入 Phase 5 自研：
n8n / LangGraph(Python) 或 Spring AI / LangChain4j(Java) 写一个 cron 触发的 agent 服务即可，
架构与契约完全不变 —— 前面投入不浪费。两条路最终汇合在 `contracts/` 上。

## 每阶段对应的 AI Agent 知识点（面试时讲得出来）

| 阶段 | 学到的东西 |
|---|---|
| Phase 2 | 给 agent 设计输入/事件流、上下文裁剪 |
| Phase 3 | 工具(skill)定义、工具选择、结构化输出 |
| Phase 4 | AgentOps：结果存储、回放、审计、任务状态机 |
| Phase 5 | agent 循环、function calling、评测与幻觉识别 |
