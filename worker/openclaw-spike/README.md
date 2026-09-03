# OpenClaw 本地 spike(Phase 3 第一步,买服务器前验证载体)

> 目标:在本机把 **OpenClaw(常驻 Gateway)+ 3 个自定义 skill + cron 触发 + 契约 v1 报告产出**
> 这条链路跑通,证明 OpenClaw 适合当「事件驱动的日志/性能监控分析 agent」载体;跑通后再上服务器(roadmap Phase 3 后半段)。
> 配套调研备忘:`/Users/stefenagents/openclaw-spike-notes.md`(键名出处全部在该文件,仓库外)。

## 目录结构

```
worker/openclaw-spike/
├── openclaw.spike.config.json5   # OpenClaw 配置模板(自定义 provider ds + monitor agent + AIOPS 路径)
├── workspace/                     # = monitor agent 的 OpenClaw workspace
│   ├── AGENTS.md                  # agent 职责与铁律(引导注入;分析五步 + 证据可溯源红线)
│   └── skills/
│       ├── collect-metrics/       # 读指标快照 + 探测 demo-app actuator
│       ├── fetch-logs/            # 按 Incident 时间戳拉事件前后真实日志(限量)
│       └── submit-report/         # 契约 v1 报告落盘 + Incident 状态流转(new→analyzing→analyzed)
├── scripts/
│   ├── demo-incidents.sh          # 用 monitor 数据平面生成样例 Incident + 日志 + 指标(不依赖 Java)
│   ├── next-incident.sh           # 取出队列第一个 status==new 的 Incident(领取命令)
│   ├── incident-trigger.mjs       # cron 条件触发器: 有新 Incident 才 fire(不空转烧 token)
│   └── receiver.mjs               # (可选)模拟 Phase 4 后端的报告接收器
└── .data/                         # 运行时数据(gitignored): incidents/ state/ logs/ reports/
```

## 运行步骤(本机)

前置:Node ≥ 24.15;`openclaw` 已装(`npm install -g openclaw@latest --allow-scripts=openclaw`)。

```bash
# 0) 准备数据:生成 3 个样例 Incident(NPE / boom / OOM), 全部 status=new
bash worker/openclaw-spike/scripts/demo-incidents.sh

# 1) 配置:把 openclaw.spike.config.json5 安装为配置文件并填 DEEPSEEK_API_KEY
#    (默认 ~/.openclaw/openclaw.json; 也可用 OPENCLAW_HOME 指向隔离目录, 如 ~/.openclaw-spike)
openclaw config validate          # 校验配置
openclaw models list              # 应能看到 ds/deepseek-v4-flash

# 2) 启动常驻 Gateway(cron 调度器在 Gateway 进程内; 本机前台跑便于看日志)
openclaw gateway start            # 或 openclaw gateway install 装成 launchd 常驻

# 3) 连通性验收(一次性回合, 不依赖 cron)
openclaw agent exec --agent monitor --message "你好, 请确认你能看到 collect-metrics/fetch-logs/submit-report 三个 skill"

# 4) 加 cron:每 2 分钟, 有新 Incident 才触发 monitor agent 分析一轮
openclaw automations add --every 2m --session isolated --agent monitor \
  --trigger-script /Users/stefenagents/stefen-agents/worker/openclaw-spike/scripts/incident-trigger.mjs \
  --message "按 AGENTS.md 工作流处理新 Incident" \
  --name aiops-monitor

# 5) 观察
openclaw automations list; openclaw automations runs --id <job-id>
openclaw logs --tail 100
ls worker/openclaw-spike/.data/reports/          # 契约 v1 报告应逐条出现
```

## 验证点(Pass = spike 成功)

1. [ ] Gateway 起来后 `openclaw models list` 有 `ds/deepseek-v4-flash`,`agent exec` 能正常对话
2. [ ] cron 任务创建成功;触发器在**队列为空**时不 fire(不烧 token)
3. [ ] 丢一个新 Incident → 触发器 fire → agent 走完五步 → `.data/reports/` 出现契约合法的
     `<incidentId>.report.json`,对应 Incident `status` 变为 `analyzed`
