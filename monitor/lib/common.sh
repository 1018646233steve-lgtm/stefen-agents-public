#!/usr/bin/env bash
# aiops monitor 公共工具: 日志/目录/依赖检查。由各脚本 source。
# 注意: 兼容 macOS bash 3.2 与 Ubuntu bash 5.x, 勿用 ${var,,} 等 bash4+ 语法。

log_ts()   { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log_info() { echo "[$(log_ts)] INFO  $*"; }
log_warn() { echo "[$(log_ts)] WARN  $*" >&2; }
log_error(){ echo "[$(log_ts)] ERROR $*" >&2; }

ensure_dir() { mkdir -p "$1" || { log_error "无法创建目录: $1"; exit 1; }; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "缺少依赖命令: $1 (Ubuntu: apt install $1; macOS: brew install $1)"
    exit 1
  fi
}
