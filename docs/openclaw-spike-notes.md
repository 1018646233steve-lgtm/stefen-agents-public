# OpenClaw(macOS 本机 / cron 监控 spike)调研备忘

> 调研对象:github.com/openclaw/openclaw,默认分支 `main`。
> 本次核对的提交:`3a5fc8f663d22c02362afc8ba454c5a06625ef72`("fix(telegram): ...")。
> 方法:仓库已浅克隆到本机 `/tmp/openclaw-repo`(整树可本地检索);下方所有出处均为该提交下的仓库内文件路径。凡未在仓库/文档中直接证实的内容一律标注 **未确认**,不臆造键名。
> 结论速览:OpenClaw 是 Node/TS 的个人 AI 网关。cron 能力由内置调度器 `openclaw automations`(别名 `openclaw cron`)提供,任务跑在 Gateway 进程内;支持**完全不接任何聊天渠道**的纯后台模式(`--no-deliver` 内部输出 / `--webhook` HTTP 推送 / `--command` 纯脚本)。"任意 Anthropic 兼容端点"用配置键 `models.providers.<id>.api: "anthropic-messages"` + `models.providers.<id>.baseUrl` + `models.providers.<id>.apiKey` 表达(源码级证实 URL 拼接为 `<baseUrl>/v1/messages`)。

---

## 1. 安装

出处:`docs/start/getting-started.md`、`docs/install/index.md`、`docs/providers/deepseek.md`。

- **形态**:CLI(`openclaw`)+ 常驻 Gateway(本地 HTTP/WS,默认端口 `18789`)+ 可选 Control UI(dashboard)。npm 包名 **`openclaw`**。
- **Node 版本要求**:Node `22.22.3+`、`24.15+` 或 `25.9+`(Node 26 为推荐运行时);`pnpm` 仅在从源码构建时需要。
- **推荐安装命令(macOS)**:
  ```bash
  curl -fsSL https://openclaw.ai/install.sh | bash          # 安装 + 引导
  curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard   # 只装不引导
  ```
- **若已自管 Node(等价命令)**:
  ```bash
  npm install -g openclaw@latest --allow-scripts=openclaw
  # npm 12 默认拦包生命周期脚本,须带 --allow-scripts=openclaw(npm 11.15 及更早则去掉该旗标)
  ```
- **快速体验**:`npx openclaw@latest`。
- **首次初始化**:
  - 交互式:`openclaw onboard`(向导)或 `openclaw setup --baseline`(只建 baseline 配置/workspace,不进向导,适合脚本)。
  - 纯脚本化引导示例(DeepSeek 官方渠道,见 §4.2):`openclaw onboard --non-interactive --mode local --auth-choice deepseek-api-key --deepseek-api-key "$DEEPSEEK_API_KEY" --skip-health --accept-risk`。
- **后台常驻(必需,cron 依赖 Gateway 进程)**:`openclaw gateway install`(macOS 走 launchd;Linux systemd)。状态:`openclaw gateway status`。
- 网络/路径相关环境变量:`OPENCLAW_HOME`、`OPENCLAW_STATE_DIR`(默认 `~/.openclaw`)、`OPENCLAW_CONFIG_PATH`、`OPENCLAW_WORKSPACE_DIR`(出处:`docs/help/environment.md`)。`--dev`/`--profile <name>` 会把状态隔离到 `~/.openclaw-dev` / `~/.openclaw-<name>`。

## 2. 配置

出处:`docs/gateway/configuration.md`、`docs/gateway/config-tools.md`、`docs/gateway/configuration-reference.md`、`docs/gateway/configuration-examples.md`、`docs/cli/config.md`、`docs/cli/configure.md`。

