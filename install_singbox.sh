#!/bin/bash
# 一键部署 Sing-Box 到 Ubuntu Server
# 自动选择端口、防火墙、订阅更新，无 tar.gz 解压问题

set -e

# -----------------------------
# 配置变量
# -----------------------------
SUBSCRIPTION_URL="https://10ncydlf.flsubcn.cc:2096/zvlqjih1t/mukeyvbugo4xzyjj?singbox=1&extend=1"
DEFAULT_PORT=8081
INSTALL_DIR="/opt/singbox"
SERVICE_NAME="singbox"
UPDATE_TIME="0 4 * * *"   # 每天 4:00 更新订阅

# -----------------------------
# 检查端口是否被占用并自动选择
# -----------------------------
WEB_PORT=$DEFAULT_PORT
while ss -tlnp | grep -q ":$WEB_PORT"; do
    echo "端口 $WEB_PORT 已被占用，尝试下一个端口..."
    WEB_PORT=$((WEB_PORT + 1))
done
echo "使用端口 $WEB_PORT 作为 Sing-Box Web 面板端口"

# -----------------------------
# 安装依赖
# -----------------------------
echo "安装依赖..."
sudo apt update
sudo apt install -y curl wget socat ufw

# -----------------------------
# 创建安装目录
# -----------------------------
sudo mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# -----------------------------
# 下载 Sing-Box 可执行文件（直接下载，无需解压）
# -----------------------------
echo "下载 Sing-Box 可执行文件..."
SB_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | grep browser_download_url | grep linux | grep amd64 | cut -d '"' -f 4)

sudo wget -O $INSTALL_DIR/sing-box $SB_URL
sudo chmod +x $INSTALL_DIR/sing-box

# -----------------------------
# 配置 Sing-Box 配置文件
# -----------------------------
CONFIG_FILE="$INSTALL_DIR/config.json"
cat | sudo tee $CONFIG_FILE <<EOL
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "http",
      "tag": "web",
      "listen": "0.0.0.0",
      "listen_port": $WEB_PORT
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "proxy",
      "tag": "proxy",
      "subscription_url": "$SUBSCRIPTION_URL"
    }
  ]
}
EOL

# -----------------------------
# 配置 systemd 服务
# -----------------------------
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
echo "配置 systemd 服务..."
sudo tee $SERVICE_FILE <<EOL
[Unit]
Description=Sing-Box Service
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/sing-box -c $CONFIG_FILE
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME

# -----------------------------
# 配置防火墙端口
# -----------------------------
echo "配置防火墙..."
if sudo ufw status | grep -q inactive; then
    sudo ufw --force enable
fi
sudo ufw allow $WEB_PORT/tcp

# -----------------------------
# 配置每天 4 点自动更新订阅
# -----------------------------
echo "配置每天 4 点自动更新订阅..."
CRON_CMD="cd $INSTALL_DIR && $INSTALL_DIR/sing-box -u"
(crontab -l 2>/dev/null; echo "$UPDATE_TIME $CRON_CMD") | crontab -

# -----------------------------
# 完成提示
# -----------------------------
echo "部署完成！"
echo "Sing-Box Web 面板端口: $WEB_PORT"
echo "每天 4 点自动更新订阅"
echo "防火墙端口已开放"
echo "使用命令查看日志: sudo journalctl -u $SERVICE_NAME -f"