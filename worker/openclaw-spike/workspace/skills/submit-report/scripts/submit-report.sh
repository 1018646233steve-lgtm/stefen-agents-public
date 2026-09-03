#!/usr/bin/env bash
# submit-report skill 后端 —— 契约 v1 AnalysisReport 落盘 + Incident 状态流转
# 用法: bash submit-report.sh <report.json>
set -Eeuo pipefail

REPORT="${1:?用法: submit-report.sh <report.json>}"
AIOPS_INCIDENT_DIR="${AIOPS_INCIDENT_DIR:-/var/lib/aiops/incidents}"
AIOPS_REPORTS_DIR="${AIOPS_REPORTS_DIR:-/var/lib/aiops/reports}"
AIOPS_REPORT_WEBHOOK="${AIOPS_REPORT_WEBHOOK:-}"

[ -f "$REPORT" ] || { echo "错误: 报告文件不存在: $REPORT" >&2; exit 1; }

# ---- 1) 契约校验(必填字段, 与 contracts/report.schema.json 对齐) ----
jq -e '
  .schemaVersion == "v1"
  and (.reportId | type == "string") and (.reportId | startswith("rpt-"))
  and (.incidentId | type == "string")
  and (.rootCause | type == "string") and (.rootCause | length > 0)
  and (.evidence | type == "array") and (.evidence | length >= 1)
  and (.fixSuggestions | type == "array") and (.fixSuggestions | length >= 1)
  and (.confidence | type == "number")
' "$REPORT" >/dev/null \
  || { echo "错误: 报告不符合契约 v1(缺必填字段或字段类型错误), 拒绝落盘" >&2; jq 'keys' "$REPORT" >&2; exit 1; }

INCIDENT_ID="$(jq -r '.incidentId' "$REPORT")"
REPORT_ID="$(jq -r '.reportId' "$REPORT")"

# ---- 2) 落盘(原子写) ----
mkdir -p "$AIOPS_REPORTS_DIR"
OUT="$AIOPS_REPORTS_DIR/${INCIDENT_ID}.report.json"
jq . "$REPORT" > "$OUT.part" && mv "$OUT.part" "$OUT"
echo "报告已落盘: $OUT"

# ---- 3) Incident 状态流转: analyzing -> analyzed ----
INC_FILE="$AIOPS_INCIDENT_DIR/${INCIDENT_ID}.json"
if [ -f "$INC_FILE" ]; then
  jq '.status = "analyzed"' "$INC_FILE" > "$INC_FILE.part" && mv "$INC_FILE.part" "$INC_FILE"
  echo "Incident 状态已更新: $INC_FILE -> analyzed"
else
  echo "警告: 未找到对应 Incident 文件 $INC_FILE (可能已被移走), 状态未流转" >&2
fi

# ---- 4) 可选: POST 到 Phase 4 后端 ----
if [ -n "$AIOPS_REPORT_WEBHOOK" ]; then
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 -H 'Content-Type: application/json' \
    --data-binary @"$OUT" "$AIOPS_REPORT_WEBHOOK" || true)"
  echo "已 POST 到 $AIOPS_REPORT_WEBHOOK -> HTTP ${code:-失败}"
fi
