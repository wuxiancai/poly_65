#!/bin/bash
# 一键部署 Sing-Box 到 Ubuntu Server
# 智能选择 Web 面板端口（默认 8081），订阅自动更新，防火墙自动配置

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
sudo apt install -y curl wget unzip tar socat ufw

# -----------------------------
# 下载 Sing-Box
# -----------------------------
echo "下载 Sing-Box..."
sudo mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

SB_LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep browser_download_url | grep linux | grep amd64 | cut -d '"' -f 4)
wget -O sing-box.tar.gz $SB_LATEST
tar -xzf sing-box.tar.gz
chmod +x sing-box
rm sing-box.tar.gz

# -----------------------------
# 配置 Sing-Box 配置文件
# -----------------------------
CONFIG_FILE="$INSTALL_DIR/config.json"
cat > $CONFIG_FILE <<EOL
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
echo "配置 systemd 服务..."
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
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
    sudo ufw enable
fi
sudo ufw allow $WEB_PORT/tcp

# -----------------------------
# 配置每天 4 点自动更新订阅
# -----------------------------
echo "配置每天 4 点更新订阅..."
CRON_CMD="cd $INSTALL_DIR && $INSTALL_DIR/sing-box -u"
(crontab -l 2>/dev/null; echo "$UPDATE_TIME $CRON_CMD") | crontab -

echo "部署完成！Sing-Box Web 面板端口: $WEB_PORT"
echo "每天 4 点自动更新订阅"
echo "防火墙端口已开放，如果有其他防火墙，请额外配置"