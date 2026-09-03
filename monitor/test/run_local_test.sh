#!/usr/bin/env bash
# run_local_test.sh —— 本地端到端测试(不依赖 Java/Maven/服务器)
#
# 设计(确定性): 把去抖窗口设为 1s, 每轮之间 sleep 2s, 使"窗口内抑制"与
# "窗口过后重新告警"都能被稳定观测:
#   R1 fixture 全量 → 恰 3 个 Incident (NPE / IllegalStateException-boom / OOM-critical)
#   R2 无新增日志   → 0 个新增        (增量 offset 生效)
#   R3 追加同一条 boom → 恰 +1 个      (若增量失效会重发 NPE/OOM → +3, 以此判定)
# 用法: bash monitor/test/run_local_test.sh
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORK="$(mktemp -d /tmp/aiops-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/state" "$WORK/incidents" "$WORK/logs"
cp "$FIXTURE_DIR/fixtures/app.log" "$WORK/logs/app.log"

export AIOPS_STATE_DIR="$WORK/state"
export AIOPS_INCIDENT_DIR="$WORK/incidents"
export AIOPS_APP_LOG="$WORK/logs/app.log"
export AIOPS_WATCH_RESOURCES=false
export AIOPS_APP_ENV=local
export AIOPS_DEDUP_WINDOW_SEC=1        # 测试专用: 极小去抖窗口
export AIOPS_COLLECT_METRICS=false     # 专注日志扫描链路(受限环境可能无 ps 权限); Incident.metrics 输出 0

count_incidents() { find "$WORK/incidents" -name 'inc-*.json' | wc -l | tr -d ' '; }

echo "==> R1: fixture 全量扫描, 期望恰 3 个 Incident (NPE / boom / OOM)"
bash "$ROOT/monitor/run_once.sh"
n1="$(count_incidents)"
[ "$n1" -eq 3 ] || { echo "FAIL: R1 生成 $n1 个(期望 3)"; ls -la "$WORK/incidents"; exit 1; }

echo "==> R1 契约与严重度校验"
critical=0
for f in "$WORK/incidents"/inc-*.json; do
  jq -e '.schemaVersion == "v1" and (.incidentId|startswith("inc-")) and (.status == "new")
         and (.metrics.cpuPct|type == "number") and (.logExcerpt|length > 0)' "$f" >/dev/null \
    || { echo "FAIL: 契约字段不合法 -> $f"; exit 1; }
  s="$(jq -r '.severity' "$f")"
  [ "$s" = "critical" ] && critical=$((critical + 1))
done
[ "$critical" -eq 1 ] || { echo "FAIL: 期望 1 个 critical(OOM), 实际 $critical"; exit 1; }
echo "PASS: 契约合法, 恰 1 个 critical(OOM)"

echo "==> R2: 无新增日志(等 2s 越过窗口), 期望 0 个新增"
sleep 2
bash "$ROOT/monitor/run_once.sh"
n2="$(count_incidents)"
[ "$n2" -eq "$n1" ] || { echo "FAIL: R2 新增 Incident ($n1 -> $n2)"; exit 1; }
echo "PASS: R2 无新增"

echo "==> R3: 追加与 fixture 中完全相同的 boom, 期望恰 +1 个(增量扫描 + 窗口过后重发)"
sleep 2
cat >> "$WORK/logs/app.log" <<'EOF'
2025-07-01 10:03:45.555 ERROR 12345 --- [http-nio-8080-exec-9] c.e.demo.web.FlakyController     : Servlet.service() for servlet [dispatcherServlet] in context with path [] threw exception [Request processing failed; nested exception is java.lang.IllegalStateException: boom] with root cause
java.lang.IllegalStateException: boom
    at c.e.demo.service.FlakyService.boom(FlakyService.java:31)
EOF
bash "$ROOT/monitor/run_once.sh"
n3="$(count_incidents)"
[ "$n3" -eq $((n2 + 1)) ] || { echo "FAIL: R3 期望 +1 ($n2 -> $n3)。若为 +3 说明增量扫描失效, 请检查 scan_logs.sh 的 offset 逻辑"; exit 1; }
echo "PASS: R3 恰新增 1 个(增量扫描正常, 未重发 NPE/OOM)"

echo "==> R4(回归): 同一异常出现在不同线程(exec-21/exec-77), 窗口内应只 +1 个 Incident"
echo "    —— 若 +2 说明签名未去除线程名方括号, 去抖对线程池场景失效"
sleep 2
cat >> "$WORK/logs/app.log" <<'EOF'
2025-07-01 10:04:01.001 ERROR 12345 --- [http-nio-8080-exec-21] c.e.demo.web.FlakyController     : Servlet.service() for servlet [dispatcherServlet] in context with path [] threw exception [Request processing failed; nested exception is java.lang.IllegalStateException: boom2] with root cause
java.lang.IllegalStateException: boom2
    at c.e.demo.service.FlakyService.boom(FlakyService.java:31)
2025-07-01 10:04:01.002 ERROR 12345 --- [http-nio-8080-exec-77] c.e.demo.web.FlakyController     : Servlet.service() for servlet [dispatcherServlet] in context with path [] threw exception [Request processing failed; nested exception is java.lang.IllegalStateException: boom2] with root cause
java.lang.IllegalStateException: boom2
    at c.e.demo.service.FlakyService.boom(FlakyService.java:31)
EOF
bash "$ROOT/monitor/run_once.sh"
n4="$(count_incidents)"
[ "$n4" -eq $((n3 + 1)) ] || { echo "FAIL: R4 期望 +1 ($n3 -> $n4)。若为 +2 请检查 scan_logs.sh 是否去除了含数字的线程名方括号"; exit 1; }
echo "PASS: R4 跨线程同异常在窗口内只发 1 个 Incident(去抖按异常而非按线程)"

echo "==> 全部通过 ✅  样例 Incident:"
jq '{incidentId, severity, type, count, signature, excerptFirstLine: (.logExcerpt|split("\n")[0])}' \
  "$WORK/incidents"/inc-*.json
