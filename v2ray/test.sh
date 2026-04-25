#!/bin/bash

# ====================================================
# 将军阁下，这是针对 Debian 12 深度修复的 V2.4 脚本
# 修复：awk/gawk 安装包名，重构 URL 拼接逻辑
# ====================================================

CONFIG_FILE="/etc/v2ray/config.json"

# --- 1. 环境准备 (修正 Debian 12 包名) ---
install_base() {
    echo "正在准备系统环境..."
    apt update && apt install -y curl jq gawk grep base64
    if ! command -v v2ray &> /dev/null; then
        echo "正在安装核心组件..."
        bash <(curl -s -L https://git.io/v2ray.sh)
    fi
}

# --- 2. 核心配置写入 (保持优化策略) ---
write_config() {
    local PROTOCOL=$1
    local UUID=$2
    local WSPATH=$3

    cat > $CONFIG_FILE << EOF
{
  "log": { "loglevel": "warning" },
  "dns": { "servers": ["localhost"], "queryStrategy": "UseIPv4" },
  "inbounds": [{
    "port": 12345,
    "listen": "127.0.0.1",
    "protocol": "$PROTOCOL",
    "settings": {
      "clients": [ { "id": "$UUID", "level": 0 } ],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": { "path": "$WSPATH" }
    }
  }],
  "outbounds": [
    { "protocol": "freedom", "settings": { "domainStrategy": "UseIPv4" } }
  ]
}
EOF
    systemctl restart v2ray
}

# --- 3. 增强版链接拼接函数 ---
generate_link() {
    if [ ! -f "$CONFIG_FILE" ]; then return; fi

    local PROTOCOL=$(jq -r '.inbounds[0].protocol' $CONFIG_FILE)
    local UUID=$(jq -r '.inbounds[0].settings.clients[0].id' $CONFIG_FILE)
    local WSPATH=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' $CONFIG_FILE)
    
    # 获取域名：优先尝试 v2ray info，失败则获取主机名
    local DOMAIN=$(v2ray info 2>/dev/null | grep "域名" | awk '{print $2}')
    [ -z "$DOMAIN" ] && DOMAIN=$(hostname -f)
    
    # 路径 URL 编码
    local ENCODED_PATH=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$WSPATH', safe=''))" 2>/dev/null || echo "$WSPATH" | sed 's/\//%2F/g')
    local REMARK="Racknerd_Debian12"

    echo "-----------------------------------------------"
    if [ "$PROTOCOL" == "vless" ]; then
        echo "VLESS 分享链接:"
        echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${ENCODED_PATH}#${REMARK}"
    else
        echo "VMess 分享链接:"
        local VMESS_JSON=$(cat <<EOF
{ "v": "2", "ps": "${REMARK}", "add": "${DOMAIN}", "port": "443", "id": "${UUID}", "aid": "0", "net": "ws", "type": "none", "host": "${DOMAIN}", "path": "${WSPATH}", "tls": "tls" }
EOF
)
        echo "vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
    fi
    echo "-----------------------------------------------"
}

# --- 4. 交互菜单 ---
show_menu() {
    clear
    echo "==============================================="
    echo "       V2Ray 战略指挥面板 V2.4 (修正版)       "
    echo "==============================================="
    echo " 1) 安装/重置为: VLESS-WS-TLS"
    echo " 2) 安装/重置为: VMess-WS-TLS"
    echo " 3) 查看当前配置报告与链接"
    echo " 4) 增加一条新 UUID"
    echo " 5) 彻底删除配置"
    echo " 0) 退出"
    echo "-----------------------------------------------"
    read -p "指令 [0-5]: " num

    case "$num" in
        1|2)
            install_base
            local PROT="vless"
            [ "$num" == "2" ] && PROT="vmess"
            local NEW_ID=$(cat /proc/sys/kernel/random/uuid)
            local NEW_PATH="/$(cat /proc/sys/kernel/random/uuid | cut -c1-8)"
            write_config "$PROT" "$NEW_ID" "$NEW_PATH"
            echo "配置已成功应用！"
            generate_link
            read -p "按回车返回菜单..."
            ;;
        3) 
            generate_link
            read -p "按回车返回菜单..." 
            ;;
        4)
            local NEW_UUID=$(cat /proc/sys/kernel/random/uuid)
            jq ".inbounds[0].settings.clients += [{\"id\": \"$NEW_UUID\", \"level\": 0}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
            systemctl restart v2ray
            echo "已添加新 UUID: $NEW_UUID"
            read -p "按回车返回..."
            ;;
        5)
            systemctl stop v2ray
            rm -f $CONFIG_FILE
            echo "已清理所有配置。"
            read -p "按回车返回..."
            ;;
        0) exit 0 ;;
    esac
}

while true; do show_menu; done