#!/usr/bin/env bash
# emit_incident.sh —— 按契约 v1 生成 Incident JSON 到 $AIOPS_INCIDENT_DIR
# 由 scan_logs.sh / check_resources.sh 调用; 通过环境变量传入事件信息:
#   INC_TYPE         exception|oom|cpu|memory|unknown (必填)
#   INC_SEVERITY     critical|high|medium|low        (必填)
#   INC_LOG_EXCERPT  日志摘录(可空, 资源告警时为触发说明)
#   INC_SIGNATURE    归一化签名(去抖/聚合用, 可空)
#   INC_COUNT        累计出现次数(默认 1)
# 事件 ID 单调递增: inc-YYYYMMDD-NNNN, 计数器在 $AIOPS_STATE_DIR/incident_seq
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/common.sh"
require_cmd jq

INC_TYPE="${INC_TYPE:-unknown}"
INC_SEVERITY="${INC_SEVERITY:-medium}"
INC_LOG_EXCERPT="${INC_LOG_EXCERPT:-}"
INC_SIGNATURE="${INC_SIGNATURE:-unknown}"
INC_COUNT="${INC_COUNT:-1}"

ensure_dir "$AIOPS_STATE_DIR"
ensure_dir "$AIOPS_INCIDENT_DIR"

SEQ_FILE="$AIOPS_STATE_DIR/incident_seq"
seq="0"; [ -f "$SEQ_FILE" ] && seq="$(cat "$SEQ_FILE")"
seq=$((seq + 1)); printf '%s' "$seq" > "$SEQ_FILE"

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
ID="$(printf 'inc-%s-%04d' "$(date -u +%Y%m%d)" "$seq")"
OUT="$AIOPS_INCIDENT_DIR/${ID}.json"

# 事件主体
jq -n \
  --arg sv "v1" --arg id "$ID" --arg app "$AIOPS_APP_NAME" --arg env "$AIOPS_APP_ENV" \
  --arg sev "$INC_SEVERITY" --arg type "$INC_TYPE" --arg ts "$TS" \
  --argjson count "$INC_COUNT" --arg sig "$INC_SIGNATURE" --arg ex "$INC_LOG_EXCERPT" \
  '{schemaVersion: $sv, incidentId: $id, app: $app, env: $env, severity: $sev,
    type: $type, firstSeenAt: $ts, count: $count, signature: $sig,
    logExcerpt: $ex, status: "new"}' \
  > "$OUT.part"

# 附上同一时刻的指标快照(若有)
METRICS_FILE="$AIOPS_STATE_DIR/metrics-latest.json"
if [ -f "$METRICS_FILE" ]; then
  M="$(jq -c '{ts, cpuPct, memUsedMb, memTotalMb, memUsedPct, loadAvg1}' "$METRICS_FILE")"
else
  M="$(jq -nc --arg ts "$TS" '{ts: $ts, cpuPct: 0, memUsedMb: 0, memTotalMb: 0, memUsedPct: 0, loadAvg1: 0}')"
fi
jq -n --argjson m "$M" --slurpfile b "$OUT.part" '$b[0] + {metrics: $m}' > "$OUT"
rm -f "$OUT.part"

log_info "Incident 已生成: $ID ($INC_SEVERITY/$INC_TYPE, count=$INC_COUNT) -> $OUT"
echo "$ID"
