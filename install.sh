#!/usr/bin/env bash
# mieru 个人自建一键脚本(单用户,仅供自己使用)
#
# 用法(在全新的 Debian / Ubuntu / CentOS / Rocky VPS 上,用 root 执行):
#   bash install.sh             安装并启动,最后打印客户端配置
#   bash install.sh --show      重新打印客户端配置
#   bash install.sh --uninstall 卸载 mita 并删除本脚本生成的文件
#
# 可选环境变量:
#   MITA_VERSION=3.38.1   指定版本(默认取 GitHub 最新版)
#   MIERU_PORT=23456      指定端口(默认在 11000-29901 里随机挑一个空闲的)
#
# 本脚本只做一件事:装官方 mita、配一个用户、打开 BBR、输出客户端配置。
# 不做多用户、不做面板、不做流量统计。
set -euo pipefail

FALLBACK_VERSION="3.38.1"
STATE_DIR="/etc/mieru-selfhost"
STATE_FILE="$STATE_DIR/state.env"
CLIENT_YAML="/root/mieru-client.yaml"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '==> %s\n' "$*"; }
die()   { red "错误:$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请用 root 运行(sudo -i 之后再执行)"

# ---------- 系统检测 ----------
detect_pkg() {
  if command -v dpkg >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then echo deb
  elif command -v rpm >/dev/null 2>&1; then echo rpm
  else die "只支持 Debian/Ubuntu(deb)或 CentOS/Rocky/Fedora(rpm)"; fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) die "不支持的 CPU 架构:$(uname -m)(只支持 amd64 / arm64)" ;;
  esac
}

latest_version() {
  local v
  v=$(curl -fsSL --max-time 15 https://api.github.com/repos/enfein/mieru/releases/latest 2>/dev/null \
      | grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9.]+)".*/\1/') || true
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$v" || echo "$FALLBACK_VERSION"
}

public_ip() {
  local ip
  for u in https://api.ipify.org https://ifconfig.me https://ipinfo.io/ip; do
    ip=$(curl -4 -fsS --max-time 8 "$u" 2>/dev/null | tr -d '[:space:]') || true
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { echo "$ip"; return; }
  done
  echo "你的服务器IP"
}

port_in_use() { ss -Htln "sport = :$1" 2>/dev/null | grep -q . ; }

pick_port() {
  local p i
  for i in $(seq 1 50); do
    p=$(( 11000 + RANDOM % 18902 ))
    port_in_use "$p" || { echo "$p"; return; }
  done
  die "找不到空闲端口,请用 MIERU_PORT=xxxxx 手动指定"
}

rand_str() { head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-"$1"; }

# ---------- 打印客户端配置 ----------
write_client_yaml() {
  # shellcheck disable=SC1090
  . "$STATE_FILE"
  umask 077
  cat >"$CLIENT_YAML" <<EOF
# mihomo(Clash Meta)客户端配置 —— 由 install.sh 生成
# 这个文件里有你的密码,别发给别人。
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: false

dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fake-ip-filter:
    - "+.lan"
    - "+.local"

proxies:
  - name: my-mieru
    type: mieru
    server: $SERVER_IP
    port: $PORT
    transport: TCP
    username: $USERNAME
    password: $PASSWORD
    multiplexing: MULTIPLEXING_LOW

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - my-mieru
      - DIRECT

rules:
  - GEOIP,LAN,DIRECT,no-resolve
  - GEOSITE,cn,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF
}

show_client() {
  [ -f "$STATE_FILE" ] || die "还没安装过(找不到 $STATE_FILE)"
  write_client_yaml
  # shellcheck disable=SC1090
  . "$STATE_FILE"
  echo
  green "================ 客户端需要填的内容 ================"
  echo "  协议      mieru"
  echo "  服务器    $SERVER_IP"
  echo "  端口      $PORT"
  echo "  传输      TCP"
  echo "  用户名    $USERNAME"
  echo "  密码      $PASSWORD"
  echo "  多路复用  低(MULTIPLEXING_LOW)"
  green "===================================================="
  echo
  echo "分享链接(小火箭 / Hiddify 可直接导入):"
  echo "  mierus://$USERNAME:$PASSWORD@$SERVER_IP?profile=my-mieru&port=$PORT&protocol=TCP&multiplexing=MULTIPLEXING_LOW#my-mieru"
  echo
  echo "完整的 Clash Meta(mihomo)配置已保存在:$CLIENT_YAML"
  echo "可以 cat 出来复制,或用 scp 下载到电脑上导入。"
  echo
}

# ---------- 卸载 ----------
uninstall() {
  # 只卸载本脚本装的;机器上别人装的 mita 不碰
  [ -f "$STATE_FILE" ] || die "找不到 $STATE_FILE,这台机器上的 mita 不是本脚本装的,不卸载"
  info "停止并卸载 mita"
  if command -v mita >/dev/null 2>&1; then mita stop >/dev/null 2>&1 || true; fi
  systemctl disable --now mita >/dev/null 2>&1 || true
  case "$(detect_pkg)" in
    deb) dpkg -P mita >/dev/null 2>&1 || true ;;
    rpm) rpm -e mita >/dev/null 2>&1 || true ;;
  esac
  if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
    if [ "${FW:-}" = ufw ]; then ufw delete allow "$PORT/tcp" >/dev/null 2>&1 || true; fi
    if [ "${FW:-}" = firewalld ]; then
      firewall-cmd --permanent --remove-port="$PORT/tcp" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
    fi
  fi
  # dpkg -P 不会删 mita 自己存的配置,不删的话重装后旧账号还能连
  rm -rf "$STATE_DIR" "$CLIENT_YAML" /etc/sysctl.d/99-mieru-bbr.conf /etc/mita
  green "已卸载。"
}

