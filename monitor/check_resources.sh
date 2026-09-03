#!/usr/bin/env bash
# check_resources.sh —— 资源告警: CPU/内存连续 N 次采样超阈值 → Incident(type=cpu|memory)
# 需先由 collect_metrics.sh 生成 metrics-latest.json; 由 run_once.sh 顺序调用。
# 防抖: 连续 AIOPS_RESOURCE_CONSECUTIVE 次超阈值才发事件; 一旦回落立即清零计数。
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/common.sh"
require_cmd jq

[ "$AIOPS_WATCH_RESOURCES" = "true" ] || exit 0

METRICS_FILE="$AIOPS_STATE_DIR/metrics-latest.json"
[ -f "$METRICS_FILE" ] || { log_warn "metrics-latest.json 不存在, 跳过资源检查"; exit 0; }

cpu="$(jq -r '.cpuPct // 0' "$METRICS_FILE")"
mem="$(jq -r '.memUsedPct // 0' "$METRICS_FILE")"
ensure_dir "$AIOPS_STATE_DIR"
CPU_N_FILE="$AIOPS_STATE_DIR/res_cpu_n"; MEM_N_FILE="$AIOPS_STATE_DIR/res_mem_n"

ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a >= b)}'; }   # 浮点比较
bump() { local f="$1" n=0; [ -f "$f" ] && n="$(cat "$f")"; echo $((n + 1)) > "$f"; }
reset_f() { [ -f "$1" ] && echo 0 > "$1"; }

cpu_hit=0; mem_hit=0
ge "$cpu" "$AIOPS_CPU_WARN_PCT" && cpu_hit=1
ge "$mem" "$AIOPS_MEM_WARN_PCT" && mem_hit=1

if [ "$cpu_hit" -eq 1 ]; then
  bump "$CPU_N_FILE"; n="$(cat "$CPU_N_FILE")"
  if [ "$n" -ge "$AIOPS_RESOURCE_CONSECUTIVE" ]; then
    log_warn "CPU ${cpu}% 连续 ${n} 次超 ${AIOPS_CPU_WARN_PCT}%, 生成 cpu 告警 Incident"
    INC_TYPE="cpu" INC_SEVERITY="high" INC_COUNT=1 INC_SIGNATURE="cpu usage ${cpu}% above ${AIOPS_CPU_WARN_PCT}% for ${n} consecutive samples" \
    INC_LOG_EXCERPT="资源告警: CPU ${cpu}%(阈值 ${AIOPS_CPU_WARN_PCT}%), 连续 ${n} 次采样超阈值(每 60s 一次)。无相关异常日志, 需按类型=cpu 分析。" \
      bash "$SCRIPT_DIR/emit_incident.sh" || log_warn "emit_incident 调用失败"
    reset_f "$CPU_N_FILE"
  fi
else
  reset_f "$CPU_N_FILE"
fi

if [ "$mem_hit" -eq 1 ]; then
  bump "$MEM_N_FILE"; n="$(cat "$MEM_N_FILE")"
  if [ "$n" -ge "$AIOPS_RESOURCE_CONSECUTIVE" ]; then
    log_warn "内存 ${mem}% 连续 ${n} 次超 ${AIOPS_MEM_WARN_PCT}%, 生成 memory 告警 Incident"
    INC_TYPE="memory" INC_SEVERITY="high" INC_COUNT=1 INC_SIGNATURE="memory usage ${mem}% above ${AIOPS_MEM_WARN_PCT}% for ${n} consecutive samples" \
    INC_LOG_EXCERPT="资源告警: 内存 ${mem}%(阈值 ${AIOPS_MEM_WARN_PCT}%), 连续 ${n} 次采样超阈值(每 60s 一次)。无相关异常日志, 需按类型=memory 分析。" \
      bash "$SCRIPT_DIR/emit_incident.sh" || log_warn "emit_incident 调用失败"
    reset_f "$MEM_N_FILE"
  fi
else
  reset_f "$MEM_N_FILE"
fi
