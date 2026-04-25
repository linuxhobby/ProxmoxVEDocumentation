#!/bin/bash

# ====================================================
# 将军自持版 V5.1 - 修复官方 404 报错 (最终修正)
# 适配系统：Debian 12, Debian 13
# ====================================================

CONFIG_DIR="/etc/v2ray"
CONFIG_FILE="$CONFIG_DIR/config.json"

# --- 核心部署：使用官方维护的新地址 ---
install_v2ray() {
    if ! command -v v2ray &> /dev/null; then
        echo "正在从官方源部署核心组件..."
        mkdir -p $CONFIG_DIR
        # 安装基础依赖
        apt update && apt install -y curl jq gawk grep coreutils python3
        # 使用官方目前推荐的安装脚本 (v2fly 维护)
        bash <(curl -L https://raw.githubusercontent.com/v2fly/fuc-v2ray/master/install-release.sh)
        
        # 如果官方脚本没能自动启动，则手动重载
        systemctl daemon-reload
    fi
}

# --- 写入配置 ---
write_config() {
    local PROTO=$1
    local UUID=$2
    local PATH_STR=$3

    cat > $CONFIG_FILE <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": 12345,
    "listen": "127.0.0.1",
    "protocol": "$PROTO",
    "settings": {
      "clients": [ { "id": "$UUID", "level": 0 } ],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": { "path": "$PATH_STR" }
    }
  }],
  "outbounds": [
    { "protocol": "freedom", "settings": {} }
  ]
}
EOF
    # 尝试重启服务，若服务名不同则尝试兼容处理
    systemctl restart v2ray || systemctl restart v2ray.service
}

# --- 链接拼接 ---
generate_links() {
    if [ ! -f "$CONFIG_FILE" ]; then 
        echo "尚未安装配置，请先执行安装。"
        return 
    fi
    
    local ADDR=$(hostname -f)
    echo "-----------------------------------------------"
    read -p "当前识别域名为 [$ADDR]，若需修改请输入，否则回车: " INPUT_ADDR
    [ ! -z "$INPUT_ADDR" ] && ADDR=$INPUT_ADDR
    
    local PROTO=$(jq -r '.inbounds[0].protocol' $CONFIG_FILE)
    local ID=$(jq -r '.inbounds[0].settings.clients[0].id' $CONFIG_FILE)
    local PR=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' $CONFIG_FILE)
    
    local P_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$PR', safe=''))")

    echo "==============================================="
    if [ "$PROTO" == "vless" ]; then
        echo "VLESS 分享链接:"
        echo "vless://${ID}@${ADDR}:443?encryption=none&security=tls&type=ws&host=${ADDR}&path=${P_ENC}#General_V5"
    else
        local VM_J="{\"v\":\"2\",\"ps\":\"General_V5\",\"add\":\"${ADDR}\",\"port\":\"443\",\"id\":\"${ID}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${ADDR}\",\"path\":\"${PR}\",\"tls\":\"tls\"}"
        echo "VMess 分享链接:"
        echo "vmess://$(echo -n "$VM_J" | base64 -w 0)"
    fi
    echo "==============================================="
}

# --- 菜单 ---
while true; do
    echo ""
    echo "==============================================="
    echo "      V2Ray 战略指挥面板 V5.1 (Debian 12/13)   "
    echo "==============================================="
    echo " 1) 部署 VLESS-WS-TLS"
    echo " 2) 部署 VMess-WS-TLS"
    echo " 3) 查看当前报告"
    echo " 4) 退出"
    read -p "指令 [1-4]: " opt

    case $opt in
        1|2)
            install_v2ray
            P_TYPE="vless"; [ "$opt" == "2" ] && P_TYPE="vmess"
            UUID=$(cat /proc/sys/kernel/random/uuid)
            WPATH="/ray$(cat /proc/sys/kernel/random/uuid | cut -c1-4)"
            write_config "$P_TYPE" "$UUID" "$WPATH"
            generate_links
            read -p "回车继续..."
            ;;
        3) generate_links; read -p "回车继续..." ;;
        4) exit 0 ;;
        *) echo "无效指令" ;;
    esac
done