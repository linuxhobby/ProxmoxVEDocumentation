#!/bin/bash
# ==============================================================
#  Debian 13 一键初始化脚本
#  功能：时区、locale、常用工具、IPv4/IPv6转发、BBR、清华源、Docker、V2Ray、修改主机名
#  更新：2026/04/07
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
#  多选菜单 (注意这里的顺序)
# ==============================================================

MENU_ITEMS=(
    "设置时区（Asia/Shanghai）"
    "配置 Locale（英文界面 + 中文支持）"
    "安装常用工具（curl wget vim net-tools）"
    "启用 IPv4/IPv6 转发 + 开启BBR"
    "修改 apt 源为清华镜像源"
    "安装 Docker（官方源 + 清华镜像加速）"
    "执行 V2Ray 安装脚本2"
    "修改主机名称（Hostname）"
)
# 默认全不选
SELECTED=(0 0 0 0 0 0 0 0)

print_menu() {
    clear
    echo -e "\n${BOLD}=====================================================${NC}"
    echo -e "${BOLD}   Debian 13 初始化脚本 — 选择要执行的功能${NC}"
    echo -e "${BOLD}   作者：MARCO CHAN${NC}"
    echo -e "${BOLD}   更新：2026/04/07${NC}"
    echo -e "${BOLD}=====================================================${NC}"
    echo -e "  ${GREEN}输入序号切换选中/取消，a=全选，n=全不选，回车确认执行${NC}\n"
    for i in "${!MENU_ITEMS[@]}"; do
        local idx=$((i + 1))
        if [[ "${SELECTED[$i]}" == "1" ]]; then
            echo -e "  ${GREEN}[✔] ${idx}. ${MENU_ITEMS[$i]}${NC}"
        else
            echo -e "  ${RED}[ ] ${idx}. ${MENU_ITEMS[$i]}${NC}"
        fi
    done
    echo ""
    echo -e "  ${GREEN}a${NC} 全选   ${GREEN}n${NC} 全不选   ${RED}q${NC} 退出   ${CYAN}回车${NC} 开始执行"
    echo -e "${BOLD}=====================================================${NC}"
    echo -n "  请输入【序列号】，然后回车（Enter）: "
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
        a|A) SELECTED=(1 1 1 1 1 1 1 1) ;;
        n|N) SELECTED=(0 0 0 0 0 0 0 0) ;;
        q|Q)
            clear
            echo -e "\n  ${RED}已退出，未执行任何操作。${NC}\n"
            exit 0
            ;;
        [1-8])
            idx=$((input - 1))
            [[ "${SELECTED[$idx]}" == "1" ]] && SELECTED[$idx]=0 || SELECTED[$idx]=1
            ;;
        *)
            # 这里原本你写的是 1-7，已修正为 1-8
            echo -e "\n  ${YELLOW}[WARN]${NC}  无效输入，请输入 1-8 / a / n / q / 回车"
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

# --- 1. 修改时区 ---
if [[ "${SELECTED[0]}" == "1" ]]; then
    info "设置时区为 Asia/Shanghai ..."
    timedatectl set-timezone Asia/Shanghai
    TZ_RESULT="$(timedatectl | grep 'Time zone' | awk '{print $3}')"
    success "时区已设置为：$TZ_RESULT"
    SUMMARY+=("  时区            : $TZ_RESULT")
else
    SUMMARY+=("  时区            : 未修改（跳过）")
fi

# --- 2. Locale ---
if [[ "${SELECTED[1]}" == "1" ]]; then
    info "配置 Locale..."
    apt-get update -qq && apt-get install -y -qq locales
    sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen > /dev/null 2>&1
    update-locale LANG=en_US.UTF-8 LC_CTYPE=zh_CN.UTF-8
    success "Locale 配置完成"
    SUMMARY+=("  系统语言        : en_US.UTF-8（支持中文）")
else
    SUMMARY+=("  系统语言        : 未修改（跳过）")
fi

# --- 3. 安装工具 ---
if [[ "${SELECTED[2]}" == "1" ]]; then
    info "安装常用工具..."
    apt-get update -qq && apt-get install -y -qq curl wget vim net-tools
    success "工具安装完成"
    SUMMARY+=("  安装工具        : curl wget vim net-tools")
else
    SUMMARY+=("  安装工具        : 未安装（跳过）")
fi

