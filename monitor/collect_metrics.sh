#!/usr/bin/env bash
# collect_metrics.sh —— 采集 CPU/内存/负载快照 → $AIOPS_STATE_DIR/metrics-latest.json
# 用途: (1) 作为 Incident 的 metrics 快照; (2) check_resources.sh 判断资源告警。
# 平台: Linux 走 /proc 精确计算; macOS 为 best-effort(本地体验用), 生产请用 Linux。
# 健壮性: 系统命令不可用(如受限容器/沙箱)时输出 0 并告警, 不中断整轮监控。
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/common.sh"
require_cmd jq

ensure_dir "$AIOPS_STATE_DIR"
METRICS_FILE="$AIOPS_STATE_DIR/metrics-latest.json"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
OS="$(uname -s)"

cpu_pct="0"; mem_total_mb="0"; mem_used_mb="0"; mem_used_pct="0"; load1="0"

if [ "$OS" = "Linux" ]; then
  # ---- CPU: 两次采样 /proc/stat 取增量 (采样间隔 1s) ----
  read_cpu() {
    # shellcheck disable=SC2034
    read -r _ u n s i w x y z _ < /proc/stat
    idle_total=$((i + w)); sum_total=$((u + n + s + i + w + x + y + z))
  }
  read_cpu; t1=$sum_total; i1=$idle_total
  sleep 1
  read_cpu; t2=$sum_total; i2=$idle_total
  d_idle=$((i2 - i1)); d_total=$((t2 - t1))
  [ "$d_total" -le 0 ] && d_total=1
  cpu_pct="$(awk -v d="$d_idle" -v t="$d_total" 'BEGIN{printf "%.1f", (1 - d/t) * 100}')"
  # ---- 内存: /proc/meminfo ----
  mem_kb_total="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
  mem_kb_avail="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)"
  mem_total_mb=$((mem_kb_total / 1024))
  mem_used_mb=$(((mem_kb_total - mem_kb_avail) / 1024))
  mem_used_pct="$(awk -v u="$mem_used_mb" -v t="$mem_total_mb" 'BEGIN{ if (t>0) printf "%.1f", u/t*100; else print 0 }')"
  load1="$(awk '{print $1}' /proc/loadavg)"
elif [ "$OS" = "Darwin" ]; then
  # ---- macOS: best-effort。ps/sysctl/vm_stat 不可用时给 0 并告警 ----
  warn_count=0
  if command -v ps >/dev/null 2>&1; then
    c="$(ps -A -o %cpu 2>/dev/null | awk '{s += $1} END{printf "%.1f", s}')" || c=""
    [ -n "$c" ] && cpu_pct="$c" || warn_count=$((warn_count + 1))
  else
    warn_count=$((warn_count + 1))
  fi
  m_total="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
  if [ "${m_total:-0}" -gt 0 ]; then
    mem_total_mb=$((m_total / 1048576))
    page_size="$(vm_stat 2>/dev/null | awk '/page size of/{print $8}')"
    free_pages="$(vm_stat 2>/dev/null | awk '/Pages free/{gsub(/\./,"",$3); print $3}')"
    if [ -n "${page_size:-}" ] && [ -n "${free_pages:-}" ]; then
      mem_used_mb=$(( mem_total_mb - free_pages * page_size / 1048576 ))
    else
      warn_count=$((warn_count + 1))
    fi
    mem_used_pct="$(awk -v u="$mem_used_mb" -v t="$mem_total_mb" 'BEGIN{ if (t>0) printf "%.1f", u/t*100; else print 0 }')"
  else
    warn_count=$((warn_count + 1))
  fi
  load1="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')" || load1=""
  [ -n "$load1" ] || load1="0"
  [ "$warn_count" -gt 0 ] && log_warn "macOS 部分系统命令不可用, 相关指标输出 0 (本地测试可用 AIOPS_COLLECT_METRICS=false 跳过)"
else
  log_warn "未识别的操作系统 $OS, 指标输出 0。生产请使用 Linux。"
fi

jq -n \
  --arg ts "$TS" \
  --argjson cpu "${cpu_pct:-0}" \
  --argjson total "${mem_total_mb:-0}" \
  --argjson used "${mem_used_mb:-0}" \
  --argjson upct "${mem_used_pct:-0}" \
  --argjson load "${load1:-0}" \
  '{ts: $ts, cpuPct: $cpu, memUsedMb: $used, memTotalMb: $total, memUsedPct: $upct, loadAvg1: $load}' \
  > "$METRICS_FILE.tmp"
mv "$METRICS_FILE.tmp" "$METRICS_FILE"
log_info "指标快照已写入 $METRICS_FILE (cpu=${cpu_pct}% mem=${mem_used_pct}% load1=${load1})"
