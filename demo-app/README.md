# demo-app —— 最小 Spring Boot 3 示例应用（故障注入 + actuator）

本应用不是"拿来监控的真实项目"，而是**给你制造故障、训练 Agent 的靶场**：

| 接口 | 行为 | 用途 |
|---|---|---|
| `GET /api/ping` | 返回 pong | 健康检查 |
| `GET /api/boom` | **100%** 抛 IllegalStateException | 确定性异常 → 验证监控/Agent 一定能抓到 |
| `GET /api/flaky` | **约 40%** 抛 NPE | 间歇性异常 → 验证去抖/聚合/上下文裁剪 |
| `GET /api/leak` | 每次 +1MB（封顶 64MB，可 `/api/leak-reset` 释放） | 制造内存增长 → 验证 oom/内存类分析 |
| `GET /api/cpu?seconds=10` | 忙等 N 秒 | 制造 CPU 尖峰 → 触发 type=cpu 资源告警 |
| `GET /api/mem` | 返回 JVM 堆内存快照 | Agent 取证工具可调用 |
| `GET /actuator/health` | UP/DOWN | Agent 取证工具可调用 |
| `GET /actuator/metrics/jvm.memory.used` 等 | 指标 | Agent 取证工具可调用（需要时用 `/actuator/prometheus`） |

## 本地运行（需要 JDK 21+ 与 Maven）

```bash
mvn spring-boot:run
# 日志写到 demo-app/logs/app.log(启动路径下; 若在 aiops-lab 根目录外运行请设 APP_LOG)

# 制造几次故障:
curl -s http://localhost:8080/api/ping
curl -s http://localhost:8080/api/flaky; echo     # 40% 概率报错, 可多打几次
curl -s http://localhost:8080/api/boom;  echo     # 必报错

# 验证日志里有异常栈:
tail -n 20 logs/app.log
```

## 服务器部署（Phase 1）

见 [`../deploy/README.md`](../deploy/README.md)：`mvn clean package` → 拷贝 jar →
安装 `deploy/systemd/aiops-app.service`（systemd 会注入 `APP_LOG=/var/log/aiops/app.log`）。

## 给 Agent 取证用的端点小结（Phase 3 skill 会用到）

- `curl -s localhost:8080/actuator/health`
- `curl -s localhost:8080/actuator/metrics/jvm.memory.used`
- `curl -s localhost:8080/api/mem`
- `curl -s localhost:8080/api/ping`
- 日志文件本身（monitor 侧已按 Incident 摘录，需要更多上下文时用 skill 拉取）
