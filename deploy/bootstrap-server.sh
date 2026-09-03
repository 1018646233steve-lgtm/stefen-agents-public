#!/usr/bin/env bash
# bootstrap-server.sh —— Phase 0: 全新 Ubuntu 服务器一键初始化
# 用法(在服务器上以 root 或 sudo 执行):  sudo bash deploy/bootstrap-server.sh
# 可跳过部分步骤:  SKIP_UFW=1 SKIP_NODE=1 SKIP_JAVA=1 前缀执行
#
# 执行前请确认:
#   1) 已用 ssh-copy-id 配置好 SSH 密钥登录(本脚本不改 SSH 配置)
#   2) 服务器是 Ubuntu 22.04/24.04 (apt 系)
set -Eeuo pipefail

say() { printf '\n\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请以 root 运行: sudo bash $0"

# ---------- 1. 基础软件 ----------
say "1/7 安装基础软件: curl git jq ufw fail2ban ..."
apt-get update -y
apt-get install -y curl git jq ufw fail2ban ca-certificates gnupg apt-transport-https

# ---------- 2. 时区 ----------
say "2/7 设置时区为 UTC (日志时间统一)"
timedatectl set-timezone UTC || true

# ---------- 3. Node.js 20+ (Phase 3 跑 OpenClaw 用) ----------
if [ "${SKIP_NODE:-0}" != "1" ]; then
  say "3/7 安装 Node.js 20 LTS"
  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
  fi
  node -v && npm -v
else
  say "3/7 跳过 Node.js 安装 (SKIP_NODE=1)"
fi

# ---------- 4. JDK 21 + Maven (跑 demo-app) ----------
if [ "${SKIP_JAVA:-0}" != "1" ]; then
  say "4/7 安装 OpenJDK 21 + Maven"
  apt-get install -y openjdk-21-jdk maven
  java -version && mvn -version | head -n1
else
  say "4/7 跳过 JDK/Maven 安装 (SKIP_JAVA=1)"
fi

# ---------- 5. 运行用户与目录 ----------
say "5/7 创建 aiops 用户与目录"
if ! id aiops >/dev/null 2>&1; then
  useradd -m -s /bin/bash aiops
fi
mkdir -p /opt/aiops /var/log/aiops /var/lib/aiops/state /var/lib/aiops/incidents
chown -R aiops:aiops /opt/aiops /var/log/aiops /var/lib/aiops
echo "目录: /opt/aiops(代码) /var/log/aiops(app.log) /var/lib/aiops(state+incidents)"

# ---------- 6. 防火墙 ----------
if [ "${SKIP_UFW:-0}" != "1" ]; then
  say "6/7 配置 ufw: 仅放行 22/80/443"
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
  ufw status
else
  say "6/7 跳过 ufw (SKIP_UFW=1)"
fi

# ---------- 7. 收尾 ----------
say "7/7 初始化完成。接下来(以 aiops 用户执行):"
echo "  1) git clone 本仓库到 ~/aiops-lab"
echo "  2) cd aiops-lab/demo-app && mvn clean package"
echo "  3) 按 deploy/README.md 安装 systemd 单元(app + monitor timer)"
