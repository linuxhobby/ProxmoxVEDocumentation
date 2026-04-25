#!/bin/bash

# ====================================================
# 将军阁下，这是针对 Debian 12 纯净版环境的最终优化脚本
# 解决：awk 虚拟包报错、URL 编码、DNS 解析撤销错误
# ====================================================

CONFIG_FILE="/etc/v2ray/config.json"

# --- 1. 强制环境对齐 (不再请求虚拟包) ---
prepare_env() {
    echo "正在执行环境标准化逻辑..."
    # 显式安装 gawk 而非 awk，显式安装 python3 处理 URL 编码
    apt update && apt install -y curl jq gawk grep base64 python3-minimal
    
    if ! command -v v2ray &> /dev/null; then
        echo "检测到核心组件缺失，正在启动安装程序..."
        # 此处使用您之前保存的安装脚本逻辑
        wget -N --no-check-certificate -q -O install.sh "https://raw.githubusercontent.com/wulabing/V2Ray_ws-tls_bash_onekey/master/install.sh" && chmod +x install.sh && bash install.sh
    fi
}

# --- 2. 深度注入优化配置 (针对 operation was canceled 报错) ---
apply_optimized_config() {
    local PROTOCOL=$1
    local UUID=$2
    local WSPATH=$3

    # 注入关键优化：AsIs 策略、IPv4 优先、延长握手时间
    cat > $CONFIG_FILE << EOF
{
  "log": { "loglevel": "warning" },
  "dns": { 
    "servers": ["localhost"], 
    "queryStrategy": "UseIPv4" 
  },
  "policy": { 
    "levels": { "0": { "handshake": 5, "connIdle": 300 } } 
  },
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
    { 
      "protocol": "freedom", 
      "settings": { "domainStrategy": "UseIPv4" } 
    }
  ]
}
EOF
    systemctl restart v2ray
    echo "优化配置已生效，服务已重启。"
}

# --- 3. 精准链接生成逻辑 ---
output_links() {
    [ ! -f "$CONFIG_FILE" ] && return
    
    local PROTO=$(jq -r '.inbounds[0].protocol' $CONFIG_FILE)
    local ID=$(jq -r '.inbounds[0].settings.clients[0].id' $CONFIG_FILE)
    local PATH_RAW=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' $CONFIG_FILE)
    
    # 动态抓取域名 (针对 233boy 或 Wulabing 环境)
    local ADDR=$(hostname -f)
    # 使用 Python3