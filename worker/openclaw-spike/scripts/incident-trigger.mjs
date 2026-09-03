// incident-trigger —— OpenClaw cron 条件触发器(沙箱内联 JS 契约, 见 docs/automation/cron-jobs.md "Event triggers")
// 只能使用沙箱全局: exec / json / trigger(trigger.state 为上次持久化状态, 深冻结)。
// 契约: 必须返回 { fire: bool, message?: string, state?: {...} } —— 用 json({...}) 输出。
// 语义: 队列中出现"未被最终处理"的 Incident(status != analyzed/ignored)才 fire, 避免空转烧 token;
//       message 自包含(会作为 agent 回合的完整事件上下文)。
const DIR = "/Users/stefenagents/stefen-agents/worker/openclaw-spike/.data/incidents";

const res = await exec({
  command: [
    `for f in "${DIR}"/inc-*.json; do`,
    `  [ -f "$f" ] || continue`,
    `  st=$(jq -r '.status // "new"' "$f")`,
    `  if [ "$st" != "analyzed" ] && [ "$st" != "ignored" ]; then echo "$f"; exit 0; fi`,
    `done`,
    `exit 0`,
  ].join("\n"),
});

const out = String(res?.aggregated ?? "").trim();
if (!out) {
  json({ fire: false, state: trigger.state ?? {} });
} else {
  json({
    fire: true,
    message: `有新 Incident 需要分析: ${out}。请按 AGENTS.md 工作流处理(领取→读事件→取证→产出契约 v1 报告→submit-report 落盘并流转状态)。`,
    state: trigger.state ?? {},
  });
}
