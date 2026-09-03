#!/usr/bin/env bash
# run_once.sh —— 数据平面一轮监控(由 systemd timer 每 60s 调用, 也可手动执行):
#   1) collect_metrics.sh   指标快照
#   2) scan_logs.sh         增量扫描日志 → 异常 Incident
#   3) check_resources.sh   资源超阈值 → 资源 Incident (AIOPS_WATCH_RESOURCES=true 时)
# 用法: bash run_once.sh [--config]
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/common.sh"

if [ "${1:-}" = "--config" ]; then
  echo "当前有效配置(可在命令行用同名环境变量覆盖):"
  for v in AIOPS_APP_NAME AIOPS_APP_ENV AIOPS_STATE_DIR AIOPS_INCIDENT_DIR AIOPS_APP_LOG \
           AIOPS_DEDUP_WINDOW_SEC AIOPS_MAX_EXCERPT_LINES \
           AIOPS_WATCH_RESOURCES AIOPS_CPU_WARN_PCT AIOPS_MEM_WARN_PCT AIOPS_RESOURCE_CONSECUTIVE \
           AIOPS_COLLECT_METRICS; do
    printf '  %s=%s\n' "$v" "${!v}"
  done
  exit 0
fi

ensure_dir "$AIOPS_STATE_DIR"
ensure_dir "$AIOPS_INCIDENT_DIR"

before="$(find "$AIOPS_INCIDENT_DIR" -name 'inc-*.json' 2>/dev/null | wc -l | tr -d ' ')"

log_info "=== 开始一轮监控 (app=$AIOPS_APP_NAME env=$AIOPS_APP_ENV) ==="
if [ "${AIOPS_COLLECT_METRICS:-true}" = "true" ]; then
  bash "$SCRIPT_DIR/collect_metrics.sh"
else
  log_info "指标采集已跳过(AIOPS_COLLECT_METRICS=false), Incident.metrics 将输出 0"
fi
bash "$SCRIPT_DIR/scan_logs.sh"
if [ "${AIOPS_WATCH_RESOURCES:-false}" = "true" ]; then
  bash "$SCRIPT_DIR/check_resources.sh"
else
  log_info "资源告警未开启(设置 AIOPS_WATCH_RESOURCES=true 启用)"
fi

after="$(find "$AIOPS_INCIDENT_DIR" -name 'inc-*.json' 2>/dev/null | wc -l | tr -d ' ')"
log_info "=== 本轮结束: 新增 Incident $((after - before)) 个, 队列总数 $after 个 ==="
if [ "$after" -gt "$before" ]; then
  log_info "消费提示: Phase 3 的 AI worker(OpenClaw/自研 agent)将从此目录消费 status=new 的 Incident"
fi
exit 0   # 成功路径恒返回 0(即使本轮无新增), 避免 timer/journal 视为失败
