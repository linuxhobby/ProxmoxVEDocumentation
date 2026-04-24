#!/bin/bash

# ==============================================================
#  Debian 13 可视化初始化脚本 (过程可见)
#  1、安装基础工具包：net-tools vnstat vim wget
#  2、时区设置
#  3、自动配置vnstat 配置
#  4、执行v2ray一键安装脚本
# ==============================================================

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[错误] 请使用 root 权限运行此脚本。${NC}"
   exit 1
fi

echo -e "${BLUE}${BOLD}>>> 开始执行系统初始化...${NC}"

# 1. 安装基础工具
echo -e "${YELLOW}>>> 2. 正在安装工具 (net-tools, vnstat, vim, curl)...${NC}"
apt-get install -y net-tools vnstat vim wget
echo -e "${GREEN}>>> 工具安装完毕。${NC}"


# 2. 时区设置
echo -e "${YELLOW}>>> 1. 正在设置时区...${NC}"
timedatectl set-timezone Asia/Shanghai
echo -e "${GREEN}>>> 时区已同步为 Asia/Shanghai，时间状态:$(date)${NC}"


# 3. vnstat 配置
echo -e "${YELLOW}>>> 3. 正在配置 vnstat...${NC}"
IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
echo -e "    检测到主网卡接口为: ${BOLD}${IFACE}${NC}"
if [ -f /etc/vnstat.conf ]; then
    sed -i "s/^Interface .*/Interface \"$IFACE\"/" /etc/vnstat.conf
    vnstat --add -i "$IFACE" || true
    systemctl enable vnstat --now
    systemctl restart vnstat
    echo -e "${GREEN}>>> vnstat 已绑定并启动。${NC}"
else
    echo -e "${RED}    警告: 未找到 /etc/vnstat.conf${NC}"
fi

echo -e "${BLUE}${BOLD}>>> 所有任务执行完毕，系统已配置完成。${NC}"

# 3. vnstat 配置
echo -e "${BLUE}${BOLD}>>> 下面开始执行v2ray一键安装脚本。${NC}"
bash <(wget -qO- -o- https://github.com/233boy/v2ray/raw/master/install.sh)
