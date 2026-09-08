#!/usr/bin/env bash
# ============================================================
# 乐乐代跑 部署脚本（在【本地电脑】运行，Windows 用 Git Bash）
#
# 用法：
#   bash deploy.sh        日常更新：上传代码 -> 装依赖(如有变化) -> 重启服务
#   bash deploy.sh init   首次部署：上述全部 + 安装 Node 24/PM2 + PM2 开机自启 + 放行端口
#
# 只需输入【一次】服务器密码：代码包和远程命令合并走同一条 SSH 连接
# （本地先打 tar 包，远端脚本先按字节数收下 tar，再继续执行后续命令）
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

# 1. 本地打包（排除数据库/上传文件/日志——这些是服务器上的运行数据）
TMP_TGZ="$(mktemp -u).tgz"
tar czf "$TMP_TGZ" --exclude=node_modules --exclude='data.db' --exclude='data.db-wal' \
  --exclude='data.db-shm' --exclude=uploads --exclude='*.log' \
  src admin scripts config.json package.json package-lock.json
TARBYTES=$(wc -c < "$TMP_TGZ" | tr -d '[:space:]')

# 2. 远端脚本：先按字节数收下 tar 包，再按模式执行部署
read -r -d '' REMOTE_SCRIPT <<REMOTE
set -e
BYTES="$TARBYTES"
MODE="$MODE"
DIR="$REMOTE_DIR"
PORT="$PORT"
APP="$APP_NAME"

mkdir -p "\$DIR"
head -c "\$BYTES" > /tmp/lele-deploy.tgz
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

# 3. 单次 SSH：脚本 + tar 包合并通过 stdin 传输（只需输一次密码）
echo "================ 乐乐代跑部署（$MODE） ================"
echo "目标 : ${SSH_USER}@${SERVER_IP}  目录: ${REMOTE_DIR}"
echo ">> 请输入服务器密码（仅一次）"
{
  printf '%s\n' "$REMOTE_SCRIPT"
  cat "$TMP_TGZ"
} | ssh -o ServerAliveInterval=30 "${SSH_USER}@${SERVER_IP}" "bash -s -- $TARBYTES $MODE"

rm -f "$TMP_TGZ"

echo ""
echo "=========================================="
echo " ✅ 部署完成（$MODE）"
echo "    接口检查 : http://${SERVER_IP}:${PORT}/api/ping"
echo "    管理后台 : http://${SERVER_IP}:${PORT}/admin"
echo "=========================================="
if [ "$MODE" = "init" ]; then
  echo " ⚠️ 阿里云安全组需在控制台放行 TCP ${PORT}（服务器本机防火墙已自动放行）"
  echo " ⚠️ 上线前确认 config.json：dev_mode=false、jwt_secret 已改、admin.password 已改"
fi
