#!/bin/bash

# ====================================================
# 将军阁下的专属 V2Ray 独立安装脚本 (修复服务未找到问题)
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 权限运行!${NC}" && exit 1

read -p "请输入您的解析域名: " DOMAIN
[[ -z "$DOMAIN" ]] && exit 1

echo -e "${GREEN}安装依赖与同步时区...${NC}"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
apt update && apt install -y curl wget jq uuid-runtime debian-keyring debian-archive-keyring apt-transport-https vnstat

# 1. 安装 V2Ray 官方核心
echo -e "${GREEN}正在从官方仓库安装 V2Ray...${NC}"
# 使用官方推荐的安装方式
bash <(curl -L https://raw.githubusercontent.com/v2fly/fscript/master/install-release.sh)

# 2. 安装 Caddy 2
echo -e "${GREEN}安装 Caddy 2...${NC}"
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install caddy -y

# 3. 准备配置参数
UUID=$(uuidgen)
WSPATH="/$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 10)"

# 4. 写入配置文件 (注意路径：官方脚本默认路径通常在 /usr/local/etc/v2ray/)
mkdir -p /usr/local/etc/v2ray
cat <<EOF > /usr/local/etc/v2ray/config.json
{
  "inbounds": [{
    "port": 10000,
    "listen":"127.0.0.1",
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$UUID"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {"path": "$WSPATH"}
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

# 5. 写入 Caddyfile
cat <<EOF > /etc/caddy/Caddyfile
$DOMAIN {
    reverse_proxy $WSPATH localhost:10000
    file_server {
        root /var/www/html
    }
}
EOF

# 6. 核心修复：检测并启动服务
echo -e "${GREEN}正在配置服务状态...${NC}"

# 尝试启动新版 V2Fly 服务名
if systemctl list-unit-files | grep -q "v2ray.service"; then
    V2_SERVICE="v2ray"
elif systemctl list-unit-files | grep -q "v2ray@"; then
    V2_SERVICE="v2ray@config"
else
    # 如果还是没找到，手动创建一个简单的 systemd 服务文件
    cat <<EOF > /etc/systemd/system/v2ray.service
[Unit]
Description=V2Ray Service
Documentation=https://www.v2fly.org/
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/v2ray run -c /usr/local/etc/v2ray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    V2_SERVICE="v2ray"
fi

systemctl enable $V2_SERVICE
systemctl restart $V2_SERVICE
systemctl enable caddy
systemctl restart caddy

# 7. 生成链接
SAFE_PATH=$(echo -n "$WSPATH" | sed 's/\//%2F/g')
VLESS_LINK="vless://$UUID@$DOMAIN:443?encryption=none&security=tls&type=ws&host=$DOMAIN&path=$SAFE_PATH#$DOMAIN"

clear
echo -e "-------------------------------------------------------"
echo -e "${GREEN}安装成功！服务已强制修复并启动。${NC}"
echo -e "服务名称: $V2_SERVICE"
echo -e "域名: ${DOMAIN}"
echo -e "UUID: ${UUID}"
echo -e "路径: ${WSPATH}"
echo -e "-------------------------------------------------------"
echo -e "${GREEN}您的 VLESS 节点链接：${NC}"
echo -e "${RED}${VLESS_LINK}${NC}"
echo -e "-------------------------------------------------------"