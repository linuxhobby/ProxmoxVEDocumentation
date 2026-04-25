#!/bin/bash

# ====================================================
# 将军阁下的专属 V2Ray 综合管理脚本 (解析检测+返回菜单版)
# https://raw.githubusercontent.com/linuxhobby/ProxmoxVE/refs/heads/main/v2ray/test.sh
# curl -sL https://raw.githubusercontent.com/linuxhobby/ProxmoxVE/refs/heads/main/v2ray/test.sh -o test.sh && chmod +x test.sh && ./test.sh
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_FILE="/usr/local/etc/v2ray/config.json"
CADDY_FILE="/etc/caddy/Caddyfile"

[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 权限运行!${NC}" && exit 1

# --- 内部功能函数 ---

# 生成分享链接并显示
generate_output() {
    local uuid=$1
    local domain=$2
    local path=$3
    local proto=$4
    local safe_path=$(echo -n "$path" | sed 's/\//%2F/g')

    if [[ "$proto" == "vless" ]]; then
        URL="vless://$uuid@$domain:443?encryption=none&security=tls&type=ws&host=$domain&path=$safe_path#vpn-ws-$domain"
    else
        VMESS_JSON=$(cat <<EOF
{ "v": "2", "ps": "vpn-ws-$domain", "add": "$domain", "port": "443", "id": "$uuid", "aid": "0", "net": "ws", "type": "none", "host": "$domain", "path": "$path", "tls": "tls" }
EOF
        )
        URL="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)#$domain"
    fi

    echo -e "-------------------------------------------------------"
    echo -e "协议 (protocol) \t= ${BLUE}${proto}${NC}"
    echo -e "地址 (address) \t\t= ${BLUE}${domain}${NC}"
    echo -e "端口 (port) \t\t= ${BLUE}443${NC}"
    echo -e "用户ID (id) \t\t= ${BLUE}${uuid}${NC}"
    echo -e "传输协议 (network) \t= ${BLUE}ws${NC}"
    echo -e "伪装域名 (host) \t= ${BLUE}${domain}${NC}"
    echo -e "路径 (path) \t\t= ${BLUE}${path}${NC}"
    echo -e "传输层安全 (TLS) \t= ${BLUE}tls${NC}"
    echo -e "------------- 链接 (URL) -------------"
    echo -e "${RED}${URL}${NC}"
    echo -e "-------------------------------------------------------"
}

# 域名解析检测函数
check_dns() {
    local domain=$1
    echo -e "${YELLOW}正在检测域名解析状态...${NC}"
    
    # 获取本地公网IP
    local local_ipv4=$(curl -s4 https://api64.ipify.org || echo "未检测到")
    local local_ipv6=$(curl -s6 https://api64.ipify.org || echo "未检测到")
    
    # 使用 dig 或 nslookup 获取域名解析 (需安装 dnsutils)
    apt install -y dnsutils > /dev/null 2>&1
    local resolved_ipv4=$(dig +short A "$domain" | tail -n1)
    local resolved_ipv6=$(dig +short AAAA "$domain" | tail -n1)

    echo -e "本机公网 IPv4: ${BLUE}$local_ipv4${NC}"
    echo -e "本机公网 IPv6: ${BLUE}$local_ipv6${NC}"
    echo -e "域名解析 IPv4: ${BLUE}${resolved_ipv4:-未检测到}${NC}"
    echo -e "域名解析 IPv6: ${BLUE}${resolved_ipv6:-未检测到}${NC}"

    if [[ -z "$resolved_ipv4" && -z "$resolved_ipv6" ]]; then
        echo -e "${RED}警告：未检测到任何解析记录，证书申请极大概率失败！${NC}"
    elif [[ -n "$resolved_ipv4" && "$resolved_ipv4" != "$local_ipv4" ]]; then
        echo -e "${YELLOW}警告：域名 IPv4 解析与本机不匹配！${NC}"
    fi

    read -p "确认信息无误并继续？(y/n, 默认y): " check_confirm
    [[ "${check_confirm,,}" == "n" ]] && return 1
    return 0
}

# --- 核心菜单功能 ---

# 1. 安装功能
install_v2ray() {
    while true; do
        echo -e "${YELLOW}请选择协议：${NC}"
        echo -e "1) VLESS + WS + TLS (推荐)"
        echo -e "2) VMess + WS + TLS"
        echo -e "3) 返回主菜单"
        read -p "选择 [1-3, 默认1]: " p_choice
        
        case $p_choice in
            2) PROTO="vmess" ; break ;;
            3) return ;;
            *) PROTO="vless" ; break ;;
        esac
    done
    
    read -p "请输入解析域名 (例如: cc.myvpsworld.top): " DOMAIN
    [[ -z "$DOMAIN" ]] && return
    
    # 调用解析检测
    check_dns "$DOMAIN" || return

    echo -e "${GREEN}正在安装核心与Caddy...${NC}"
    apt update && apt install -y curl wget jq uuid-runtime caddy vnstat
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fscript/master/install-release.sh)

    UUID=$(uuidgen)
    WSPATH="/$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 10)"

    mkdir -p /usr/local/etc/v2ray
    cat <<EOF > $CONFIG_FILE
{
  "inbounds": [{
    "port": 10000, "listen":"127.0.0.1", "protocol": "$PROTO",
    "settings": { "clients": [{"id": "$UUID" $( [[ "$PROTO" == "vless" ]] && echo ',"decryption": "none"' ) }] },
    "streamSettings": { "network": "ws", "wsSettings": {"path": "$WSPATH"} }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

    cat <<EOF > $CADDY_FILE
$DOMAIN {
    reverse_proxy $WSPATH localhost:10000
    file_server { root /var/www/html }
}
EOF
    
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

    systemctl daemon-reload && systemctl enable v2ray caddy && systemctl restart v2ray caddy
    generate_output "$UUID" "$DOMAIN" "$WSPATH" "$PROTO"
}

# 2. 查看配置
show_config() {
    if [[ ! -f $CONFIG_FILE ]]; then
        echo -e "${RED}未检测到安装配置！${NC}"
        return
    fi
    local proto=$(jq -r '.inbounds[0].protocol' $CONFIG_FILE)
    local domain=$(grep -v "{" $CADDY_FILE | head -n 1 | awk '{print $1}')
    local path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' $CONFIG_FILE)
    
    echo -e "${YELLOW}当前配置中的所有用户：${NC}"
    local count=$(jq '.inbounds[0].settings.clients | length' $CONFIG_FILE)
    for ((i=0; i<$count; i++)); do
        local uuid=$(jq -r ".inbounds[0].settings.clients[$i].id" $CONFIG_FILE)
        echo -e "用户 $((i+1)):"
        generate_output "$uuid" "$domain" "$path" "$proto"
    done
}

# 3. 增加用户
add_user() {
    [[ ! -f $CONFIG_FILE ]] && echo -e "${RED}请先安装！${NC}" && return
    local new_uuid=$(uuidgen)
    local proto=$(jq -r '.inbounds[0].protocol' $CONFIG_FILE)
    
    if [[ "$proto" == "vless" ]]; then
        jq ".inbounds[0].settings.clients += [{\"id\": \"$new_uuid\", \"decryption\": \"none\"}]" $CONFIG_FILE > ${CONFIG_FILE}.tmp
    else
        jq ".inbounds[0].settings.clients += [{\"id\": \"$new_uuid\"}]" $CONFIG_FILE > ${CONFIG_FILE}.tmp
    fi
    
    mv ${CONFIG_FILE}.tmp $CONFIG_FILE
    systemctl restart v2ray
    echo -e "${GREEN}用户添加成功！${NC}"
    show_config
}

# 4. 删除配置 (卸载)
uninstall_v2ray() {
    read -p "确定要彻底删除 V2Ray 和 Caddy 吗？(y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        systemctl stop v2ray caddy
        systemctl disable v2ray caddy
        rm -rf /usr/local/etc/v2ray /usr/local/bin/v2ray /etc/caddy /etc/systemd/system/v2ray.service
        echo -e "${GREEN}卸载完成！${NC}"
    fi
}

# --- 主菜单 ---
while true; do
    echo -e "${YELLOW}=================================${NC}"
    echo -e "${GREEN}   将军阁下的 V2Ray 管理面板 ${NC}"
    echo -e "${GREEN}   随即号码：767 ${NC}"
    echo -e "${YELLOW}=================================${NC}"
    echo -e "1) 安装 V2Ray (默认推荐 VLESS)"
    echo -e "2) 查看当前配置与链接"
    echo -e "3) 增加新用户 (多UUID)"
    echo -e "4) 彻底卸载 (删除所有配置)"
    echo -e "q) 退出"
    read -p "请选择操作: " opt
    case $opt in
        1) install_v2ray ;;
        2) show_config ;;
        3) add_user ;;
        4) uninstall_v2ray ;;
        q) exit 0 ;;
        *) echo -e "${RED}无效选项${NC}" ;;
    esac
done