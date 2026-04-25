#!/bin/bash

# ====================================================
# 将军阁下的专属 V2Ray (VLESS+WS+TLS) 独立安装脚本
# 支持系统：Debian 11+, Ubuntu 20.04+
# 功能：自动核心安装、Caddy证书配置、生成分享链接
# ====================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 1. 环境检查
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 权限运行!${NC}" && exit 1

# 2. 交互输入
read -p "请输入您的解析域名 (例如: cc.myvpsworld.top): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}域名不能为空!${NC}"
    exit 1
fi

# 3. 安装基础依赖
echo -e "${GREEN}正在同步系统时区并安装基础依赖...${NC}"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
apt update
apt install -y curl wget jq uuid-runtime debian-keyring debian-archive-keyring apt-transport-https vnstat

# 4. 安装 V2Ray 官方核心 (V2Fly)
echo -e "${GREEN}正在从官方仓库安装 V2Ray 核心...${NC}"
bash <(curl -L https://raw.githubusercontent.com/v2fly/fscript/master/install-release.sh)

# 5. 安装 Caddy 2 (自动处理 TLS 证书)
echo -e "${GREEN}正在安装 Caddy 2 负责反向代理与证书申请...${NC}"
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install caddy -y

# 6. 生成配置参数
UUID=$(uuidgen)
# 随机生成一个路径，例如 /v2ray-abc123
WSPATH="/$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 10)"

# 7. 写入 V2Ray 配置文件
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

# 8. 写入 Caddyfile (自动化证书与反向代理)
cat <<EOF > /etc/caddy/Caddyfile
$DOMAIN {
    reverse_proxy $WSPATH localhost:10000
    file_server {
        root /var/www/html
    }
}
EOF

# 9. 重启并设置开机自启
echo -e "${GREEN}正在启动服务并设置自启动...${NC}"
systemctl restart v2ray
systemctl enable v2ray
systemctl restart caddy
systemctl enable caddy

# 10. 生成 VLESS 分享链接
# 将路径中的 / 编码为 %2F 确保链接兼容性
SAFE_PATH=$(echo -n "$WSPATH" | sed 's/\//%2F/g')
VLESS_LINK="vless://$UUID@$DOMAIN:443?encryption=none&security=tls&type=ws&host=$DOMAIN&path=$SAFE_PATH#$DOMAIN-vless"

# 11. 最终结果展示
clear
echo -e "-------------------------------------------------------"
echo -e "${GREEN}安装成功！将军阁下，您的专属配置已就绪：${NC}"
echo -e "-------------------------------------------------------"
echo -e "域名: ${DOMAIN}"
echo -e "端口: 443"
echo -e "UUID: ${UUID}"
echo -e "路径: ${WSPATH}"
echo -e "协议: VLESS + WS + TLS"
echo -e "流量统计: 已开启 (使用 vnstat 查看)"
echo -e "-------------------------------------------------------"
echo -e "${GREEN}您的 VLESS 节点链接：${NC}"
echo -e "${RED}${VLESS_LINK}${NC}"
echo -e "-------------------------------------------------------"
echo -e "注意：请确保域名的 A 记录已正确指向本服务器 IP。"
echo -e "Caddy 会在首次连接时自动为您申请 SSL 证书。"