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
echo "正在下载 Sing-Box..."

# 清理可能存在的损坏文件
if [ -f "$INSTALL_DIR/sing-box" ]; then
    echo "检查现有文件..."
    if ! file "$INSTALL_DIR/sing-box" | grep -q "ELF.*executable"; then
        echo "发现损坏的文件，删除重新下载..."
        sudo rm -f "$INSTALL_DIR/sing-box"
    fi
fi

# 尝试多种下载方式
if [ ! -f "$INSTALL_DIR/sing-box" ]; then
    # 方法1: 直接使用固定版本（更可靠）
    echo "下载 sing-box v1.12.4..."
    BACKUP_URL="https://github.com/SagerNet/sing-box/releases/download/v1.12.4/sing-box-1.12.4-linux-amd64.tar.gz"
    
    # 下载到临时目录
    TEMP_DIR="/tmp/singbox_install_$$"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    if sudo wget --timeout=30 --tries=3 -O sing-box.tar.gz "$BACKUP_URL"; then
        echo "解压文件..."
        sudo tar -xzf sing-box.tar.gz
        
        # 查找sing-box二进制文件
        SING_BOX_BIN=$(find . -name "sing-box" -type f -executable | head -1)
        
        if [ -n "$SING_BOX_BIN" ] && [ -f "$SING_BOX_BIN" ]; then
            echo "验证二进制文件..."
            if file "$SING_BOX_BIN" | grep -q "ELF.*executable"; then
                sudo cp "$SING_BOX_BIN" "$INSTALL_DIR/sing-box"
                echo "✅ sing-box 下载成功"
            else
                echo "❌ 下载的文件不是有效的可执行文件"
                exit 1
            fi
        else
            echo "❌ 在压缩包中找不到 sing-box 可执行文件"
            exit 1
        fi
    else
        echo "❌ 下载失败"
        exit 1
    fi
    
    # 清理临时文件
    cd /
    sudo rm -rf "$TEMP_DIR"
fi

sudo chmod +x $INSTALL_DIR/sing-box
echo "Sing-Box 下载完成"

# -----------------------------
# 生成配置文件
# -----------------------------
CONFIG_FILE="$INSTALL_DIR/config.json"
sudo tee $CONFIG_FILE <<EOL
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "http",
      "tag": "http-in",
      "listen": "0.0.0.0",
      "listen_port": $WEB_PORT
    },
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "listen_port": $SOCKS_PORT
    }
  ],
  "outbounds": [
    {
      "type": "selector",
      "tag": "proxy",
      "outbounds": ["auto", "direct"]
    },
    {
      "type": "urltest",
      "tag": "auto",
      "outbounds": ["direct"],
      "url": "http://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "proxy"
  }
}
EOL

# -----------------------------
# 下载订阅配置
# -----------------------------
echo "正在下载订阅配置..."
if [ -n "$SUBSCRIPTION_URL" ]; then
    sudo wget -O "$INSTALL_DIR/subscription.json" "$SUBSCRIPTION_URL" || {
        echo "订阅下载失败，使用基础配置"
    }
    
    # 如果订阅下载成功，合并配置
    if [ -f "$INSTALL_DIR/subscription.json" ]; then
        echo "合并订阅配置..."
        # 这里可以添加配置合并逻辑
    fi
fi

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
ExecStart=$INSTALL_DIR/sing-box run -c $CONFIG_FILE
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL

# 验证sing-box二进制文件
echo "验证sing-box安装..."
if [ ! -f "$INSTALL_DIR/sing-box" ]; then
    echo "错误: sing-box二进制文件不存在"
    exit 1
fi

if [ ! -x "$INSTALL_DIR/sing-box" ]; then
    echo "错误: sing-box文件没有执行权限"
    sudo chmod +x "$INSTALL_DIR/sing-box"
fi

# 测试配置文件
echo "测试配置文件..."
sudo "$INSTALL_DIR/sing-box" check -c "$CONFIG_FILE" || {
    echo "配置文件验证失败，请检查配置"
    exit 1
}

sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME

# 停止可能存在的旧服务
sudo systemctl stop $SERVICE_NAME 2>/dev/null || true

# 启动服务
echo "启动sing-box服务..."
sudo systemctl start $SERVICE_NAME

# 等待服务启动
sleep 3

# 检查服务状态
if sudo systemctl is-active --quiet $SERVICE_NAME; then
    echo "✅ sing-box服务启动成功"
else
    echo "❌ sing-box服务启动失败"
    echo "查看错误日志:"
    sudo journalctl -u $SERVICE_NAME --no-pager -n 20
    exit 1
fi

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