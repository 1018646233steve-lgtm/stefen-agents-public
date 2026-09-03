#!/usr/bin/env bash
# collect-metrics skill 后端 —— 输出最近指标快照 + (可选) demo-app 实时健康
# 用法: bash collect-metrics.sh
set -Eeuo pipefail

# 路径默认值(与 monitor/config.env 一致; 可在环境/配置中覆盖)
AIOPS_STATE_DIR="${AIOPS_STATE_DIR:-/var/lib/aiops/state}"
APP_HEALTH_URL="${APP_HEALTH_URL:-http://127.0.0.1:8080/actuator/health}"
APP_METRICS_URL="${APP_METRICS_URL:-http://127.0.0.1:8080/actuator/metrics/jvm.memory.used}"

MF="$AIOPS_STATE_DIR/metrics-latest.json"
echo "===== 最近指标快照: $MF ====="
if [ -f "$MF" ]; then
  jq . "$MF"
else
  echo "(不存在, 说明 monitor 尚未采集; 事件 metrics 见 Incident JSON)"
fi

echo
echo "===== demo-app 实时状态(可选) ====="
health="$(curl -sS --max-time 3 "$APP_HEALTH_URL" 2>/dev/null || true)"
if [ -n "$health" ]; then
  echo "health: $health"
  metrics="$(curl -sS --max-time 3 "$APP_METRICS_URL" 2>/dev/null || true)"
  [ -n "$metrics" ] && echo "jvm.memory.used: $metrics" || echo "jvm.memory.used: 端点无响应"
else
  echo "demo-app 不可访问($APP_HEALTH_URL 无响应) —— 事件发生时应用可能已不可用, 这本身是线索"
fi
