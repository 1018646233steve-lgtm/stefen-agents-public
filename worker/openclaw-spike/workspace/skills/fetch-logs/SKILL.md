---
name: fetch-logs
description: 按 Incident 的日志首行时间戳,从应用日志拉取事件前后的原始日志上下文(限量)
---

当 Incident 的 `logExcerpt` 不够、需要看事件发生前后的完整日志时执行:

```bash
bash {baseDir}/scripts/fetch-logs.sh <incident.json 路径> [before行数] [after行数]
```

- `<incident.json 路径>`:必填。脚本自动从 Incident 的 `logExcerpt` 首行提取时间戳,并在
  `$AIOPS_APP_LOG` 中找到该行,打印它**之前 before(默认 40)行、之后 after(默认 80)行**的真实日志。
- 找不到对应行时(如日志已轮转),回退输出该文件最后 200 行并明确提示"未找到精确位置,以下为文件尾部"。

使用要点:
- **限量是纪律**:默认 120 行足够定位绝大多数问题,不要无脑拉整个文件;确需更多时再加大 after。
- 引用进 `evidence[]` 时必须保留日志原文与时间戳,`location` 写"<app.log> <该行时间戳> 前后 N 行"。
- 如果摘录首行时间戳与当前日志时间区不一致(如 UTC vs +08:00),以脚本输出为准——它直接在文件里找匹配行。