# ---------- 安装 ----------
install() {
  if [ -f "$STATE_FILE" ]; then
    info "检测到之前已经装过,直接打印配置(要重装请先 --uninstall)"
    show_client; exit 0
  fi
  # 机器上已有别的 mita 配置就不动它,免得把正在用的服务覆盖掉
  if command -v mita >/dev/null 2>&1 && mita describe config 2>/dev/null | grep -q '"users"'; then
    die "这台机器上已经有 mita 在用了(且不是本脚本装的)。为避免覆盖现有配置,脚本退出。"
  fi

  local pkg arch ver port user pass ip file url fw=none
  pkg=$(detect_pkg); arch=$(detect_arch)
  ver=${MITA_VERSION:-$(latest_version)}
  port=${MIERU_PORT:-$(pick_port)}
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1025 ] && [ "$port" -le 65535 ] || die "端口要在 1025-65535 之间"
  port_in_use "$port" && die "端口 $port 已被占用"

  info "安装 mita v$ver($pkg / $arch)"
  if [ "$pkg" = deb ]; then
    file="mita_${ver}_${arch}.deb"
  else
    [ "$arch" = amd64 ] && file="mita-${ver}-1.x86_64.rpm" || file="mita-${ver}-1.aarch64.rpm"
  fi
  url="https://github.com/enfein/mieru/releases/download/v${ver}/${file}"
  local tmp; tmp=$(mktemp -d)
  curl -fsSL --retry 3 -o "$tmp/$file" "$url" || die "下载失败:$url"
  if curl -fsSL --retry 3 -o "$tmp/$file.sha256.txt" "$url.sha256.txt"; then
    (cd "$tmp" && sha256sum -c "$file.sha256.txt" >/dev/null) || die "安装包校验失败,可能下载不完整,请重试"
  fi
  if [ "$pkg" = deb ]; then dpkg -i "$tmp/$file" >/dev/null; else rpm -Uvh --force "$tmp/$file" >/dev/null; fi
  rm -rf "$tmp"

  # 等守护进程起来
  for _ in $(seq 1 20); do mita status >/dev/null 2>&1 && break; sleep 1; done

  user="u$(rand_str 7)"; pass=$(rand_str 24)
  info "写入配置(端口 $port,单用户)"
  local cfg; cfg=$(mktemp)
  cat >"$cfg" <<EOF
{
  "portBindings": [ { "port": $port, "protocol": "TCP" } ],
  "users": [ { "name": "$user", "password": "$pass" } ],
  "loggingLevel": "INFO",
  "dns": { "dualStack": "PREFER_IPv4" }
}
EOF
  # replace 而不是 apply:apply 会把旧配置里的用户合并进来
  mita replace config "$cfg" >/dev/null || { rm -f "$cfg"; die "mita 拒绝了配置"; }
  rm -f "$cfg"
  mita start >/dev/null
  for _ in $(seq 1 10); do mita status 2>/dev/null | grep -q RUNNING && break; sleep 1; done
  mita status 2>/dev/null | grep -q RUNNING || die "mita 没能启动,看看 journalctl -u mita -n 50"

  info "开启 BBR"
  if modprobe tcp_bbr 2>/dev/null || grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' >/etc/sysctl.d/99-mieru-bbr.conf
    sysctl -p /etc/sysctl.d/99-mieru-bbr.conf >/dev/null 2>&1 || red "  BBR 写入失败(容器类 VPS 常见),不影响使用"
  else
    red "  内核不支持 BBR,跳过(不影响使用)"
  fi

  info "检查时间同步(服务器时间偏差超过 2 分钟会连不上)"
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-ntp true >/dev/null 2>&1 || true
    sleep 2
    if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ]; then
      echo "  时间已同步"
    else
      red "  时间同步未确认。装一下 chrony:apt install -y chrony 或 dnf install -y chrony"
    fi
  fi

  info "放行防火墙端口"
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "$port/tcp" >/dev/null && fw=ufw && echo "  ufw 已放行 $port/tcp"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$port/tcp" >/dev/null && firewall-cmd --reload >/dev/null && fw=firewalld \
      && echo "  firewalld 已放行 $port/tcp"
  else
    echo "  系统防火墙未启用,无需处理"
  fi
  echo "  ⚠️ 如果服务商控制台有「安全组 / 防火墙」(阿里云、AWS、Oracle 等),记得在那里也放行 TCP $port"

  ip=$(public_ip)
  mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
  umask 077
  cat >"$STATE_FILE" <<EOF
SERVER_IP=$ip
PORT=$port
USERNAME=$user
PASSWORD=$pass
FW=$fw
EOF
  green "安装完成,mita 正在运行。"
  show_client
}

case "${1:-}" in
  ""|--install) install ;;
  --show)       show_client ;;
  --uninstall)  uninstall ;;
  -h|--help)    sed -n '2,13p' "$0" ;;
  *) die "未知参数:$1(可用:--show / --uninstall / --help)" ;;
esac