- **配置文件位置与格式**:`~/.openclaw/openclaw.json`,格式 **JSON5**(允许注释与尾逗号)。文件不存在则用安全默认值;缺失即拒绝启动的“严格校验”:未知键/类型错 → Gateway 拒绝启动(可用 `openclaw doctor --fix` 修复)。
- 直接改文件会被热重载(Gateway 监听该文件;`gateway.reload.mode` 默认 `hybrid`:安全改动即时生效、关键改动自动重启)。
- 非交互 CLI 读写:`openclaw config get|set|patch|unset <点路径>`,`openclaw config file`(打印实际路径)、`openclaw config schema`(权威 JSON Schema)、`openclaw config validate`。多文件拆分可用顶层 `$include`。
- **密钥注入方式**(三选一):
  1. `~/.openclaw/.env`(全局 dotenv;推荐放 provider key;工作区 `.env` 被安全策略拒绝存放 provider 密钥);
  2. 配置内 `env: { vars: { DEEPSEEK_API_KEY: "sk-..." } }`(仅当环境缺失时生效);
  3. 配置字符串内 `${VAR}` 替换(如 `apiKey: "${DEEPSEEK_API_KEY}"`)。
- **模型选择键**(出处:`docs/gateway/configuration.md` "Choose and configure models"、`docs/gateway/config-agents.md#agents.defaults.model`):
  - 主模型:`agents.defaults.model.primary` = `"provider/model"`;可配 `fallbacks: [...]`、`utilityModel` 等。
  - 别名/每模型参数:`agents.defaults.models["provider/model"] = { alias, params }`。
  - 覆盖白名单:`agents.defaults.modelPolicy.allow`(可 `provider/*` 通配)。
  - CLI:`openclaw models list`、`openclaw models set <provider/model>`、`openclaw configure --section model`。

### 2.1 自定义 provider(Anthropic 兼容端点)的键结构

出处:`docs/gateway/config-tools.md` "Custom providers and base URLs" + "Provider field details";`docs/gateway/configuration-examples.md` "Anthropic API key + MiniMax fallback"(Minimax 的 Anthropic 兼容端点样例,键与 DeepSeek 场景完全同构);源码 `packages/ai/src/transports/anthropic-transport-stream.ts` `resolveAnthropicMessagesUrl()`。

```json5
// ~/.openclaw/openclaw.json
{
  env: { vars: { DEEPSEEK_API_KEY: "sk-..." } },

  models: {
    mode: "merge", // merge | replace
    providers: {
      "ds-anthropic": {
        // api: 请求适配器。Anthropic 兼容端点用 "anthropic-messages"
        // (其他取值: openai-completions / openai-responses / google-generative-ai ...)
        api: "anthropic-messages",
        // baseUrl 不带 /v1: 源码证实适配器最终请求 <baseUrl>/v1/messages
        // (若 baseUrl 以 /v1 结尾则拼 /v1/messages 时不重复; 自定 baseUrl 无 api 时默认 openai-completions)
        baseUrl: "https://api.deepseek.com/anthropic",
        apiKey: "${DEEPSEEK_API_KEY}",
        models: [
          {
            // id = 实际发往端点的模型名; DeepSeek Anthropic 端点此刻接受哪些 id → 未确认,
            // 需以 DeepSeek 现行文档/实测为准(仓库 docs/providers/deepseek.md 仅覆盖其官方
            // OpenAI 兼容目录: deepseek/deepseek-v4-flash、deepseek/deepseek-v4-pro)
            id: "deepseek-chat",
            name: "DeepSeek via Anthropic endpoint",
            input: ["text"],
            contextWindow: 128000,
            maxTokens: 8192,
          },
        ],
      },
    },
  },

  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      model: { primary: "ds-anthropic/deepseek-chat" },
    },
    entries: {
      monitor: {
        name: "monitor",
        workspace: "~/.openclaw/workspaces/monitor",
        agentDir: "~/.openclaw/agents/monitor/agent",
        model: "ds-anthropic/deepseek-chat",
      },
    },
  },
}
```

