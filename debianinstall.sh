#!/bin/bash
# ==============================================================
#  Debian 13 一键初始化脚本
#  功能：时区、locale、常用工具、IPv4/IPv6转发、BBR
# ==============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查 root 权限
[[ $EUID -ne 0 ]] && error "请使用 root 权限运行此脚本：sudo bash $0"

# ==============================================================
#  多选菜单
# ==============================================================

MENU_ITEMS=(
    "设置时区（Asia/Shanghai）"
    "配置 Locale（英文界面 + 中文支持）"
    "安装常用工具（curl wget vim net-tools）"
    "启用 IPv4/IPv6 转发 + BBR"
)
# 默认全不选
SELECTED=(0 0 0 0)

print_menu() {
    clear
    echo -e "\n${BOLD}=====================================================${NC}"
    echo -e "${BOLD}   Debian 13 初始化脚本 — 选择要执行的功能${NC}"
    echo -e "${BOLD}=====================================================${NC}"
    echo -e "  ${CYAN}输入序号切换选中/取消，a=全选，n=全不选，回车确认执行${NC}\n"
    for i in "${!MENU_ITEMS[@]}"; do
        local idx=$((i + 1))
        if [[ "${SELECTED[$i]}" == "1" ]]; then
            echo -e "  ${GREEN}[✔] ${idx}. ${MENU_ITEMS[$i]}${NC}"
        else
            echo -e "  ${RED}[ ] ${idx}. ${MENU_ITEMS[$i]}${NC}"
        fi
    done
    echo ""
    echo -e "  ${YELLOW}a${NC} 全选   ${YELLOW}n${NC} 全不选   ${YELLOW}q${NC} 退出   ${YELLOW}回车${NC} 开始执行"
    echo -e "${BOLD}=====================================================${NC}"
    echo -n "  请输入: "
}

# 交互循环
while true; do
    print_menu
    read -r input

    case "$input" in
        "")
            any=0
            for s in "${SELECTED[@]}"; do [[ "$s" == "1" ]] && any=1; done
            if [[ $any -eq 0 ]]; then
                echo -e "\n  ${YELLOW}[WARN]${NC}  至少需要选择一项，请重新选择"
                sleep 1
            else
                break
            fi
            ;;
        a|A) SELECTED=(1 1 1 1) ;;
        n|N) SELECTED=(0 0 0 0) ;;
        q|Q)
            clear
            echo -e "\n  ${YELLOW}已退出，未执行任何操作。${NC}\n"
            exit 0
            ;;
        [1-4])
            idx=$((input - 1))
            [[ "${SELECTED[$idx]}" == "1" ]] && SELECTED[$idx]=0 || SELECTED[$idx]=1
            ;;
        *)
            echo -e "\n  ${YELLOW}[WARN]${NC}  无效输入，请输入 1-4 / a / n / q / 回车"
            sleep 1
            ;;
    esac
done

clear
echo ""
echo -e "${BOLD}=====================================================${NC}"
echo -e "${BOLD}   开始执行...${NC}"
echo -e "${BOLD}=====================================================${NC}"
echo ""

SUMMARY=()

# ==============================================================
#  1. 修改时区
# ==============================================================
if [[ "${SELECTED[0]}" == "1" ]]; then
    info "设置时区为 Asia/Shanghai ..."
    timedatectl set-timezone Asia/Shanghai
    TZ_RESULT="$(timedatectl | grep 'Time zone' | awk '{print $3}')"
    success "时区已设置为：$TZ_RESULT"
    SUMMARY+=("  时区        : $TZ_RESULT")
else
    warn "跳过：设置时区"
    SUMMARY+=("  时区        : 未修改（跳过）")
fi

# ==============================================================
#  2. Locale
# ==============================================================
if [[ "${SELECTED[1]}" == "1" ]]; then
    info "配置 Locale（英文界面 + 中文支持）..."
    apt-get update -qq
    apt-get install -y -qq locales

    sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
    grep -q "^en_US.UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    grep -q "^zh_CN.UTF-8" /etc/locale.gen || echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen

    locale-gen > /dev/null 2>&1
    update-locale LANG=en_US.UTF-8 LC_CTYPE=zh_CN.UTF-8
    cat > /etc/default/locale <<EOF
LANG=en_US.UTF-8
LC_CTYPE=zh_CN.UTF-8
EOF
    success "Locale 配置完成（系统提示英文，支持中文字符）"
    SUMMARY+=("  系统语言    : en_US.UTF-8（提示英文，支持中文）")
else
    warn "跳过：配置 Locale"
    SUMMARY+=("  系统语言    : 未修改（跳过）")
fi

# ==============================================================
#  3. 安装常用工具
# ==============================================================
if [[ "${SELECTED[2]}" == "1" ]]; then
    info "安装常用工具：curl wget vim net-tools ..."
    apt-get update -qq
    apt-get install -y -qq curl wget vim net-tools
    success "curl、wget、vim、net-tools 安装完成"
    SUMMARY+=("  安装工具    : curl wget vim net-tools")
else
    warn "跳过：安装常用工具"
    SUMMARY+=("  安装工具    : 未安装（跳过）")
fi

# ==============================================================
#  4. IPv4/IPv6 转发 + BBR
# ==============================================================
if [[ "${SELECTED[3]}" == "1" ]]; then
    info "配置 IPv4/IPv6 转发 + BBR ..."

    SYSCTL_CONF="/etc/sysctl.d/99-debian-init.conf"
    cat > "$SYSCTL_CONF" <<EOF
# ---- IPv4/IPv6 转发 ----
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# ---- BBR 拥塞控制 ----
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    sysctl --system > /dev/null 2>&1

    BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    IPV4_FWD=$(sysctl net.ipv4.ip_forward 2>/dev/null | awk '{print $3}')
    IPV6_FWD=$(sysctl net.ipv6.conf.all.forwarding 2>/dev/null | awk '{print $3}')

    [[ "$IPV4_FWD" == "1" ]] && success "IPv4 转发已启用" || warn "IPv4 转发启用失败，请手动检查"
    [[ "$IPV6_FWD" == "1" ]] && success "IPv6 转发已启用" || warn "IPv6 转发启用失败，请手动检查"
    [[ "$BBR_STATUS" == "bbr" ]] && success "BBR 拥塞控制已启用" || warn "BBR 启用失败（内核需 >= 4.9），当前：$BBR_STATUS"

    SUMMARY+=("  IPv4 转发   : $IPV4_FWD")
    SUMMARY+=("  IPv6 转发   : $IPV6_FWD")
    SUMMARY+=("  TCP 拥塞控制: $BBR_STATUS")
else
    warn "跳过：IPv4/IPv6 转发 + BBR"
    SUMMARY+=("  转发 / BBR  : 未配置（跳过）")
fi

# ==============================================================
#  汇总
# ==============================================================
echo ""
echo -e "${BOLD}=====================================================${NC}"
echo -e "${GREEN}${BOLD}  执行完成！汇总如下：${NC}"
echo -e "${BOLD}=====================================================${NC}"
for line in "${SUMMARY[@]}"; do
    echo -e "$line"
done
echo -e "${BOLD}=====================================================${NC}"
echo ""

[[ "${SELECTED[1]}" == "1" ]] && warn "建议重新登录终端（或执行 source /etc/default/locale）使 locale 完全生效"
echo ""