# --- 4. 网络优化 ---
if [[ "${SELECTED[3]}" == "1" ]]; then
    info "配置 IPv4/IPv6 转发 + BBR ..."
    cat > "/etc/sysctl.d/99-debian-init.conf" <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl --system > /dev/null 2>&1
    BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    success "BBR 已启用: $BBR_STATUS"
    SUMMARY+=("  网络优化        : 转发+BBR已开启")
else
    SUMMARY+=("  网络优化        : 未配置（跳过）")
fi

# --- 5. 清华源 ---
if [[ "${SELECTED[4]}" == "1" ]]; then
    info "修改 apt 源为清华镜像源..."
    CODENAME=$(lsb_release -cs 2>/dev/null || grep VERSION_CODENAME /etc/os-release | cut -d= -f2 || echo "trixie")
    [[ -f /etc/apt/sources.list ]] && mv /etc/apt/sources.list /etc/apt/sources.list.disabled 2>/dev/null || true
    cat > /etc/apt/sources.list.d/tuna.sources <<EOF
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian
Suites: ${CODENAME} ${CODENAME}-updates ${CODENAME}-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian-security
Suites: ${CODENAME}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    apt-get update -qq && success "apt 源已切换" || warn "源更新失败"
    SUMMARY+=("  apt 源          : 清华镜像源")
else
    SUMMARY+=("  apt 源          : 未修改（跳过）")
fi

# --- 6. Docker ---
if [[ "${SELECTED[5]}" == "1" ]]; then
    info "安装 Docker..."
    if command -v docker &>/dev/null; then
        warn "Docker 已安装，跳过"
        SUMMARY+=("  Docker          : 已存在（跳过）")
    else
        apt-get update -qq && apt-get install -y -qq ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        CODENAME=$(lsb_release -cs 2>/dev/null || grep VERSION_CODENAME /etc/os-release | cut -d= -f2 || echo "trixie")
        ARCH=$(dpkg --print-architecture)
        cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
        apt-get update -qq && apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://docker.mirrors.tuna.tsinghua.edu.cn"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
        systemctl enable docker --now && systemctl restart docker
        success "Docker 安装完成"
        SUMMARY+=("  Docker          : 已安装并开启加速")
    fi
else
    SUMMARY+=("  Docker          : 未安装（跳过）")
fi

# --- 7. V2Ray (对应菜单第7项 SELECTED[6]) ---
if [[ "${SELECTED[6]}" == "1" ]]; then
    info "准备安装 V2Ray 一键安装脚本..."
    apt-get update -qq && apt-get install -y -qq wget curl
    warn "即将进入 V2Ray 交互式安装界面，请根据提示操作。"
    sleep 2
    bash <(wget -qO- -o- https://github.com/233boy/v2ray/raw/master/install.sh)
    success "V2Ray 脚本执行完毕"
    SUMMARY+=("  V2Ray           : 已运行安装脚本")
else
    SUMMARY+=("  V2Ray           : 未安装（跳过）")
fi

# --- 8. 主机名 (对应菜单第8项 SELECTED[7]) ---
if [[ "${SELECTED[7]}" == "1" ]]; then
    CURRENT_HOSTNAME=$(hostname)
    echo -e "\n${CYAN}[INPUT]${NC} 当前主机名 (Hostname) 为: ${RED}$CURRENT_HOSTNAME${NC}"
    echo -e "${CYAN}[INPUT]${NC} 请输入新的主机名 (Hostname):"
    read -r NEW_HOSTNAME
    if [[ -n "$NEW_HOSTNAME" && "$NEW_HOSTNAME" != "$CURRENT_HOSTNAME" ]]; then
        hostnamectl set-hostname "$NEW_HOSTNAME"
        sed -i "s/$CURRENT_HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts
        success "主机名已修改为: $NEW_HOSTNAME"
        echo -e "${RED}${BOLD}[!] 提示: 主机名已更改，建议稍后重启系统生效。${NC}"
        SUMMARY+=("  主机名          : $CURRENT_HOSTNAME -> $NEW_HOSTNAME")
    else
        SUMMARY+=("  主机名          : 未修改")
    fi
else
    SUMMARY+=("  主机名          : 未修改（跳过）")
fi

# ==============================================================
#  汇总展示
# ==============================================================
echo ""
echo -e "${BOLD}=====================================================${NC}"
echo -e "${GREEN}${BOLD}   执行完成！汇总如下：${NC}"
echo -e "${BOLD}=====================================================${NC}"
for line in "${SUMMARY[@]}"; do
    echo -e "$line"
done
echo -e "${BOLD}=====================================================${NC}"
echo ""