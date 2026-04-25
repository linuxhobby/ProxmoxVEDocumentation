#!/bin/bash

# ====================================================
# 将军阁下的专属 V2Ray 综合管理脚本 (Debian 12 核心加固版)
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 定义关键路径
V2RAY_BIN="/usr/local/bin/v2ray"
V2RAY_CONF_DIR="/usr/local/etc/v2ray"
CONFIG_FILE="$V2RAY_CONF_DIR/config.json"
CADDY_CONF_DIR="/etc/caddy"
CADDY_FILE="$CADDY_CONF_DIR/Caddyfile"

# 1. 环境肃清与准备
prepare_env() {
    echo -e "${YELLOW}正在清理环境并安装基础组件...${NC}"
    apt update && apt upgrade -y
    # 彻底移除可能占用的 Apache2 或 Nginx
    apt purge apache2* nginx* bind9* -y
    apt autoremove -y
    
    # 安装必要工具
    apt install -y curl wget jq uuid-runtime caddy vnstat unzip libcap2-bin
    
    # 强制创建目录
    mkdir -p $V2RAY_CONF_DIR
    mkdir -p $CADDY_CONF_DIR
    mkdir -p /var/www/html
    
    # 停止服务防止冲突
    systemctl stop v2ray caddy 2>/dev/null
}

# 2. 安装 V2Ray 核心 (手动部署，避开失效链接)
install_core() {
    echo -e "${GREEN}正在从 GitHub 官方抓取最新 V2Ray 核心...${NC}"
    local latest_version=$(curl -s https://api.github.com/repos/v2fly/v2ray-core/releases/latest | jq -r .tag_name)
    echo -e "${BLUE}检测到最新版本: $latest_version${NC}"
    
    wget -q -O /tmp/v2ray.zip "https://github.com/v2fly/v2ray-core/releases/download/${latest_version}/v2ray-linux-64.zip"
    
    if [[ ! -f /tmp/v2ray.zip ]]; then
        echo -e "${RED}错误：下载核心包失败，请检查网络！${NC}"
        exit 1
    fi
    
    unzip -o /tmp/v2ray.zip -d /tmp/v2ray_tmp
    cp /tmp/v2ray_tmp/v2ray /usr/local/bin/
    chmod +x /usr/local/bin/v2ray
    rm -rf /tmp/v2ray.zip /tmp/v2ray_tmp
    echo -e "${GREEN}V2Ray 核心安装成功。${NC}"
}

# 3. 写入配置并启动
write_config() {
    local domain=$1
    local uuid=$(uuidgen)
    local wspath="/$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 10)"

    # 写入 V2Ray 配置 (锁定 IPv4 内部回环)
    cat <<EOF > $CONFIG_FILE
{
  "inbounds": [{
    "port": 10000, "listen":"127.0.0.1", "protocol": "vless",
    "settings": { "clients": [{"id": "$uuid", "decryption": "none"}] },
    "streamSettings": { "network": "ws", "wsSettings": {"path": "$wspath"} }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

    # 写入 Caddyfile (强制 bind 0.0.0.0 实现双栈容错)
    cat <<EOF > $CADDY_FILE
$domain {
    bind 0.0.0.0
    reverse_proxy $wspath localhost:10000
    file_server { root /var/www/html }
}
EOF

    # 写入 Systemd 服务
    cat <<EOF > /etc/systemd/system/v2ray.service
[Unit]
Description=V2Ray Service
After=network.target
[Service]
User=root
ExecStart=/usr/local/bin/v2ray run -c $CONFIG_FILE
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

    # 授予 Caddy 绑定端口权限
    setcap 'cap_net_bind_service=+ep' $(which caddy)

    systemctl daemon-reload
    systemctl enable v2ray caddy
    systemctl restart v2ray caddy
    
    echo -e "\n${GREEN}========== 部署成功 ==========${NC}"
    echo -e "域名: ${BLUE}$domain${NC}"
    echo -e "UUID: ${BLUE}$uuid${NC}"
    echo -e "路径: ${BLUE}$wspath${NC}"
    echo -e "端口: ${BLUE}443${NC}"