要点(均出自上述文档):
- 自定义 provider 的模型引用即 `models.providers.<id>.models[]` 里 `id` 与 provider 前缀拼成的 `"<id>/<model>"`,所以上面的主模型是 `ds-anthropic/deepseek-chat`。
- 不用显式 `apiKey` 时可用 `authHeader` + `headers`,或 `request.auth`(`authorization-bearer` / `header`),`request.headers`/`request.tls`/`request.proxy` 可选。
- 官方插件已覆盖的 provider(如 `deepseek`、`moonshot`、`minimax`)通常**不必**写 `models.providers` 条目;只有要“改 baseUrl/header/模型表”或加纯自定义 provider 时才写。若改写某官方 provider 的 baseUrl 到非官方主机,OpenClaw 会把它当自定义路由处理:非直连 Anthropic 端点会自动抑制隐式 beta 头(`claude-code-20250219` 等),需要时用 `models.providers.<id>.headers["anthropic-beta"]` 显式补(出处:`docs/concepts/model-providers.md` 末尾自定义段)。另一种等价写法是 `models.providers.anthropic.baseUrl` 覆盖默认 anthropic 渠道。
- `models.providers.*.models[]` 里 `input` 写 `["text"]`/`["text","image"]`、`contextWindow`/`contextTokens`/`maxTokens`/`cost` 为可选元数据(带图片能力才走原生图传)。
- 出处提供的同构官方样例(可直接抄改):MiniMax `baseUrl: "https://api.minimax.io/anthropic", api: "anthropic-messages", apiKey: "${MINIMAX_API_KEY}"`,模型引用 `minimax/MiniMax-M2.7`,见 `docs/gateway/configuration-examples.md`。

### 2.2 “系统提示 / agent”怎么给

出处:`docs/concepts/system-prompt.md`、`docs/gateway/config-agents.md`、`docs/cli/agents.md`。

- OpenClaw 自己拼系统提示(无“运行时默认 prompt”文件),**不要**试图用某个配置键整体替换系统提示。个性/身份/长期指令走 **workspace 引导文件**(按注入顺序):`AGENTS.md`、`SOUL.md`、`IDENTITY.md`、`USER.md`、`MEMORY.md`(仅新工作区有 `BOOTSTRAP.md`),位于 `agents.defaults.workspace`(默认 `~/.openclaw/workspace`)根目录;总注入上限 `agents.defaults.bootstrapTotalMaxChars`(默认 60000),单文件 `bootstrapMaxChars`(20000)。
- 每个 agent 是独立 workspace + 会话 + 模型;定义落在 `agents.entries.<id>`(config)或 CLI `openclaw agents add <name> --workspace <dir> [--model <ref>] [--agent-dir <dir>] [--bind channel:*] --non-interactive`。
- `agents.entries.*` 支持:`name`、`workspace`、`agentDir`(如 `~/.openclaw/agents/main/agent`)、`model`(字符串或 `{primary, fallbacks}`)、`skills`(per-agent 白名单,`[]`=无)、`identity`、`thinkingDefault`、`sandbox`、`tools` 等。多 agent 时引用目标用 `--agent <id>`/`agentId`;单 agent 时隐式为默认(旧 `default: true` 字段已废弃,见 config-agents.md)。
- 因此最小“系统提示/agent”做法:给该 agent 的 workspace 放一个 `SOUL.md`/`AGENTS.md`,并在 cron 任务的 prompt 里写清职责(见 §3.2 示例)。

## 3. cron 用法

出处:`docs/cli/cron.md`、`docs/automation/cron-jobs.md`、`docs/gateway/configuration.md`(cron 小节)。

- 命令:主命令 **`openclaw automations`**,`openclaw cron` 仍是别名(子命令同构)。管理类操作(`add/edit/rm/run`)要求 `operator.admin`。
- 触发的是**任务**(job)而非对话:agent-turn 任务在 Gateway 进程内起一个“受调度的 agent 回合”(有模型调用、可用工具);纯 `command`/`script` payload 甚至完全不调模型。结果默认可投递到聊天渠道,也可只写内部或 POST 到 webhook。
- 增删查改:
  ```bash
  openclaw automations add --cron "*/10 * * * *" --message "做 X" --name "job-name" [--agent monitor] [--session isolated]
  openclaw automations create "*/10 * * * *" "做 X" --name "job-name"        # create=add 别名;调度在前,prompt 在后(位置参数)
  openclaw automations list | openclaw automations list --all
  openclaw automations show <job-id>        # 含解析出的投递路由
  openclaw automations edit <job-id> --cron "0 7 * * *"
  openclaw automations rm <job-id>          # enable/disable 亦可
  openclaw automations run <job-id> --wait --wait-timeout 10m   # 手动触发并等终态(exit 0 仅当 succeeded)
  openclaw automations runs --id <job-id>
  ```