4. [ ] 抽查报告:evidence[].content 都能在 `.data/logs/app.log` 中找到原文(无幻觉)
5. [ ] (可选)幻觉第一课:把 logExcerpt 手工截断一半再喂,看 agent 是否如实降 confidence 而非编造

# 验证结果(2026-09-03 本机 spike 实跑)

## ✅ 全部通过

| # | 结果 |
|---|---|
| 1 | 模型链通用:`ds/deepseek-v4-flash` 经 `https://api.deepseek.com/anthropic/v1/messages` 200/数百 ms;模型目录经 GET /models 实测为 `deepseek-v4-flash` / `deepseek-v4-pro`(老 id 已退役) |
| 2 | cron 任务 `aiops-monitor-spike`(every 2m, isolated, --no-deliver, tools=exec,read,write)创建成功;触发器脚本采用沙箱内联 JS 契约(exec/json/trigger 全局) |
| 3 | 3 个真实 Incident(NPE/boom/OOM)全部处理:0001/0002 由手动与首轮调度处理,0003 由**纯定时调度**自动消化 → 3 份契约 v1 报告落盘、队列全部 `analyzed` |
| 4 | 证据可溯源:抽查 3 份报告 evidence,内容均为 app.log 原文 / demo-app 源码原文 / metrics 快照原文,无编造栈 |
| 5 | 幻觉探测:只喂 1 行无堆栈日志 → agent 如实把 confidence 打到 0.7,列出 3 条 openQuestions,并声明"未编造堆栈/行号";0003(OOM)因找不到预期类名,confidence 0.55 偏低(诚实) |

**空队列不空转**:队列清空后 130s 观察,`automations runs` entries 3→3,零新增(触发器 fire:false,不烧 token)。

## 关键发现/坑(记录)

1. **触发器脚本是"沙箱内联 JS"而非 node 文件**:源码契约只用 `exec()`/`json()`/`trigger.state` 三个全局,
   不能有 shebang、require、process(见 docs/automation/cron-jobs.md "Event triggers")。
2. **Gateway 前台进程勿用管道截断**:`openclaw gateway ... | head` 会因 SIGPIPE 把 gateway 杀死(实测中断了
   一次运行)。要用 `> logfile 2>&1` 重定向常驻。
3. **read 工具被沙箱限制在 agent workspace 内**:Incident 队列/应用日志/demo-app 源码都在 workspace 根之外,
   agent 实际靠 exec(shell cat/jq/grep)读取——链路可行,但意味着这些 agent 需要 exec 权限(trusted 模式已默认给)。
4. **崩溃恢复**:运行中 gateway 被杀会留下 `analyzing` 的 Incident;next-incident 领取范围已扩为
   `new`+`analyzing`(analyzed/ignored 跳过),重启后调度器自动续跑,0003 即由此恢复(留有一条 failed run 记录)。
5. **模型是思考型**:DeepSeek Anthropic 端点返回带 `thinking` 块;OpenClaw 原生处理,无需特殊配置。
6. 每轮 agent 分析成本:约 2 万 input token(含 AGENTS.md + skill 描述引导),报告回合数 15-25;可用
   `--light-context` 等瘦身(见 automations add --help)。
7. 背景噪音:`[memory] sync failed ... provider openai` 只是 exec 临时环境的无害告警(未配 openai key)。

## 已知待实测点(调研备忘 §8)

- [x] DeepSeek Anthropic 端点模型 id → 实测 `deepseek-v4-flash`/`deepseek-v4-pro` 均可用
- [x] trigger-script 契约 → 实测为沙箱内联 JS(见上"关键发现 1")
- [x] 配置文件路径/隔离 → 默认 `~/.openclaw/openclaw.json`(JSON5),`config validate` 校验通过
- [ ] 服务器部署后半段(roadmap Phase 3):装 launchd/systemd、接真实 demo-app 日志、接 Telegram 或 webhook 通知
