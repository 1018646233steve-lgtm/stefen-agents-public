#!/usr/bin/env bash
# demo-incidents.sh —— 为 spike 生成"真实"样例数据(不需要启动 Java):
#   用仓库 monitor 数据平面处理自带样例日志(fixtures/app.log, 含 NPE/boom/OOM),
#   产出契约 v1 的 Incident 队列 + 日志文件 + 指标快照, 供 OpenClaw agent 消费分析。
# 用法: bash demo-incidents.sh
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SPIKE_DIR="$ROOT/worker/openclaw-spike"
DATA_DIR="${AIOPS_DATA_DIR:-$SPIKE_DIR/.data}"

echo "== 重置 spike 数据目录: $DATA_DIR =="
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR/incidents" "$DATA_DIR/state" "$DATA_DIR/logs" "$DATA_DIR/reports"

cp "$ROOT/monitor/test/fixtures/app.log" "$DATA_DIR/logs/app.log"

echo "== 用 monitor 数据平面跑一轮(生成 Incident + 指标快照) =="
AIOPS_APP_NAME=demo-app \
AIOPS_APP_ENV=local \
AIOPS_STATE_DIR="$DATA_DIR/state" \
AIOPS_INCIDENT_DIR="$DATA_DIR/incidents" \
AIOPS_APP_LOG="$DATA_DIR/logs/app.log" \
AIOPS_WATCH_RESOURCES=false \
AIOPS_COLLECT_METRICS=true \
  bash "$ROOT/monitor/run_once.sh" 2>&1 | grep -E "Incident 已生成|新增|快照"

echo
echo "== 队列内容 =="
for f in "$DATA_DIR"/incidents/inc-*.json; do
  [ -f "$f" ] && jq -r '"\(.incidentId) | \(.severity)/\(.type) | count=\(.count) | status=\(.status)"' "$f"
done
echo
echo "队列目录: $DATA_DIR/incidents"
echo "指标快照: $DATA_DIR/state/metrics-latest.json"
echo "应用日志: $DATA_DIR/logs/app.log"
echo "报告目录: $DATA_DIR/reports"
