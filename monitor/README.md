# monitor/ —— 数据平面（无 LLM）

纯 bash + jq 实现的监控与告警，产物是**契约 v1 的 Incident JSON**（见 `../contracts/`）。
这一层刻意不用 LLM：指标阈值判断是确定性问题，用脚本免费且可靠；LLM 留给低频分析（Phase 3+）。

## 组件

| 脚本 | 作用 |
|---|---|
| `config.env` | 全部可调参数（可用同名环境变量覆盖） |
| `lib/common.sh` | 日志/目录/依赖检查工具 |
| `collect_metrics.sh` | CPU/内存/负载快照 → `state/metrics-latest.json`（Linux 精确；macOS best-effort） |
| `scan_logs.sh` | 增量扫描 `AIOPS_APP_LOG`，异常签名聚合 + 去抖 → Incident(type=exception/oom) |
| `check_resources.sh` | 连续 N 次超阈值才告警 → Incident(type=cpu/memory)；需 `AIOPS_WATCH_RESOURCES=true` |
| `emit_incident.sh` | 按契约生成 Incident JSON（内部被上面两个调用） |
| `run_once.sh` | 一键一轮监控；systemd timer 每 60s 调用 |
| `test/` | 本地端到端测试 + fixture 日志 |

## 运行原理（30 秒看懂）

```
run_once.sh
 ├─ collect_metrics.sh ──────────────► state/metrics-latest.json
 ├─ scan_logs.sh (只读上次 offset 后的新增行)
 │    ├─ 命中 ERROR/FATAL/SEVERE/OOM → 组事件(截取前 N 行堆栈)
 │    ├─ 签名归一化 + 去抖窗口(600s 内同一签名只发一次)
 │    └─► emit_incident.sh ──────────► incidents/inc-<date>-<seq>.json
 └─ check_resources.sh (可选) ───────► incidents/… (type=cpu|memory)
```

Incident 目录即"事件队列"：**Phase 3 的 AI worker（OpenClaw cron / Telegram / Webhook）只消费这里 `status=new` 的文件**。
去抖保证 agent 不会被同一异常刷爆；`count` 字段记录去抖窗口内的累计次数。

## 本地测试（无需 Java）

```bash
bash monitor/test/run_local_test.sh
```

## 服务器安装（Phase 2）

```bash
sudo mkdir -p /opt/aiops/monitor /var/log/aiops /var/lib/aiops/{state,incidents}
sudo cp -r monitor/. /opt/aiops/monitor/
sudo chown -R aiops:aiops /opt/aiops /var/log/aiops /var/lib/aiops
# 若资源告警开启:
sudo sed -i 's/^: "${AIOPS_WATCH_RESOURCES:=false}"/: "${AIOPS_WATCH_RESOURCES:=true}"/' \
  /opt/aiops/monitor/config.env
# 安装 timer (systemd 单元见 ../deploy/systemd/)
```

> 提示：状态目录里的 offset/签名/计数器会随运行增长（本仓库为学习规模设计），
> Phase 4 引入数据库后由 `incidents/reports` 表取代目录队列。
