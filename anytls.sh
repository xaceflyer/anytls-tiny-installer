#!/usr/bin/env bash
# anytls.sh - Tiny VPS friendly AnyTLS installer
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/anytls.sh)
# Optional env:
#   VERSION=0.0.11 PORT=31918 PASSWORD='your_password' bash <(curl -fsSL ...)
#
# Designed for very small NAT VPS/container environments. No jq/python required.

set -u

VERSION="${VERSION:-0.0.11}"
DEFAULT_PORT="${PORT:-31918}"
PASSWORD="${PASSWORD:-}"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="anytls"
LOG_FILE="/root/anytls.log"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
die() { red "[ERROR] $*"; exit 1; }

need_root() {
  [ "$(id -u)" = "0" ] || die "请使用 root 用户运行。"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armhf) echo "armv7" ;;
    *) die "暂不支持的架构：$(uname -m)" ;;
  esac
}

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
  else
    OS_ID="unknown"
  fi
  echo "$OS_ID"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_deps() {
  # Only install what is missing. Avoid jq/python to save memory.
  missing=""
  has_cmd curl || missing="$missing curl"
  has_cmd unzip || missing="$missing unzip"
  has_cmd update-ca-certificates || missing="$missing ca-certificates"

  if [ -z "$missing" ]; then
    info "依赖已满足：curl / unzip / ca-certificates"
    return 0
  fi

  OS_ID="$(detect_os)"
  yellow "缺少依赖：$missing"
  yellow "准备安装最小依赖。低内存小鸡如遇 Killed，通常是内存/OOM，不是脚本语法错误。"

  if has_cmd apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get clean || true
    apt-get update || die "apt-get update 失败"
    apt-get install -y --no-install-recommends $missing || die "依赖安装失败。若出现 Killed，请先检查内存/swap，或手动预装 curl unzip ca-certificates。"
  elif has_cmd apk; then
    apk add --no-cache $missing || die "apk 安装依赖失败"
  elif has_cmd yum; then
    yum install -y $missing || die "yum 安装依赖失败"
  elif has_cmd dnf; then
    dnf install -y $missing || die "dnf 安装依赖失败"
  else
    die "未识别包管理器，请先手动安装：curl unzip ca-certificates"
  fi
}

ask_config() {
  if [ -t 0 ] || [ -r /dev/tty ]; then
    printf "请输入 AnyTLS 内部监听端口 [%s]: " "$DEFAULT_PORT" > /dev/tty
    read -r input_port < /dev/tty || input_port=""
    PORT="${input_port:-$DEFAULT_PORT}"

    if [ -z "$PASSWORD" ]; then
      printf "请输入 AnyTLS 密码，留空则自动生成: " > /dev/tty
      read -r input_pass < /dev/tty || input_pass=""
      PASSWORD="$input_pass"
    fi
  else
    PORT="$DEFAULT_PORT"
  fi

  case "$PORT" in
    ''|*[!0-9]*) die "端口必须是数字。" ;;
  esac
  [ "$PORT" -ge 1 ] 2>/dev/null && [ "$PORT" -le 65535 ] 2>/dev/null || die "端口范围必须是 1-65535。"

  if [ -z "$PASSWORD" ]; then
    if has_cmd base64; then
      PASSWORD="$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -dc 'A-Za-z0-9' | cut -c1-24)"
    fi
    [ -n "$PASSWORD" ] || PASSWORD="AnyTLS_$(date +%s)_$RANDOM"
  fi
}

