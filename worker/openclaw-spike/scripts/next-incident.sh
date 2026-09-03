#!/usr/bin/env bash
# next-incident.sh —— 取出队列中第一个"未最终处理"的 Incident 路径(无则静默)
# 说明: 领取范围 = status 为 new 或 analyzing(analyzing 视为"上次运行可能中断, 允许续跑/重跑");
#       已 analyzed/ignored 的不再领取。由 AGENTS.md 工作流第 1 步调用。
# 用法: bash next-incident.sh
set -Eeuo pipefail
AIOPS_INCIDENT_DIR="${AIOPS_INCIDENT_DIR:-/var/lib/aiops/incidents}"

[ -d "$AIOPS_INCIDENT_DIR" ] || exit 0

for f in "$AIOPS_INCIDENT_DIR"/inc-*.json; do
  [ -f "$f" ] || continue
  st="$(jq -r '.status // "new"' "$f")"
  if [ "$st" != "analyzed" ] && [ "$st" != "ignored" ]; then
    echo "$f"
    exit 0
  fi
done
exit 0
