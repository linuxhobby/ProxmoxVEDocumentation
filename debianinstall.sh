#!/bin/bash
# ==============================================================
#  Debian 13 一键初始化脚本
#  功能：时区、locale、常用工具、IPv4/IPv6转发、BBR、清华源、Docker
# 执行：bash <(curl -fsSL https://raw.githubusercontent.com/linuxhobby/ProxmoxVEDocumentation/refs/heads/main/debianinstall.sh)
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
    "启用 IPv4/IPv6 转发 + 开启BBR"
    "修改 apt 源为清华镜像源"
    "安装 Docker（官方源 + 清华镜像加速）"
    "修改主机名称（Hostname）"
)
# 默认全不选，增加选项需要修改这里
SELECTED=(0 0 0 0 0 0 0)

print_menu() {
    clear
    echo -e "\n${BOLD}=====================================================${NC}"
    echo -e "${BOLD}   Debian 13 初始化脚本 — 选择要执行的功能${NC}"
    echo -e "${BOLD}   作者：MARCO CHAN${NC}"
    echo -e "${BOLD}   更细：2026/04/07${NC}"
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
    echo -e "  ${CYAN}a${NC} 全选   ${CYAN}n${NC} 全不选   ${CYAN}q${NC} 退出   ${CYAN}回车${NC} 开始执行"
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
                echo -e "\n  ${YELLOW}[RED]${NC}  至少需要选择一项，请重新选择"
                sleep 1
            else
                break
            fi
            ;;
        a|A) SELECTED=(1 1 1 1 1 1 1) ;;
        n|N) SELECTED=(0 0 0 0 0 0 0) ;;
        q|Q)
            clear
            echo -e "\n  ${RED}已退出，未执行任何操作。${NC}\n"
            exit 0
            ;;
        [1-7])
            idx=$((input - 1))
            [[ "${SELECTED[$idx]}" == "1" ]] && SELECTED[$idx]=0 || SELECTED[$idx]=1
            ;;
        *)
            echo -e "\n  ${RED}[WARN]${NC}  无效输入，请输入 1-7 / a / n / q / 回车"
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
#  5. 修改 apt 源为清华镜像源
# ==============================================================
if [[ "${SELECTED[4]}" == "1" ]]; then
    info "修改 apt 源为清华镜像源 ..."

    SOURCES_DIR="/etc/apt/sources.list.d"
    BACKUP_DIR="/etc/apt/sources.list.d/backup_$(date +%Y%m%d%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    if [[ -f /etc/apt/sources.list ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
        info "已备份原 sources.list 至 /etc/apt/sources.list.bak"
    fi

    find "$SOURCES_DIR" -maxdepth 1 \( -name "*.sources" -o -name "*.list" \) \
        ! -path "$BACKUP_DIR/*" -exec cp {} "$BACKUP_DIR/" \; 2>/dev/null || true

    CODENAME=$(lsb_release -cs 2>/dev/null || grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
    CODENAME=${CODENAME:-trixie}

    find "$SOURCES_DIR" -maxdepth 1 \( -name "*.sources" -o -name "*.list" \) \
        ! -path "$BACKUP_DIR/*" -exec mv {} {}.disabled \; 2>/dev/null || true
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

    if apt-get update -qq 2>&1 | grep -qi "error\|failed"; then
        warn "清华源更新时出现错误，正在回滚..."
        find "$SOURCES_DIR" -maxdepth 1 -name "*.disabled" \
            ! -path "$BACKUP_DIR/*" | while read f; do mv "$f" "${f%.disabled}"; done
        [[ -f /etc/apt/sources.list.disabled ]] && mv /etc/apt/sources.list.disabled /etc/apt/sources.list
        rm -f /etc/apt/sources.list.d/tuna.sources
        apt-get update -qq
        warn "已回滚至原始源"
        SUMMARY+=("  apt 源      : 切换失败，已回滚原始源")
    else
        success "apt 源已切换为清华镜像源（${CODENAME}）"
        SUMMARY+=("  apt 源      : 清华镜像源 mirrors.tuna.tsinghua.edu.cn")
    fi
else
    warn "跳过：修改 apt 源"
    SUMMARY+=("  apt 源      : 未修改（跳过）")
fi

# ==============================================================
#  6. 安装 Docker
# ==============================================================
if [[ "${SELECTED[5]}" == "1" ]]; then
    info "安装 Docker ..."

    # 若已安装则跳过
    if command -v docker &>/dev/null; then
        DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
        warn "Docker 已安装（版本：$DOCKER_VER），跳过安装"
        SUMMARY+=("  Docker      : 已存在 v$DOCKER_VER（跳过安装）")
    else
        # 安装依赖
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release

        # 添加 Docker GPG key（从清华镜像获取）
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian/gpg \
            -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        # 获取系统代号与架构
        CODENAME=$(lsb_release -cs 2>/dev/null || grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
        CODENAME=${CODENAME:-trixie}
        ARCH=$(dpkg --print-architecture)

        # 写入 Docker 软件源（DEB822 格式，清华镜像）
        cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

        # 安装 Docker Engine + Compose 插件
        apt-get update -qq
        apt-get install -y -qq \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin

        # 启动并设为开机自启
        systemctl enable docker --now

        # 配置镜像加速 + 日志限制
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.mirrors.tuna.tsinghua.edu.cn"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
        systemctl daemon-reload
        systemctl restart docker

        # 验证结果
        DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
        COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "未知")

        if systemctl is-active --quiet docker; then
            success "Docker 安装完成，服务已启动"
            success "Docker 版本：$DOCKER_VER"
            success "Docker Compose 版本：$COMPOSE_VER"
            success "镜像加速：docker.mirrors.tuna.tsinghua.edu.cn"
            SUMMARY+=("  Docker      : v$DOCKER_VER（已启动，开机自启）")
            SUMMARY+=("  Compose     : v$COMPOSE_VER")
            SUMMARY+=("  镜像加速    : docker.mirrors.tuna.tsinghua.edu.cn")
        else
            warn "Docker 服务启动失败，请手动执行：systemctl start docker"
            SUMMARY+=("  Docker      : 已安装 v$DOCKER_VER（服务未启动）")
        fi
    fi
else
    warn "跳过：安装 Docker"
    SUMMARY+=("  Docker      : 未安装（跳过）")
fi


# ==============================================================
#  7. 修改主机名
# ==============================================================
if [[ "${SELECTED[6]}" == "1" ]]; then
    echo -e "\n${CYAN}[INPUT]${NC} 请输入新的主机名 (Hostname):"
    read -r NEW_HOSTNAME
    if [[ -n "$NEW_HOSTNAME" ]]; then
        OLD_HOSTNAME=$(hostname)
        info "修改主机名: $OLD_HOSTNAME -> $NEW_HOSTNAME ..."
        hostnamectl set-hostname "$NEW_HOSTNAME"
        sed -i "s/$OLD_HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts
        success "主机名修改成功"
        SUMMARY+=("  主机名          : $OLD_HOSTNAME -> $NEW_HOSTNAME")
    else
        warn "输入为空，跳过修改"
        SUMMARY+=("  主机名          : 未修改（输入为空）")
    fi
else
    SUMMARY+=("  主机名          : 未修改（跳过）")
fi



# 功能分支都添加在这上面
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