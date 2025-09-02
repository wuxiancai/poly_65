#!/bin/bash
set -e

# 安装必要工具
apt update -y
apt install -y wget tar

# 下载 FRP 最新版 (amd64)
cd /usr/local
FRP_VER="0.61.0"
wget https://github.com/fatedier/frp/releases/download/v${FRP_VER}/frp_${FRP_VER}_linux_amd64.tar.gz
tar -xzf frp_${FRP_VER}_linux_amd64.tar.gz
mv frp_${FRP_VER}_linux_amd64 frp
cd frp

# 创建 frpc 配置文件
cat > /usr/local/frp/frpc.ini <<EOF
[common]
server_addr = 119.28.204.194
server_port = 7000

[web]
type = tcp
local_ip = 127.0.0.1
local_port = 8080
remote_port = 5000
EOF

# 创建 systemd 服务
cat > /etc/systemd/system/frpc.service <<EOF
[Unit]
Description=FRP Client Service
After=network.target

[Service]
ExecStart=/usr/local/frp/frpc -c /usr/local/frp/frpc.ini
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reexec
systemctl enable frpc
systemctl restart frpc

echo "==========================================="
echo "FRP 客户端部署完成！"
echo "现在可通过 http://119.28.204.194:5000 访问你家里的 127.0.0.1:8080"
echo "==========================================="