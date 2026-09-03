---
name: collect-metrics
description: 读取最近一次指标快照,并在 demo-app 可访问时探测其 actuator health/metrics
---

当你需要"当前服务器/应用指标"作为分析依据时,执行:

```bash
bash {baseDir}/scripts/collect-metrics.sh
```

脚本行为:
1. 输出 `$AIOPS_STATE_DIR/metrics-latest.json`(monitor 最近一次采集的 CPU/内存/负载快照)的内容;
2. 若 `demo-app`(默认 http://127.0.0.1:8080)可访问,顺带输出 `/actuator/health` 与
   `/actuator/metrics/jvm.memory.used` 的当前值,用于判断"应用现在还活着吗 / 堆内存现在多高";
3. 应用不可访问时输出提示,不报错(事件发生时它可能已经崩了——这本身就是线索)。

使用要点:
- 事件 JSON 里已有事件发生时刻的 `metrics` 快照;本 skill 给你的是"现在"的指标,用于对比趋势(如内存是否持续上涨)。
- 输出是文本,引用到证据里时请保留原值并标注来源(metrics-latest.json 或 actuator 端点)。
