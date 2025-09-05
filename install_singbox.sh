#!/bin/bash
set -e

SUBSCRIPTION_URL="https://10ncydlf.flsubcn.cc:2096/zvlqjih1t/mukeyvbugo4xzyjj?singbox=1&extend=1"
WEB_PORT=8081
SOCKS_PORT=1080
INSTALL_DIR="/opt/singbox"
SERVICE_NAME="singbox"
UPDATE_TIME="0 4 * * *"

# -----------------------------
# 检查端口 8081 占用并强制杀掉
# -----------------------------
OCCUPY_PID=$(ss -tlnp | grep ":$WEB_PORT" | awk '{print $7}' | cut -d',' -f2)
if [ -n "$OCCUPY_PID" ]; then
    echo "端口 $WEB_PORT 被占用，强制杀掉 PID $OCCUPY_PID..."
    sudo kill -9 $OCCUPY_PID
    sleep 1
fi

# -----------------------------
# 检查 SOCKS 端口是否被占用
# -----------------------------
while ss -tlnp | grep -q ":$SOCKS_PORT"; do
    echo "SOCKS 端口 $SOCKS_PORT 被占用，尝试下一个端口..."
    SOCKS_PORT=$((SOCKS_PORT + 1))
done
echo "使用 Web 面板端口: $WEB_PORT"
echo "使用 SOCKS5 端口: $SOCKS_PORT"

# -----------------------------
# 安装依赖
# -----------------------------
sudo apt update
sudo apt install -y curl wget socat iptables-persistent

# -----------------------------
# 创建安装目录
# -----------------------------
sudo mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# -----------------------------
# 下载 Sing-Box
# -----------------------------
SB_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | grep browser_download_url | grep linux | grep amd64 | cut -d '"' -f 4)
sudo wget -O $INSTALL_DIR/sing-box $SB_URL
sudo chmod +x $INSTALL_DIR/sing-box

# -----------------------------
# 生成配置文件
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
    },
    {
      "type": "socks",
      "tag": "socks",
      "listen": "127.0.0.1",
      "listen_port": $SOCKS_PORT
    }
  ],
  "outbounds": [
    {
      "type": "proxy",
      "tag": "proxy",
      "subscription_url": "$SUBSCRIPTION_URL"
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOL

# -----------------------------
# 配置 systemd
# -----------------------------
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
# 防火墙配置
# -----------------------------
if sudo ufw status | grep -q inactive; then
    sudo ufw --force enable
fi
sudo ufw allow 22/tcp
sudo ufw allow $WEB_PORT/tcp
sudo ufw allow $SOCKS_PORT/tcp

# -----------------------------
# Ubuntu 全局代理
# -----------------------------
grep -qxF "export http_proxy=socks5://127.0.0.1:$SOCKS_PORT" ~/.bashrc || \
    echo "export http_proxy=socks5://127.0.0.1:$SOCKS_PORT" >> ~/.bashrc
grep -qxF "export https_proxy=socks5://127.0.0.1:$SOCKS_PORT" ~/.bashrc || \
    echo "export https_proxy=socks5://127.0.0.1:$SOCKS_PORT" >> ~/.bashrc
grep -qxF "export all_proxy=socks5://127.0.0.1:$SOCKS_PORT" ~/.bashrc || \
    echo "export all_proxy=socks5://127.0.0.1:$SOCKS_PORT" >> ~/.bashrc

export http_proxy="socks5://127.0.0.1:$SOCKS_PORT"
export https_proxy="socks5://127.0.0.1:$SOCKS_PORT"
export all_proxy="socks5://127.0.0.1:$SOCKS_PORT"

# -----------------------------
# 定时更新订阅
# -----------------------------
CRON_CMD="cd $INSTALL_DIR && $INSTALL_DIR/sing-box -u"
(crontab -l 2>/dev/null; echo "$UPDATE_TIME $CRON_CMD") | crontab -

echo "========================================"
echo "部署完成！Web 面板端口: $WEB_PORT, SOCKS5: $SOCKS_PORT"
echo "Ubuntu 全局代理已生效"
echo "每天 4 点自动更新订阅"
echo "使用: sudo journalctl -u $SERVICE_NAME -f 查看日志"
echo "========================================"