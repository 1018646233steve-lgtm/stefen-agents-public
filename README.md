# aiops-lab —— 用 AI Agent 监控 Spring Boot 应用（学习型项目）

> 目标：以「**传统监控告警（数据平面）+ 事件驱动的 LLM Agent 分析（分析平面）+ 分析结果展示 UI（存储/UI 平面）**」三层架构，端到端实现：
> 服务器跑一个 Spring Boot 应用 → 异常/资源事件触发 OpenClaw Agent 自动分析定位 → 分析报告存入自己的后端并用网页展示。
> 学习路径：先用官方/社区 Agent 跑通，再按同一契约自研一个可替换的 Agent。
> 作者背景：6 年 Java 开发，转型 AI Agent 开发。本仓库全部代码均为学习产物，欢迎照抄并改进。

---

## 0. 为什么这样设计（三条铁律）

1. **LLM 不做高频监控，只做低频分析。**
   指标采集与异常检测用 shell / node_exporter / Prometheus 完成（免费、确定、毫秒级）；
   LLM Agent 只在「有告警事件」时被唤醒（事件驱动 = agent-on-alert），否则 token 会烧到怀疑人生。
2. **契约先行，实现后置。**
   `contracts/` 里的 Incident（事件）与 AnalysisReport（报告）JSON Schema 是唯一的接口。
   官方 Agent 和你的自研 Agent 都消费 Incident、产出 Report —— 因此可以**逐个替换、A/B 对比、离线评测**。
3. **上下文要裁剪，证据要可溯。**
   每次分析只喂「最近 N 秒日志摘录 + 指标快照」，不喂整个日志；Report 里的每条证据必须指向真实日志/指标。

架构与数据流详见 [docs/architecture.md](docs/architecture.md)；8 周执行路线见 [docs/roadmap.md](docs/roadmap.md)。

```
                    你的云服务器 (2C4G+)
 ┌────────────────────────────────────────────────────────────┐
 │ [数据平面 · 无 LLM]                                          │
 │  demo-app(SpringBoot, actuator, 可注入故障)                  │
 │      │ 日志 /var/log/aiops/app.log                          │
 │  monitor/ (systemd timer 每 60s)                            │
 │      ├─ collect_metrics.sh  → 指标快照(state/metrics)        │
 │      ├─ scan_logs.sh        → 按增量扫描异常并去抖            │
 │      └─ check_resources.sh  → CPU/内存连续超阈值告警          │
 │                     │ 生成                                   │
 │                     ▼                                       │
 │           Incident JSON (契约 v1)                            │
 │             队列目录 /var/lib/aiops/incidents/               │
 │                     ▼ (Phase 3 起)                          │
 │ [分析平面 · LLM · 按需唤醒]                                   │
 │  OpenClaw (cron 消费队列 / Telegram / Webhook)               │
 │   skills: collect_metrics · fetch_logs · submit_report       │
 │                     │ AnalysisReport JSON (契约 v1)          │
 │                     ▼                                       │
 │ [存储 + UI 平面 · 你的 Java 强项]                             │
 │  Spring Boot 3 + Postgres + REST + 网页(报告列表/详情/证据链)  │
 └────────────────────────────────────────────────────────────┘
```

## 1. 仓库结构

```
aiops-lab/
├── README.md                 ← 本文件
├── docs/
│   ├── architecture.md       ← 三层架构、数据流、契约说明
│   └── roadmap.md            ← 8 周路线 + 每阶段验收标准(checklist)
├── contracts/                ← ★ 契约先行（本仓库最有价值的部分）
│   ├── incident.schema.json  ← 事件 v1（监控平面 → 分析平面）
│   ├── report.schema.json    ← 报告 v1（分析平面 → 存储/UI）
│   └── examples/             ← 真实示例（测试与评测用）
├── monitor/                  ← 数据平面（无 LLM，纯 shell + jq）
│   ├── config.env            ← 路径与阈值配置（可用环境变量覆盖）
│   ├── lib/common.sh         ← 日志/目录工具
│   ├── collect_metrics.sh    ← CPU/内存/负载快照 → state/metrics-latest.json
│   ├── scan_logs.sh          ← 增量扫描日志、异常签名聚合、去抖
│   ├── check_resources.sh    ← 资源超阈值(连续 N 次)告警
│   ├── emit_incident.sh      ← 按契约生成 Incident JSON
│   ├── run_once.sh           ← 一键执行一轮监控（timer 每 60s 调用）
│   └── test/                 ← 本地端到端测试 + 样例日志
├── demo-app/                 ← 最小 Spring Boot 3 示例（可注入故障）
└── deploy/                   ← 服务器初始化、systemd 单元、安装说明
```

## 2. 本地快速体验（不需要服务器，5 分钟）

前置：JDK 21+、Maven、`bash`、`jq`。

```bash
# 1) 起示例应用（另开一个终端；日志写到 demo-app/logs/app.log）
cd aiops-lab/demo-app
mvn spring-boot:run

# 2) 制造一次异常（可多打几次）
curl -s http://localhost:8080/api/boom ; echo
curl -s http://localhost:8080/api/flaky ; echo   # 约 40% 概率抛 NPE

# 3) 回到仓库根目录，跑一轮本地监控（路径全部指向本地临时目录）
export AIOPS_STATE_DIR=$(pwd)/.aiops/state \
       AIOPS_INCIDENT_DIR=$(pwd)/.aiops/incidents \
       AIOPS_APP_LOG=$(pwd)/demo-app/logs/app.log \
       AIOPS_WATCH_RESOURCES=false
bash monitor/run_once.sh

# 4) 查看生成的 Incident（契约 v1）
ls -la .aiops/incidents/
jq . .aiops/incidents/inc-*.json | head -80
```

没有 Maven 也想先看效果：直接跑仓库自带的样例日志测试（不依赖 Java）：

```bash
bash monitor/test/run_local_test.sh
```

## 3. 当前进度与下一步

- [x] Phase 0/1/2 脚手架：契约、监控脚本、示例应用、部署骨架（本仓库）
- [x] 本地全链路验证：真实 `demo-app` 日志 → Incident（2026-09-03，11 条 ERROR → 2 个 Incident）
- [ ] 按 [docs/roadmap.md](docs/roadmap.md) 买服务器并执行 deploy/bootstrap-server.sh
- [ ] Phase 3：部署 OpenClaw、写三个 skill、接 Incident 队列
- [ ] Phase 4：自建 Spring Boot 存储/UI 后端
- [ ] Phase 5：按契约自研可替换的 Agent

## 4. 常用决策记录（为什么这么做）

| 决策 | 理由 | 备注 |
|---|---|---|
| 事件驱动而非 LLM 轮询 | 成本低 2–3 个数量级、可靠性高 | agent-on-alert 是业界模式 |
| 契约先行 | 官方/自研 Agent 可替换、可评测 | 见 contracts/README |
| 签名取日志"消息"部分而非整行 | 线程名/PID/时区等噪声都在 header 段，排除后同一异常跨线程才能被去抖（真实 Tomcat 线程池场景，R4 回归测试覆盖） | 见 monitor/scan_logs.sh |
| 服务器买海外 VPS | 大陆直连 Anthropic API / GitHub 不稳 | 香港/新加坡节点 |
| 分析模型分层 | Haiku 级打底，复杂问题升 Sonnet | 省 token |
| 存储/UI 用 Java | 发挥 6 年 Java 经验，聚焦新知识(Agent) | |

> ⚠️ 本仓库不含任何密钥。所有运行参数通过环境变量或 `config.env` 注入。
