# deploy/ —— 服务器部署（Phase 0–2 落地）

## 0) 前置（Phase 0）

买海外 VPS 后，先手动完成（脚本不代劳，涉及安全底线）：

1. SSH 密钥登录：`ssh-copy-id user@host`，并在 `/etc/ssh/sshd_config` 设 `PasswordAuthentication no` 后 `systemctl restart ssh`
2. 域名 + A 记录（可选，后面 UI 会用到）

然后以 root 执行一键初始化：

```bash
sudo bash deploy/bootstrap-server.sh
```

## 1) 部署示例应用（Phase 1）

```bash
# 以 aiops 用户执行
cd ~/aiops-lab/demo-app
mvn clean package

sudo mkdir -p /opt/aiops/demo-app
sudo cp target/demo-app-0.0.1-SNAPSHOT.jar /opt/aiops/demo-app/demo-app.jar
sudo chown -R aiops:aiops /opt/aiops

# 安装 systemd 单元
sudo cp ../deploy/systemd/aiops-app.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now aiops-app

# 验收
curl -s localhost:8080/actuator/health            # → {"status":"UP"}
curl -s localhost:8080/api/boom                   # → 500
sleep 1 && tail -n 15 /var/log/aiops/app.log      # → 有异常栈
```

## 2) 安装监控 timer（Phase 2）

```bash
# 拷贝 monitor(保留执行权限)
sudo mkdir -p /opt/aiops/monitor
sudo cp -r monitor/. /opt/aiops/monitor/
sudo chmod +x /opt/aiops/monitor/*.sh /opt/aiops/monitor/lib/*.sh
sudo chown -R aiops:aiops /opt/aiops

# 开启资源告警(把 config.env 里的默认值改为 true)
sudo sed -i 's|^: "${AIOPS_WATCH_RESOURCES:=false}"|: "${AIOPS_WATCH_RESOURCES:=true}"|' \
  /opt/aiops/monitor/config.env

# 安装 timer
sudo cp deploy/systemd/aiops-monitor.service deploy/systemd/aiops-monitor.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now aiops-monitor.timer

# 验收 1: 手动触发一轮
sudo -u aiops bash /opt/aiops/monitor/run_once.sh --config   # 看配置
sudo -u aiops bash /opt/aiops/monitor/run_once.sh            # 跑一轮

# 验收 2: 制造故障 → 60 秒内出现 Incident
curl -s localhost:8080/api/boom
sleep 70
ls -la /var/lib/aiops/incidents/                 # → inc-YYYYMMDD-NNNN.json
jq . /var/lib/aiops/incidents/inc-*.json         # → 契约 v1 字段齐全
```

故障复测（验证去抖）：

```bash
curl -s localhost:8080/api/flaky; curl -s localhost:8080/api/flaky
sleep 70
ls -la /var/lib/aiops/incidents/   # 同一异常应只产生一个 Incident(count 累加)
```

## 3) 状态查询

```bash
journalctl -u aiops-monitor.service -n 20        # 每轮监控日志
systemctl list-timers aiops-monitor.timer        # 下次触发时间
```

## 目录约定

| 路径 | 内容 | 属主 |
|---|---|---|
| `/opt/aiops/demo-app/demo-app.jar` | 应用 jar | aiops |
| `/opt/aiops/monitor/` | 监控脚本 | aiops |
| `/var/log/aiops/app.log` | 应用日志（monitor 扫描对象） | aiops |
| `/var/lib/aiops/incidents/` | Incident 队列（Phase 3 agent 消费） | aiops |
| `/var/lib/aiops/state/` | offset/签名/计数器/metrics 快照 | aiops |

> Phase 3 之前，用 `journalctl`/`ls` 即可验证；Phase 3 起 AI worker 接管 incidents/ 目录。