download_anytls() {
  ARCH="$(detect_arch)"
  ASSET="anytls_${VERSION}_linux_${ARCH}.zip"
  URL="https://github.com/anytls/anytls-go/releases/download/v${VERSION}/${ASSET}"
  TMP_DIR="/tmp/anytls-install.$$"

  mkdir -p "$TMP_DIR" || die "无法创建临时目录"
  cd "$TMP_DIR" || die "无法进入临时目录"

  info "下载 AnyTLS-Go v${VERSION} (${ARCH})"
  info "$URL"
  curl -L --fail --retry 3 -o anytls.zip "$URL" || die "下载失败。请检查版本号、架构、网络或 GitHub 访问。"

  unzip -o anytls.zip >/dev/null || die "解压失败"

  [ -f anytls-server ] || die "压缩包内没有 anytls-server"
  [ -f anytls-client ] || die "压缩包内没有 anytls-client"

  install -m 755 anytls-server "${INSTALL_DIR}/anytls-server" || die "安装 anytls-server 失败"
  install -m 755 anytls-client "${INSTALL_DIR}/anytls-client" || die "安装 anytls-client 失败"

  cd / || true
  rm -rf "$TMP_DIR"
  green "AnyTLS 二进制安装完成：${INSTALL_DIR}/anytls-server"
}

stop_old_process() {
  if pgrep -f "anytls-server" >/dev/null 2>&1; then
    yellow "发现已有 anytls-server 进程，准备停止。"
    pkill -f "anytls-server" || true
    sleep 1
  fi
}

pid1_is_systemd() {
  [ "$(ps -p 1 -o comm= 2>/dev/null | tr -d ' ')" = "systemd" ]
}

setup_systemd() {
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=AnyTLS Server
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/anytls-server -l 0.0.0.0:${PORT} -p ${PASSWORD}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  chmod 600 "/etc/systemd/system/${SERVICE_NAME}.service" || true
  systemctl daemon-reload || die "systemctl daemon-reload 失败"
  systemctl enable "${SERVICE_NAME}" || die "systemctl enable 失败"
  systemctl restart "${SERVICE_NAME}" || die "systemctl restart 失败"
  green "systemd 服务已启用：${SERVICE_NAME}.service"
}

setup_openrc() {
  cat > "/etc/init.d/${SERVICE_NAME}" <<EOF
#!/sbin/openrc-run
name="AnyTLS Server"
description="AnyTLS Server"
command="${INSTALL_DIR}/anytls-server"
command_args="-l 0.0.0.0:${PORT} -p ${PASSWORD}"
command_background="yes"
pidfile="/run/${SERVICE_NAME}.pid"
output_log="${LOG_FILE}"
error_log="${LOG_FILE}"
EOF

  chmod +x "/etc/init.d/${SERVICE_NAME}" || die "OpenRC 脚本授权失败"
  rc-update add "${SERVICE_NAME}" default || die "rc-update 失败"
  rc-service "${SERVICE_NAME}" restart || die "rc-service restart 失败"
  green "OpenRC 服务已启用：${SERVICE_NAME}"
}

setup_nohup_only() {
  yellow "未检测到 systemd/OpenRC，改用 nohup 临时启动；这种方式不保证重启后自启。"
  nohup "${INSTALL_DIR}/anytls-server" -l "0.0.0.0:${PORT}" -p "${PASSWORD}" >"${LOG_FILE}" 2>&1 &
  sleep 1
}

start_service() {
  stop_old_process

  if has_cmd systemctl && pid1_is_systemd; then
    setup_systemd
  elif has_cmd rc-service && has_cmd rc-update && [ -d /etc/init.d ]; then
    setup_openrc
  else
    setup_nohup_only
  fi
}

check_status() {
  sleep 1
  if pgrep -f "anytls-server" >/dev/null 2>&1; then
    green "AnyTLS 进程正在运行。"
  else
    red "AnyTLS 似乎没有运行。日志如下："
    [ -f "$LOG_FILE" ] && tail -n 50 "$LOG_FILE"
    exit 1
  fi

  if has_cmd ss; then
    ss -lntp 2>/dev/null | grep ":${PORT}" || true
  elif has_cmd netstat; then
    netstat -lntp 2>/dev/null | grep ":${PORT}" || true
  fi
}

