#!/bin/bash
set -e

# =========================
# 一键安装 Sing-Box + Yacd
# =========================

# 默认订阅链接（可修改）
SUB_URL="https://10ncydlf.flsubcn.cc:2096/zvlqjih1t/mukeyvbugo4xzyjj?singbox=1&extend=1"

# 安装依赖: Docker + Docker Compose
echo "==> 安装 Docker 与 Docker Compose..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
fi

if ! command -v docker-compose &> /dev/null; then
    sudo apt update
    sudo apt install -y docker-compose
fi

# 创建工作目录
CLASH_DIR="/root/clash"
mkdir -p "$CLASH_DIR"

# 下载初始订阅配置
echo "==> 拉取 Sing-Box 订阅配置..."
curl -L "$SUB_URL" -o "$CLASH_DIR/config.json"

# 确保 experimental 配置，Yacd 可用
if ! grep -q "experimental" "$CLASH_DIR/config.json"; then
    # 备份原配置
    cp "$CLASH_DIR/config.json" "$CLASH_DIR/config.json.bak"
    
    # 使用 jq 添加 experimental 配置
    if command -v jq &> /dev/null; then
        jq '. + {"experimental": {"clash_api": {"external_controller": "0.0.0.0:9090", "external_ui": "metacubexd", "external_ui_download_url": "https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip", "external_ui_download_detour": "select", "default_mode": "rule"}}}' "$CLASH_DIR/config.json.bak" > "$CLASH_DIR/config.json"
    else
        # 如果没有 jq，安装它
        sudo apt install -y jq
        jq '. + {"experimental": {"clash_api": {"external_controller": "0.0.0.0:9090", "external_ui": "metacubexd", "external_ui_download_url": "https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip", "external_ui_download_detour": "select", "default_mode": "rule"}}}' "$CLASH_DIR/config.json.bak" > "$CLASH_DIR/config.json"
    fi
fi

# 创建更新脚本
cat > "$CLASH_DIR/update.sh" <<'EOF'
#!/bin/bash
set -e
SUB_URL="https://10ncydlf.flsubcn.cc:2096/zvlqjih1t/mukeyvbugo4xzyjj?singbox=1&extend=1"
CONFIG_PATH="/root/clash/config.json"

echo "==> 更新 Sing-Box 订阅..."
curl -L "$SUB_URL" -o "$CONFIG_PATH"

# 确保 experimental 配置
if ! grep -q "experimental" "$CONFIG_PATH"; then
    # 备份原配置
    cp "$CONFIG_PATH" "$CONFIG_PATH.bak"
    
    # 使用 jq 添加 experimental 配置
    jq '. + {"experimental": {"clash_api": {"external_controller": "0.0.0.0:9090", "external_ui": "metacubexd", "external_ui_download_url": "https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip", "external_ui_download_detour": "select", "default_mode": "rule"}}}' "$CONFIG_PATH.bak" > "$CONFIG_PATH"
fi

# 重启 Sing-Box 容器
docker compose -f /root/clash/docker-compose.yml restart sing-box
EOF

chmod +x "$CLASH_DIR/update.sh"

# 创建 docker-compose.yml
cat > "$CLASH_DIR/docker-compose.yml" <<'EOF'
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sing-box
    restart: always
    volumes:
      - ./config.json:/etc/sing-box/config.json
    ports:
      - "7890:7890"   # HTTP/SOCKS5 代理端口
      - "9090:9090"   # API 控制端口
    command: sing-box run -c /etc/sing-box/config.json

  yacd:
    image: haishanh/yacd:latest
    container_name: yacd
    restart: always
    ports:
      - "8080:80"     # Web 控制台端口
EOF

# 启动服务
echo "==> 启动 Sing-Box + Yacd..."
cd "$CLASH_DIR"
docker compose up -d

# 创建 crontab 定时任务（每天 4 点更新订阅）
echo "==> 配置每日自动更新订阅..."
(crontab -l 2>/dev/null; echo "0 4 * * * $CLASH_DIR/update.sh >/dev/null 2>&1") | crontab -

echo "==========================================="
echo "Sing-Box + Yacd 安装完成！"
echo "HTTP/SOCKS5 代理端口: 7890"
echo "API 控制端口: 9090"
echo "Web 控制面板: http://<你的服务器IP>:8080"
echo "订阅自动每天 4 点更新"
echo "你可以执行 '$CLASH_DIR/update.sh' 手动更新订阅"
echo "==========================================="