#!/usr/bin/env bash
# ============================================================
# 乐乐代跑 部署脚本（在【本地电脑】运行，Windows 用 Git Bash）
#
# 用法：
#   bash deploy.sh        日常更新：上传代码 -> 装依赖(如有变化) -> 重启服务 -> 自检
#   bash deploy.sh init   首次部署：上述全部 + 安装 Node 24/PM2 + PM2 开机自启 + 放行端口
#
# 密码只输一次：通过 SSH ControlMaster 连接复用，第一条命令建立主连接后，
# 后续 scp/ssh 全部走同一条通道（若你的环境不支持复用，会退化为逐条询问，功能不受影响）
# ============================================================
set -e

SERVER_IP="47.91.25.15"
SSH_USER="root"
REMOTE_DIR="/opt/lele/server"
PORT="8899"
APP_NAME="lele"

MODE="${1:-update}"
if [ "$MODE" != "update" ] && [ "$MODE" != "init" ]; then
  echo "用法: bash deploy.sh [update|init]（默认 update）"
  exit 1
fi

cd "$(dirname "$0")"

# SSH 连接复用：主连接套件（Git Bash 的 OpenSSH 支持；不支持的环境自动退化为普通模式）
CM_DIR="$(mktemp -d)"
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$CM_DIR/ssh-%r@%h-%p" -o ControlPersist=yes -o ServerAliveInterval=30)

# 1. 建立主连接（唯一一次输密码）
echo "================ 乐乐代跑部署（$MODE） ================"
echo "目标 : ${SSH_USER}@${SERVER_IP}  目录: ${REMOTE_DIR}"
echo ">> 请输入服务器密码（仅一次；之后自动复用连接）"
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "mkdir -p ${REMOTE_DIR} && echo   连接建立"

# 2. 上传代码包（排除数据库/上传文件/日志——这些是服务器上的运行数据）
echo "== 上传服务端代码 =="
TMP_TGZ="$(mktemp -u).tgz"
tar czf "$TMP_TGZ" --exclude=node_modules --exclude='data.db' --exclude='data.db-wal' \
  --exclude='data.db-shm' --exclude=uploads --exclude='*.log' \
  src admin scripts config.json package.json package-lock.json
scp "${SSH_OPTS[@]}" "$TMP_TGZ" "${SSH_USER}@${SERVER_IP}:/tmp/lele-deploy.tgz"
rm -f "$TMP_TGZ"

# 3. 远端部署：解包 -> (init: 装环境/放行端口) -> 装依赖 -> 重启 -> 自检
echo "== 远端部署 =="
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "bash -s" <<REMOTE
set -e
DIR="$REMOTE_DIR"
PORT="$PORT"
APP="$APP_NAME"

tar xzf /tmp/lele-deploy.tgz -C "\$DIR"
rm -f /tmp/lele-deploy.tgz
echo "   代码已更新"

if [ "\$MODE" = "init" ]; then
  export DEBIAN_FRONTEND=noninteractive
  if ! command -v node >/dev/null 2>&1; then
    echo "   安装 Node.js 24（Ubuntu/Debian 适用）..."
    apt-get update -qq >/dev/null
    apt-get install -y -qq curl >/dev/null
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
    apt-get install -y -qq nodejs
  fi
  if ! command -v pm2 >/dev/null 2>&1; then
    npm install -g pm2 --silent
  fi
  if command -v ufw >/dev/null 2>&1; then ufw allow \$PORT/tcp >/dev/null 2>&1 || true; fi
fi

echo "   Node: \$(node -v) | 安装依赖..."
cd "\$DIR"
npm install --omit=dev --no-audit --no-fund >/dev/null 2>&1

if pm2 restart "\$APP" --update-env >/dev/null 2>&1; then
  echo "   服务已重启"
else
  pm2 start src/index.js --name "\$APP" >/dev/null
  pm2 save >/dev/null
  echo "   服务已启动（PM2 守护）"
  pm2 startup 2>/dev/null | tail -1 || true
fi

sleep 1
PING=\$(curl -s -m 5 "http://127.0.0.1:\$PORT/api/ping" || true)
if echo "\$PING" | grep -q '"ok":true'; then
  echo "   自检通过：服务正常响应"
else
  echo "   ⚠️ 自检未通过，请执行 pm2 logs $APP 查看日志"
fi
REMOTE

# 4. 关闭复用通道
ssh -O exit -o "ControlPath=$CM_DIR/ssh-%r@%h-%p" "${SSH_USER}@${SERVER_IP}" 2>/dev/null || true

echo ""
echo "=========================================="
echo " ✅ 部署完成（$MODE）"
echo "    接口检查 : http://${SERVER_IP}:${PORT}/api/ping"
echo "    管理后台 : http://${SERVER_IP}:${PORT}/admin"
echo "=========================================="
if [ "$MODE" = "init" ]; then
  echo " ⚠️ 阿里云安全组需在控制台放行 TCP ${PORT}（服务器本机防火墙已自动放行）"
fi
