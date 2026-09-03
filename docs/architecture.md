# 架构设计（v1）

## 1. 三层平面总览

| 平面 | 职责 | 技术 | 是否用 LLM | 运行频率 |
|---|---|---|---|---|
| 数据平面 | 采集指标、扫描日志、检测异常、生成 Incident | shell + jq（后续可换 Prometheus/Alertmanager） | 否 | 每 60s（systemd timer） |
| 分析平面 | 消费 Incident，调用工具取证，产出 AnalysisReport | OpenClaw（Phase 3）；自研 agent（Phase 5） | 是 | **事件驱动**，仅在有新 Incident 时 |
| 存储/UI 平面 | 存 Incident 与 Report、提供 REST、网页展示 | Spring Boot 3 + Postgres + Thymeleaf/React | 否 | 常驻服务 |

三个平面之间**只通过契约 JSON 通信**，互不感知实现细节。这是本项目的核心解耦点。

## 2. 数据流

```
demo-app 写日志 (logback, 追加到 app.log)
   │
   ▼
monitor/run_once.sh (每 60s)
   ├─ collect_metrics.sh ──────────────► state/metrics-latest.json (CPU/内存/负载快照)
   ├─ scan_logs.sh (增量: 只读上次 offset 之后的新增行)
   │     ├─ 命中 ERROR/Exception/OutOfMemoryError
   │     ├─ 组事件(取前 N 行堆栈作为 logExcerpt)
   │     ├─ 签名归一化 + 去抖窗口(同一异常窗口内只发一次)
   │     └─► emit_incident.sh ─────────► incidents/inc-<ts>-<seq>.json  (契约 v1)
   └─ check_resources.sh (可选)
         └─ CPU/内存连续 N 次超阈值 ───► emit_incident.sh (type=cpu|memory)

[Phase 3 起] AI Worker (OpenClaw cron 或消息/Webhook 触发)
   ├─ 扫描 incidents/ 目录中新到的 status=new 的 Incident
   ├─ 用 skills 取证: 查 actuator/prometheus 指标、拉日志上下文、查代码
   ├─ 组装 AnalysisReport (契约 v1, 每条证据可溯源)
   └─► POST http://localhost:9000/api/reports (你的后端)

[Phase 4] 存储/UI 后端 (Spring Boot 3 + Postgres)
   ├─ REST: POST /api/reports / GET /api/reports / GET /api/reports/{id}
   └─ 网页: 报告列表 / 详情(结论/证据链/修复建议/时间线) / 手动重分析
```

## 3. 契约说明

- **Incident（事件）**：监控平面发现的一个值得 AI 分析的问题。字段：`incidentId / app / severity / type / firstSeenAt / count / signature / logExcerpt / metrics / status`。
  定义见 [`contracts/incident.schema.json`](../contracts/incident.schema.json)。
- **AnalysisReport（报告）**：Agent 对某个 Incident 的分析结论。字段：`reportId / incidentId / agent / model / analyzedAt / summary / rootCause / evidence[] / impact / fixSuggestions[] / confidence / status`。
  定义见 [`contracts/report.schema.json`](../contracts/report.schema.json)。
- 变更契约 = 升版本号（v1 → v2），不原地改字段语义。示例见 `contracts/examples/`。

> 为什么契约先行：官方 OpenClaw agent 与自研 agent 都只依赖这两份 JSON。
> 于是你可以 (a) 用同一批历史 Incident 对两个 agent 做离线评测；(b) 逐步把流量从官方切到自研；
> (c) UI 层永远只按 Report Schema 渲染，与"谁写的报告"无关。这就是把 agent 平台化的核心思路。

## 4. 关键设计细节（踩坑预防）

1. **增量扫描**：`scan_logs.sh` 记录上次读到的字节 offset（`state/log_offset`），每次只处理新增部分；
   日志轮转（文件变小）时自动从头开始。避免每次全量扫大日志。
2. **签名去抖**：同一异常在 `AIOPS_DEDUP_WINDOW_SEC`(默认 600s) 内只发一次 Incident，防止日志风暴刷爆 agent。
3. **上下文裁剪**：logExcerpt 默认最多 `AIOPS_MAX_EXCERPT_LINES`(10) 行；Agent 需要更多时用 skill 按需拉取。
4. **资源告警防抖**：连续 `AIOPS_RESOURCE_CONSECUTIVE`(3) 次采样超阈值才发，避免瞬时尖峰误报。
5. **严重度**：含 OutOfMemoryError/FATAL → critical；ERROR/SEVERE → high；其他 → medium。
6. **安全**：喂给 LLM 的内容来自日志，若将来接入真实日志必须先脱敏（密钥/token 替换），本仓库用 demo 数据。

## 5. 演进路线（不过度设计）

- Phase 3 之前：无 LLM、无数据库，Incident 就是"队列"，落盘目录即可。
- Phase 3：OpenClaw cron 轮询 incidents/ 目录。
- Phase 4：后端接管存储与查询，Incident 落库，目录队列可退役。
- Phase 5：自研 agent 作为第二个 Worker 与官方 agent 并存对比。
- 进阶（可选）：把数据平面升级为 node_exporter + Prometheus + Alertmanager，把 Alertmanager Webhook 作为 Incident 来源。
