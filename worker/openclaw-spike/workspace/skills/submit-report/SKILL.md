---
name: submit-report
description: 把契约 v1 的 AnalysisReport JSON 落盘到报告目录,并同步 Incident 状态流转
---

分析完成后,把报告 JSON 写入临时文件再交给脚本落盘:

```bash
# 1) 把构造好的报告写到 /tmp/report.json(务必先用 jq 校验必填字段齐全)
jq -e '.schemaVersion=="v1" and .reportId and .incidentId and .rootCause and (.evidence|length>=1) and (.fixSuggestions|length>=1)' /tmp/report.json >/dev/null || echo "报告不完整,请补齐后再提交"

# 2) 提交
bash {baseDir}/scripts/submit-report.sh /tmp/report.json
```

脚本行为:
1. 校验:reportId 以 `rpt-` 开头、incidentId 存在、`schemaVersion=="v1"`;不合法则拒绝并说明原因;
2. 写入 `$AIOPS_REPORTS_DIR/<incidentId>.report.json`(原子写:先写 .part 再 mv);
3. 把对应 Incident JSON 的 `status` 流转为 `analyzed`(领取时你已置为 `analyzing`,写回用 jq 原子替换);
4. 若设置了 `$AIOPS_REPORT_WEBHOOK`,会把报告 POST 到该地址(Phase 4 后端接入点,spike 阶段可留空);
5. 输出报告文件的绝对路径。

使用要点:
- 提交前**逐条核对证据**:evidence[].content 是否都能在你的 read 输出/脚本输出里找到原文。
- 若本次分析置信度低,允许提交,但 confidence 必须如实偏低并在 summary/openQuestions 里说明。
