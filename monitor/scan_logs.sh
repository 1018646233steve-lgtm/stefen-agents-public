#!/usr/bin/env bash
# scan_logs.sh —— 增量扫描应用日志, 按"异常签名"聚合去抖, 生成 Incident(契约 v1)
#
# 设计要点:
#  1. 增量: 记录上次已读字节 offset(state/log_offset), 每次只处理新增部分;
#     日志轮转(文件变小)时自动回到 0 重新开始。
#  2. 事件组: 命中行(ERROR/FATAL/SEVERE/OutOfMemoryError)作为起点,
#     后续堆栈行( at / Caused by / java.xxxException / ... )并入同一事件, 截断到
#     AIOPS_MAX_EXCERPT_LINES 行作为 logExcerpt(上下文裁剪)。
#  3. 去抖: 同一归一化签名在 AIOPS_DEDUP_WINDOW_SEC 内只发一次 Incident,
#     期间的再次出现累加到 count(每次触发时读出并清零), 防止日志风暴刷爆 agent。
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/common.sh"

LOG="$AIOPS_APP_LOG"
if [ ! -f "$LOG" ]; then
  log_warn "应用日志不存在: $LOG (本轮跳过日志扫描)"
  exit 0
fi

ensure_dir "$AIOPS_STATE_DIR"
SIG_DIR="$AIOPS_STATE_DIR/signatures"      # 每个签名: 上次发出的 unix 时间
OCC_DIR="$AIOPS_STATE_DIR/occurrences"     # 每个签名: 去抖窗口内的累计次数
ensure_dir "$SIG_DIR"; ensure_dir "$OCC_DIR"

OFFSET_FILE="$AIOPS_STATE_DIR/log_offset"
last=0; [ -f "$OFFSET_FILE" ] && last="$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)"
size="$(wc -c < "$LOG" | tr -d ' ')"
if [ "$size" -lt "$last" ]; then
  log_warn "检测到日志轮转(size=$size < offset=$last), 从头开始扫描"
  last=0
fi

# 只取新增字节段(避免每轮全量扫描大日志)
CHUNK="$AIOPS_STATE_DIR/scan_chunk.$$"
if [ "$size" -gt "$last" ]; then
  tail -c +$((last + 1)) "$LOG" > "$CHUNK" || true
else
  : > "$CHUNK"   # 无新增
fi
# 按实际读到的字节推进 offset(而非扫描前的 size), 避免扫描期间日志增长导致重复处理
chunk_bytes="$(wc -c < "$CHUNK" | tr -d ' ')"
printf '%s' $((last + chunk_bytes)) > "$OFFSET_FILE"
log_info "日志增量扫描: 从 offset $last 读到 $chunk_bytes 字节"

# 事件边界判定:
#   logback 文件日志里, 每条新日志记录都以时间戳开头(yyyy-MM-dd HH:mm:ss.SSS);
#   堆栈续行(java.lang.XxxException / Caused by / at / ... )不以时间戳开头。
#   因此用"是否以时间戳开头"切分记录, 天然把多行堆栈归并到所属的那条 ERROR 记录,
#   不再依赖易错的行首类名正则。
DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}'
ERR_RE='ERROR|FATAL|SEVERE|OutOfMemoryError'

starter=""; excerpt=""; elines=0; emitted=0

close_event() {
  [ -n "$starter" ] || return 0
  # ★先拷贝并立即清空事件状态: 无论后续走哪条分支(emit/去抖/出错)都不会残留旧事件
  local starter0="$starter" excerpt0="$excerpt"
  local now key occf sigf last_emit occ sev type sig
  starter=""; excerpt=""; elines=0

  now="$(date +%s)"
  # 签名设计: 取日志行的"消息"部分(logback 默认格式里 logger 与消息以 ' : ' 分隔)做归一化:
  #  - 线程名/PID/应用名/时间戳等易变噪声只出现在消息之前的 header 段, 被整体排除,
  #    天然解决"同一异常换线程/换 PID 导致签名漂移、去抖失效"(真实 Tomcat 线程池场景);
  #  - 消息里的 [nested exception is java.lang.XxxException...] 等方括号原样保留,
  #    不同异常不会因误删方括号而被归一成同一签名(去抖误伤);
  #  - 若行内没有 ' : '(非标准格式), 回退到整行归一化。
  # 已知限制: 两处不同代码若 %msg 完全相同会被并入同一签名;
  #   需要更细粒度时把首个应用栈帧(at com.example...)并入签名即可(留作练习)。
  sig="$(printf '%s\n' "$starter0" \
    | awk '{ i = index($0, " : "); if (i > 0) print substr($0, i + 3); else print $0 }' \
    | sed -E \
        -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9:.]+(\+[0-9:]+)?//' \
        -e 's/[0-9]{3,}//g' \
        -e 's/[[:space:]]+/ /g' -e 's/^ //' -e 's/ $//' \
    | tr '[:upper:]' '[:lower:]' \
    | cut -c1-200)"
  key="$(printf '%s' "$sig" | cksum | awk '{print $1}')"
  sigf="$SIG_DIR/$key"; occf="$OCC_DIR/$key"

  occ=0; [ -f "$occf" ] && occ="$(cat "$occf" 2>/dev/null || echo 0)"
  occ=$((occ + 1))

  last_emit=0; [ -f "$sigf" ] && last_emit="$(cat "$sigf" 2>/dev/null || echo 0)"
  if [ "$last_emit" -gt 0 ] && [ $((now - last_emit)) -lt "$AIOPS_DEDUP_WINDOW_SEC" ]; then
    printf '%s' "$occ" > "$occf"     # 窗口内: 只累加次数, 不再发 Incident
    log_info "去抖窗口内命中同一签名(${starter0:0:60}...), 累计 count=$occ, 跳过"
    return 0
  fi

  # 严重度/类型判定
  sev="high"; type="exception"
  if printf '%s' "$starter0" | grep -qi 'OutOfMemoryError'; then sev="critical"; type="oom"
  elif printf '%s' "$starter0" | grep -q 'FATAL';            then sev="critical"
  fi

  INC_TYPE="$type" INC_SEVERITY="$sev" INC_COUNT="$occ" \
  INC_SIGNATURE="$sig" INC_LOG_EXCERPT="$excerpt0" \
    bash "$SCRIPT_DIR/emit_incident.sh" || log_warn "emit_incident 调用失败"
  emitted=$((emitted + 1))
  printf '%s' "$now" > "$sigf"
  printf '0' > "$occf"
}

# 逐行处理新增段
while IFS= read -r line || [ -n "$line" ]; do
  if printf '%s' "$line" | grep -Eq "$DATE_RE"; then
    # 新日志记录: 先关闭当前事件; 该记录含错误级别才作为新事件起点
    close_event
    if printf '%s' "$line" | grep -Eq "$ERR_RE"; then
      starter="$line"; excerpt="$line"; elines=1
    fi
  elif [ -n "$starter" ] && [ -n "$line" ] && [ "$elines" -lt "$AIOPS_MAX_EXCERPT_LINES" ]; then
    # 非时间戳开头的行 = 当前事件的堆栈续行(在摘录行数上限内并入)
    excerpt="${excerpt}
${line}"
    elines=$((elines + 1))
  fi
done < "$CHUNK"
close_event
rm -f "$CHUNK"

log_info "日志扫描完成, 本轮生成 $emitted 个 Incident"
