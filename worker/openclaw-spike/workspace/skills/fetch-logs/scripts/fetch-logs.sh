#!/usr/bin/env bash
# fetch-logs skill 后端 —— 按 Incident 日志首行时间戳, 拉取事件前后真实日志上下文
# 用法: bash fetch-logs.sh <incident.json> [before=40] [after=80]
set -Eeuo pipefail

INCIDENT="${1:?用法: fetch-logs.sh <incident.json> [before] [after]}"
BEFORE="${2:-40}"
AFTER="${3:-80}"
AIOPS_APP_LOG="${AIOPS_APP_LOG:-/var/log/aiops/app.log}"

[ -f "$INCIDENT" ] || { echo "错误: Incident 文件不存在: $INCIDENT" >&2; exit 1; }
[ -f "$AIOPS_APP_LOG" ] || { echo "错误: 应用日志不存在: $AIOPS_APP_LOG" >&2; exit 1; }

# 从 logExcerpt 首行提取时间戳前缀(两种格式都兼容):
#   "2025-07-01 10:23:11.123 ..."  与  "2026-09-03T17:13:44.513+08:00 ..."
FIRST_LINE="$(jq -r '.logExcerpt | split("\n")[0]' "$INCIDENT")"
TS="$(printf '%s\n' "$FIRST_LINE" | sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}).*/\1/')"
if [ "$TS" = "$FIRST_LINE" ] || [ -z "$TS" ]; then
  echo "警告: 无法从 logExcerpt 首行提取时间戳, 回退输出文件尾部 $AFTER 行" >&2
  tail -n "$AFTER" "$AIOPS_APP_LOG"
  exit 0
fi

# 在日志中找到该时间戳行号(前缀匹配; 用 -m1 取第一处)
LINE_NO="$(grep -n -m1 -F "$TS" "$AIOPS_APP_LOG" | cut -d: -f1 || true)"
if [ -z "$LINE_NO" ]; then
  echo "警告: 日志中未找到 '$TS' (可能已轮转), 回退输出文件尾部 $AFTER 行" >&2
  tail -n "$AFTER" "$AIOPS_APP_LOG"
  exit 0
fi

START=$((LINE_NO - BEFORE)); [ "$START" -lt 1 ] && START=1
END=$((LINE_NO + AFTER))
TOTAL="$(wc -l < "$AIOPS_APP_LOG" | tr -d ' ')"
[ "$END" -gt "$TOTAL" ] && END="$TOTAL"

echo "===== 命中行 #$LINE_NO ($TS), 输出 #$START..#$END (共 $TOTAL 行) ====="
sed -n "${START},${END}p" "$AIOPS_APP_LOG"