- **调度类型**:`--at <ISO|相对如 20m>`(一次性)、`--every <10m|1h|1d>`(固定间隔)、`--cron <5/6段表达式> [--tz <IANA>]`、`--on-exit`、`--stream-command`。cron 表达式解析用 [croner](https://github.com/Hexagon/croner);日+星期同非通配时是 OR 语义(标准 vixie)。
- **会话**:`--session main|isolated|current|session:<id>`。`isolated` = 每次新转录新会话(监控类任务推荐,避免上下文串味);agent-turn 任务默认落到创建时的会话,否则 `isolated`。
- **payload 种类**(每个 job 恰好一种):`--message <text>`(agent 回合)、`--system-event <text>`(只入 main 会话队列、不调模型)、`--command <shell>` / `--command-argv '<json>'`(宿主机进程、不调模型;带 `--command-cwd/--command-env/--command-input/--timeout-seconds/--output-max-bytes`)、`--script <file|->`(headless JS,用所属 agent 的工具,超时默认 300s 上限 900s)。
- 可选项:`--model <ref>`(per-job 主模型,解析失败则显式报错不回退)、`--fallbacks`、`--thinking`、`--tools exec,read,write`(存显式工具策略)。
- **“每 N 分钟处理某目录新文件”的三个做法**(文档均有对应机制):
  1. **纯脚本(command/script payload,不烧 token)**:`--every 5m --command-argv '["node","scripts/scan-dir.mjs"]' --command-cwd /path/to/out` —— 自己写 JS 扫目录/去重/生成报告文件;脚本输出即投递内容(仅 `NO_REPLY` 会静默)。
  2. **agent 回合 + 目录任务**:`--every 5m --session isolated --agent monitor --tools exec,read,write,edit --message "扫描 <dir> 下自上次运行以来的新文件并分析,结论写到 <out>/report-$(date...).md" --no-deliver`(输出内部;或 `--webhook http://127.0.0.1:PORT/cb` POST 结果)。
  3. **条件触发器(状态去重)**:`--every 30s --trigger-script ./watch-new-files.js --message "有新文件,处理" --session isolated` —— 脚本必须返回 `{ fire, message?, state? }`;`trigger.state` 保存上次状态(上限 16KB),`fire:true` 才真正跑 agent 回合(示例见 cron-jobs.md "Event triggers")。**注意**:触发器脚本/script payload 默认以所属 agent 的完整工具策略无人值守运行(含 exec),安全上按“无人值守代码执行”对待;可用 `cron.triggers.enabled: false` 整体关闭。
- **投递/headless 语义**:isolated 任务默认 `--announce`(有聊天路由才发);`--no-deliver` 关闭 fallback 投递但 agent 仍可自己用 message 工具;`--webhook <url>` 改为把“完成的 payload”POST 出去(webhookToken 以 `Authorization: Bearer` 带出,配置在 `cron.webhookToken`);`none` 模式关闭 runner 投递。失败通知、重试退避(30s→1h)、`--at` 一次性任务成功后自删、`cron.sessionRetention` 等详见文档。**不用配置任何聊天渠道也能跑**(webhook/command/script/no-deliver 均不依赖渠道)。
- 网关离线时错过的周期默认会补跑(`cron.skipMissedJobs: true` 改为跳过)。整体开关:`cron.enabled: false` 或 `OPENCLAW_SKIP_CRON=1`。
- jobs/运行历史持久化在共享 SQLite;旧 `~/.openclaw/cron/jobs.json` 由 `openclaw doctor --fix` 迁移一次。

## 4. 模型 provider 现状(DeepSeek 场景)

出处:`docs/providers/deepseek.md`、`docs/concepts/model-providers.md`、`docs/plugins/reference/deepseek.md`(如安装插件)。

- **官方 DeepSeek provider 插件(OpenAI 兼容,非 Anthropic 端点)**:provider id `deepseek`,认证 env `DEEPSEEK_API_KEY`,CLI `openclaw onboard --auth-choice deepseek-api-key`。目录模型引用(仓库文档当下值):`deepseek/deepseek-v4-flash`、`deepseek/deepseek-v4-pro`(仓库文档称 deepseek-chat/reasoner 已于 2026-07-24 退役——若与你实际拿到的 DeepSeek 文档不符,以 DeepSeek 官方为准,**未确认**)。安装插件:`openclaw plugins install @openclaw/deepseek-provider && openclaw gateway restart`。
- **指向“任意 Anthropic 兼容端点”(本 spike 目标)**:不依赖 DeepSeek 官方插件,用 §2.1 的自定义 provider 即可(`api: "anthropic-messages"` + `baseUrl: "https://api.deepseek.com/anthropic"`)。这是文档中为“Anthropic 兼容代理/自定义端点”提供的正式机制,且 MiniMax/Volcano/Synthetic 等官方页都给出过同构样例。
  - 需要实测确认的点(仓库内无答案,**未确认**):DeepSeek Anthropic 端点接受的模型 id(如仍叫 `deepseek-chat`,还是 v4 命名);`anthropic-version` 头等是否需要透传(OpenClaw 对非官方主机自动抑制隐式 beta 头,基础头由适配器自带)。建议上线前用 `openclaw agent exec --model ds-anthropic/<id> --json "ping"` 做一次连通性验收,或用 `curl https://api.deepseek.com/anthropic/v1/messages` 先手工探端点契约。
- 若坚持走官方 DeepSeek 插件但想切 Anthropic 端点:在插件 provider id 上覆写 `models.providers.deepseek.baseUrl` + `api:"anthropic-messages"` 也属于文档允许的“路由改写”,但会与插件自带目录/适配器语义交互,doctor 会保留分歧值待人工复核——spike 阶段更推荐独立的 `ds-anthropic` 自定义 provider,隔离干净。
- 追加 key/多 key 轮换:`<PROVIDER>_API_KEYS`(逗号/分号列表)、`<PROVIDER>_API_KEY_1...`、`OPENCLAW_LIVE_<PROVIDER>_KEY` 最高优先;仅在 429/限流类错误时轮换(出处:model-providers.md "API key rotation")。

## 5. skill 目录结构与最小示例

出处:`docs/tools/creating-skills.md`、`docs/tools/skills.md`(加载顺序/format)、`docs/cli/skills.md`。

- **位置(优先级从高到低)**:workspace `<workspace>/skills` > `<workspace>/.agents/skills` > `~/.agents/skills` > `<state-dir>/skills` > 内置(捆绑 + custodian)> `skills.load.extraDirs`。spike 场景直接放 agent 自己的 `~/.openclaw/workspace/skills/<name>/SKILL.md`。
- **结构**:skill = 一个目录 + `SKILL.md`(YAML frontmatter + Markdown 指令体)。`SKILL.md` 出现在根目录下任意深度即被发现(嵌套仅用于组织;技能名取自 frontmatter `name`)。文档示例目录里还可放 `scripts/`、`references/`、`assets/` 等,正文用 `{baseDir}` 引用技能目录内文件(如 `{baseDir}/scripts/run.sh`)。
- **SKILL.md frontmatter 字段**:
  - 必填:`name`(小写字母/数字/连字符,与目录名一致)、`description`(一行,<160 字符)。
  - 可选:`user-invocable`(默认 true,是否暴露为 `/skill` 斜杠命令)、`disable-model-invocation`(false= 默认进系统提示)、`command-dispatch: tool` + `command-tool`(把斜杠命令直接路由到工具)、`command-arg-mode`、`homepage`;门控用 `metadata: { "openclaw": { requires: { bins:[...], env:[...], config:[...] }, os:["darwin"], always } }`。
- 最小示例:
  ```markdown
  ---
  name: dir-watcher
  description: 扫描指定目录的新文件并输出清单
  ---
  当需要检查新文件时,运行 `{baseDir}/scripts/scan.sh <dir>` 并把结果整理成要点。
  ```
- 验证/测试:`openclaw skills list`;会话内 `/skill <name>` 或 `/new`(换新会话);CLI 直测 `openclaw agent --message "..."`。ClawHub 发布可选(独立 `clawhub` CLI)。

## 6. headless / worker 可行性结论

出处:`docs/cli/cron.md`、`docs/automation/cron-jobs.md`、`docs/cli/agent.md`、`docs/cli/gateway.md`、`docs/start/getting-started.md`。

- **结论:可行,且是文档头等支持的形态。** cron 不需要任何消息渠道:agent 回合结果可 `--webhook` POST、`--no-deliver` 留在内部运行历史,或干脆用 `command`/`script` payload 跑确定性脚本(连模型都不调)。
- 依赖两点:(1) **Gateway 常驻**(调度器在 Gateway 进程内)——macOS `openclaw gateway install`(launchd),开机自启;(2) 有一个可用模型 provider(§2.1 配置)与一个默认/main agent。
- 备选“无常驻调度器”路径:用系统 cron / launchd 调 **`openclaw agent exec`**(嵌入式单发回合,推荐给 CI;自带 setup/清理/JSON envelope,`--model`/`--config`/`--timeout` 可配),文档特别给了外部调度包装建议:`timeout -k 60 600 openclaw agent ...`(见 `docs/cli/agent.md` "How automations work" 旁注、`docs/cli/cron.md`)。spike 建议优先用内建 automations(自带持久化/重试/失败告警/run 历史),不必自建 launchd 脚本。
- 无渠道时“告诉人类结果”的最接近做法:webhook POST 到本机/远端接收端(如轻量 HTTP 服务把 body 落盘),或让任务把报告写文件后由别的工具(如 `openclaw agent exec --message-file`)汇总;内建没有“文件尾行/文件夹推送”投递目标,需要自己写接收器(**未确认**是否有官方文件投递 target——文档只列 chat/webhook/none)。

## 7. VPS / 服务器部署(Phase 3 预告,简记)

出处:`docs/vps.md`(真实存在于仓库,标题 “Linux server”)、`docs/install/index.md`、`docs/platforms/linux.md`、`docs/gateway/multi-tenant-hosting.md`。

- 形态:Gateway 跑在 VPS 上并持有 state+workspace;本机用 Control UI / Tailscale / SSH 隧道访问。默认 `gateway.port 18789`;安全默认绑定 loopback,公开绑定需 `gateway.auth.token`/`password`。
- 安装:同一安装器(`curl -fsSL https://openclaw.ai/install.sh | bash`),`openclaw onboard --install-daemon` 装 systemd user unit(`systemctl --user edit openclaw-gateway.service` 可加 `NODE_COMPILE_CACHE`、`OPENCLAW_NO_RESPAWN=1` 等小 VM 优化)。Docker/K8s/各云商有专门指南。
- 备份:state + workspace(自带 `openclaw backup create`,SQLite 状态库)。
- 因为调研环境最初给的是不存在的路径假设,特此更正:仓库确有 `docs/vps.md`,抓取成功。

## 8. 抓取/验证情况与未确认清单

- 用 `api.github.com/.../contents` 抓取全部成功;因后续发现 `github.com` 可达,直接 `git clone --depth 1` 了整库在 `/tmp/openclaw-repo`(提交 3a5fc8f),故正文所有出处均以本地克隆核对,无跳过项。
- **未确认 / 需实测**:
  1. DeepSeek Anthropic 端点(`https://api.deepseek.com/anthropic`)实际接受的模型 id 与 header 契约(仓库只记录其 OpenAI 兼容目录)。
  2. `openclaw.ai/install.sh` 在本环境的可达性(本备忘只照录官方命令,未实际执行安装)。
  3. 官方 DeepSeek 插件目录模型名(deepseek-v4-flash/pro)与你拿到的 DeepSeek 最新文档是否一致(仓库称旧 id 已于 2026-07-24 退役)。
  4. “文件投递 target”是否存在(官方投递仅 chat/webhook/none)。

## 9. 关键命令速查

```bash
# 安装/初始化
npm install -g openclaw@latest --allow-scripts=openclaw
openclaw setup --baseline                     # 无引导建 baseline
openclaw gateway install && openclaw gateway status   # 后台常驻(launchd),端口 18789
# provider(自定义 Anthropic 兼容端点)→ 编辑 ~/.openclaw/openclaw.json(§2.1),然后:
openclaw config validate
openclaw agent exec --model ds-anthropic/deepseek-chat --json "连通性测试"   # 嵌入式验收
# cron 监控任务
openclaw automations add --every 5m --session isolated --agent monitor \
  --message "扫描 ~/data/inbox 的新文件并生成报告" --no-deliver --name scan-inbox
openclaw automations list; openclaw automations runs --id <job-id>
# skill
mkdir -p ~/.openclaw/workspace/skills/dir-watcher   # 放 SKILL.md + scripts/
openclaw skills list
```