urlencode() {
  # Percent-encode a string for URL userinfo/query usage.
  # Uses only POSIX shell + od; no python/jq dependency.
  old_lc_all="${LC_ALL:-}"
  LC_ALL=C
  input="$1"
  output=""
  i=1
  while [ "$i" -le "${#input}" ]; do
    c="$(printf '%s' "$input" | cut -c "$i")"
    case "$c" in
      [a-zA-Z0-9.~_-]) output="${output}${c}" ;;
      *) hex="$(printf '%s' "$c" | od -An -tx1 | tr -d ' \n' | tr 'abcdef' 'ABCDEF')"; output="${output}%${hex}" ;;
    esac
    i=$((i + 1))
  done
  LC_ALL="$old_lc_all"
  printf '%s' "$output"
}

print_result() {
  IP="$(curl -fsS --max-time 5 https://ip.sb 2>/dev/null || curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo '你的服务器IP或域名')"
  EXTERNAL_PORT="${EXTERNAL_PORT:-$PORT}"
  ENCODED_PASSWORD="$(urlencode "$PASSWORD")"
  NEKOBOX_URI="anytls://${ENCODED_PASSWORD}@${IP}:${EXTERNAL_PORT}/?insecure=1"

  cat <<EOF

================ AnyTLS 安装完成 ================

服务端监听：
  0.0.0.0:${PORT} / TCP

客户端填写：
  地址：${IP}
  端口：请填写 NAT 面板上的【外部 TCP 端口】
  密码：${PASSWORD}
  协议：AnyTLS

NekoBox / sing-box 类客户端分享链接：
  ${NEKOBOX_URI}

重要提醒：
  1. AnyTLS-Go 当前服务端监听的是 TCP，不是 UDP。
  2. NAT 小鸡面板里必须添加 TCP 转发规则。
     例如：TCP 外部端口 ${PORT} -> 内部端口 ${PORT}
  3. 如果面板给的是“外部端口 31922 -> 内部端口 ${PORT}”，
     客户端端口要填 31922，而不是 ${PORT}。
     这种情况下可这样安装，让输出的分享链接直接使用外部端口：
     EXTERNAL_PORT=31922 PORT=${PORT} PASSWORD='你的密码' bash <(curl -fsSL 你的脚本raw地址)
  4. 如果你的客户端不接受 insecure=1，请手动在客户端里开启“允许不安全 / 跳过证书验证”。
  5. 这类超小内存机器不建议反复 apt upgrade。

常用命令：
  查看状态：systemctl status anytls --no-pager
  重启服务：systemctl restart anytls
  查看端口：ss -lntp | grep ${PORT}
  查看日志：journalctl -u anytls --no-pager -n 50

==================================================

EOF
}

uninstall_anytls() {
  yellow "准备卸载 AnyTLS。"
  if has_cmd systemctl; then
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload 2>/dev/null || true
  fi
  if has_cmd rc-service; then
    rc-service "${SERVICE_NAME}" stop 2>/dev/null || true
    rc-update del "${SERVICE_NAME}" default 2>/dev/null || true
    rm -f "/etc/init.d/${SERVICE_NAME}"
  fi
  pkill -f "anytls-server" 2>/dev/null || true
  rm -f "${INSTALL_DIR}/anytls-server" "${INSTALL_DIR}/anytls-client"
  green "卸载完成。"
}

main() {
  case "${1:-install}" in
    install)
      need_root
      ask_config
      install_deps
      download_anytls
      start_service
      check_status
      print_result
      ;;
    uninstall)
      need_root
      uninstall_anytls
      ;;
    status)
      check_status
      ;;
    *)
      cat <<EOF
用法：
  $0 install      安装 AnyTLS
  $0 uninstall    卸载 AnyTLS
  $0 status       查看运行状态

环境变量示例：
  VERSION=0.0.11 PORT=31918 PASSWORD='your_password' bash $0 install
EOF
      ;;
  esac
}

main "$@"
