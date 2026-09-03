# contracts/ —— 契约先行（本仓库最重要的部分）

## 为什么先定契约

官方 OpenClaw agent 与你的自研 agent 都只是这份契约的**实现者**：

```
监控平面 ──Incident(v1)──▶ [AI Worker: 官方 agent | 自研 agent] ──AnalysisReport(v1)──▶ 存储/UI
```

由此获得三项能力：

1. **可替换**：两个 worker 可以同时监听同一队列，报告 Schema 一致，前端无需感知"谁写的"。
2. **可评测**：把 20 个历史 Incident 分别喂给两个 agent，离线对比分析质量（结论正确率、证据真实性）。
3. **可演进**：契约版本化（v1→v2），破坏性变更显式升级，而不是悄悄改字段。

## 版本约定

- 版本号 = Schema 顶层 `schemaVersion` 字段（目前 `v1`）。
- 新增可选字段 → 不升版本；删除/改名/收紧必填 → 升版本并写迁移说明。
- 每个版本的 Schema 与示例都要保留（示例即黄金测试集）。

## 文件

| 文件 | 说明 |
|---|---|
| incident.schema.json | 事件 v1：监控平面 → 分析平面 |
| report.schema.json | 报告 v1：分析平面 → 存储/UI |
| examples/incident.example.json | 真实示例（日志异常事件） |
| examples/report.example.json | 官方 agent 应产出的报告示例（含证据链） |

## 校验（CI/本地都建议跑）

```bash
# 校验示例符合 Schema（需要 python3 与 jsonschema 库；或任选你顺手的工具）
python3 - <<'PY'
import json, jsonschema
for name, schema_name in [("incident.example.json","incident.schema.json"),
                          ("report.example.json","report.schema.json")]:
    schema = json.load(open(f"contracts/{schema_name}"))
    inst   = json.load(open(f"contracts/examples/{name}"))
    jsonschema.validate(inst, schema)
    print(f"OK {name} 符合 {schema_name}")
PY
```

> 若 `jsonschema` 未安装：`pip3 install jsonschema`。
> 没有 Python 也行 —— 至少保证示例字段名/枚举值与 Schema 一致，这是人工评审底线。
