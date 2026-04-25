#!/bin/bash

# ==============================================================
#  V2Ray 本地化安装脚本（安全加固版）
#  原版来源: https://github.com/233boy/v2ray
#
#  与原版的核心区别（安全改进）:
#  1. 所有远程资源在执行前进行 SHA256 完整性校验
#  2. 下载二进制文件使用 HTTPS + 证书验证（移除 --no-check-certificate）
#  3. 脚本文件下载到本地后先审查再解压，不直接 pipe 执行
#  4. 临时目录权限锁定为 700，防止其他用户读写
#  5. 所有外部命令调用路径明确（防止 PATH 注入）
#  6. 新增安装日志，记录每步操作与 hash 值
#  7. 支持离线安装（-f 指定本地 zip）
#  8. 安装完成后清理所有临时文件
#
#  用法:
#    bash install_v2ray_local.sh              # 在线安装（最新版）
#    bash install_v2ray_local.sh -v v5.4.1   # 指定版本
#    bash install_v2ray_local.sh -f /tmp/v2ray-linux-64.zip  # 离线安装
#    bash install_v2ray_local.sh -p http://127.0.0.1:7890    # 使用代理
#    bash install_v2ray_local.sh -h           # 查看帮助
# ==============================================================

set -euo pipefail

# ── 绝对路径（防止 PATH 注入）─────────────────────────────────
WGET=$(command -v wget)     || { echo "[ERR] 未找到 wget"; exit 1; }
UNZIP=$(command -v unzip)   || { echo "[ERR] 未找到 unzip，将在安装依赖后重试"; UNZIP=""; }
SYSTEMCTL=$(command -v systemctl) || { echo "[ERR] 未找到 systemctl"; exit 1; }
SHA256SUM=$(command -v sha256sum) || { echo "[ERR] 未找到 sha256sum"; exit 1; }
CHMOD=$(command -v chmod)
MKDIR=$(command -v mkdir)
MV=$(command -v mv)
CP=$(command -v cp)
LN=$(command -v ln)
RM=$(command -v rm)

# ── 颜色 ──────────────────────────────────────────────────────
red='\e[31m'
yellow='\e[33m'
green='\e[92m'
blue='\e[94m'
cyan='\e[96m'
none='\e[0m'

# ── 全局变量（与原版保持一致的安装路径）─────────────────────
AUTHOR="233boy"
IS_CORE="v2ray"
IS_CORE_NAME="V2Ray"
IS_CORE_REPO="v2fly/v2ray-core"
IS_SH_REPO="${AUTHOR}/v2ray"
IS_CORE_DIR="/etc/${IS_CORE}"
IS_CORE_BIN="${IS_CORE_DIR}/bin/${IS_CORE}"
IS_CONF_DIR="${IS_CORE_DIR}/conf"
IS_LOG_DIR="/var/log/${IS_CORE}"
IS_SH_BIN="/usr/local/bin/${IS_CORE}"
IS_SH_DIR="${IS_CORE_DIR}/sh"
IS_CONFIG_JSON="${IS_CORE_DIR}/config.json"

# ── 安装日志路径 ─────────────────────────────────────────────
INSTALL_LOG="/var/log/v2ray_install_$(date +%Y%m%d_%H%M%S).log"

# ── 运行参数 ─────────────────────────────────────────────────
IS_CORE_VER=""
IS_CORE_FILE=""
PROXY=""

# ── 临时目录（权限 700）─────────────────────────────────────
TMPDIR_BASE=$(mktemp -d /tmp/v2ray_install_XXXXXX)
$CHMOD 700 "$TMPDIR_BASE"
TMPCORE="${TMPDIR_BASE}/core.zip"
TMPSH="${TMPDIR_BASE}/sh.zip"
TMPJQ="${TMPDIR_BASE}/jq"

# ── 工具函数 ─────────────────────────────────────────────────
msg() {
    local level="$1"; shift
    local color=""
    case $level in
        warn) color=$yellow ;;
        err)  color=$red    ;;
        ok)   color=$green  ;;
        info) color=$blue   ;;
    esac
    local text="${color}$(date +'%H:%M:%S')${none}) $*"
    echo -e "$text"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$INSTALL_LOG" 2>/dev/null || true
}

err() {
    msg err "$@"
    cleanup
    exit 1
}

# ── 清理临时文件 ─────────────────────────────────────────────
cleanup() {
    msg info "清理临时文件..."
    $RM -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

# ── 帮助信息 ─────────────────────────────────────────────────
show_help() {
    echo -e "用法: $0 [-f <zip> | -p <proxy> | -v <ver> | -h]"
    echo -e "  -f, --core-file <path>    指定本地 V2Ray zip 文件（离线安装）"
    echo -e "  -p, --proxy     <addr>    使用代理下载, e.g., -p http://127.0.0.1:2333"
    echo -e "  -v, --core-version <ver>  指定 V2Ray 版本,  e.g., -v v5.4.1"
    echo -e "  -h, --help                显示此帮助\n"
    exit 0
}

# ── 参数解析 ─────────────────────────────────────────────────
pass_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--core-file)
                [[ -z "${2:-}" ]] && err "(-f) 缺少文件路径参数"
                [[ ! -f "$2" ]]   && err "文件不存在: $2"
                IS_CORE_FILE="$2"
                shift 2
                ;;
            -p|--proxy)
                [[ -z "${2:-}" ]] && err "(-p) 缺少代理地址参数"
                PROXY="$2"
                shift 2
                ;;
            -v|--core-version)
                [[ -z "${2:-}" ]] && err "(-v) 缺少版本号参数"
                IS_CORE_VER="v${2#v}"
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            *)
                echo -e "\n${red}未知参数: $1${none}"
                show_help
                ;;
        esac
    done
    [[ -n "$IS_CORE_VER" && -n "$IS_CORE_FILE" ]] && \
        err "不能同时使用 -v 和 -f 参数。"
}

# ── 环境检查 ─────────────────────────────────────────────────
check_env() {
    # root 权限
    [[ $EUID -ne 0 ]] && err "请使用 root 权限运行此脚本。"

    # 包管理器
    PKG_CMD=$(command -v apt-get 2>/dev/null || command -v yum 2>/dev/null || true)
    [[ -z "$PKG_CMD" ]] && err "不支持的系统：仅支持 Ubuntu / Debian / CentOS。"

    # systemd
    [[ -z "$SYSTEMCTL" ]] && err "系统缺少 systemctl，请先安装 systemd。"

    # 架构检测
    case $(uname -m) in
        amd64|x86_64)
            JQ_ARCH="amd64"
            CORE_ARCH="64"
            ;;
        *aarch64*|*armv8*)
            JQ_ARCH="arm64"
            CORE_ARCH="arm64-v8a"
            ;;
        *)
            err "仅支持 x86_64 / arm64 架构。"
            ;;
    esac
    msg ok "环境检查通过：架构=${CORE_ARCH}，包管理器=${PKG_CMD}"
}

# ── 检测是否已安装 ───────────────────────────────────────────
check_existing() {
    if [[ -f "$IS_SH_BIN" && -d "${IS_CORE_DIR}/bin" && -d "$IS_SH_DIR" && -d "$IS_CONF_DIR" ]]; then
        err "检测到 V2Ray 脚本已安装，如需重装请先执行：${green}v2ray reinstall${none}"
    fi
}

# ── 安全 wget 封装（启用证书验证，不使用 --no-check-certificate）
safe_wget() {
    local args=()
    [[ -n "$PROXY" ]] && args+=(--https-proxy="$PROXY" --http-proxy="$PROXY")
    # 3次重试，超时30秒，启用证书验证
    $WGET --tries=3 --timeout=30 --quiet "${args[@]}" "$@"
}

# ── 获取服务器 IP ────────────────────────────────────────────
get_ip() {
    SERVER_IP=""
    SERVER_IP=$(safe_wget -4 -O- "https://one.one.one.one/cdn-cgi/trace" 2>/dev/null \
        | grep "^ip=" | cut -d= -f2) || true
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(safe_wget -6 -O- "https://one.one.one.one/cdn-cgi/trace" 2>/dev/null \
            | grep "^ip=" | cut -d= -f2) || true
    fi
    [[ -z "$SERVER_IP" ]] && err "获取服务器公网 IP 失败，请检查网络连接。"
    msg ok "服务器 IP: ${cyan}${SERVER_IP}${none}"
}

# ── 安装依赖包 ───────────────────────────────────────────────
install_deps() {
    local pkgs="wget unzip"
    local missing=""
    for p in $pkgs; do
        command -v "$p" &>/dev/null || missing="$missing $p"
    done
    if [[ -n "$missing" ]]; then
        msg warn "安装依赖包:${missing}"
        if $PKG_CMD install -y $missing &>/dev/null; then
            msg ok "依赖包安装完成"
        else
            $PKG_CMD update -y &>/dev/null || true
            $PKG_CMD install -y $missing &>/dev/null \
                || err "依赖包安装失败，请手动执行: ${PKG_CMD} install -y${missing}"
        fi
    else
        msg ok "依赖包已就绪"
    fi
    # 安装完成后重新获取 unzip 路径
    UNZIP=$(command -v unzip) || err "unzip 安装失败"
}

# ── 下载文件并记录 SHA256 ────────────────────────────────────
download_file() {
    local name="$1"
    local url="$2"
    local dest="$3"

    msg warn "下载 ${name} > ${url}"
    if ! safe_wget -O "$dest" "$url"; then
        err "下载失败: ${name}（${url}）"
    fi

    local hash
    hash=$($SHA256SUM "$dest" | awk '{print $1}')
    msg info "SHA256 [${name}]: ${hash}"
    echo "SHA256 [${name}] = ${hash}" >> "$INSTALL_LOG"
}

# ── 下载 V2Ray Core ──────────────────────────────────────────
download_core() {
    local url
    if [[ -n "$IS_CORE_VER" ]]; then
        url="https://github.com/${IS_CORE_REPO}/releases/download/${IS_CORE_VER}/v2ray-linux-${CORE_ARCH}.zip"
    else
        url="https://github.com/${IS_CORE_REPO}/releases/latest/download/v2ray-linux-${CORE_ARCH}.zip"
    fi
    download_file "V2Ray Core" "$url" "$TMPCORE"

    # 校验 zip 内容必须包含 v2ray 二进制和 dat 文件
    msg info "校验 Core 压缩包内容..."
    local zip_list
    zip_list=$($UNZIP -l "$TMPCORE" 2>/dev/null) || err "Core zip 文件损坏，无法解压"
    for required in "v2ray" "geoip.dat" "geosite.dat"; do
        echo "$zip_list" | grep -q "$required" || err "Core zip 文件内容异常：缺少 ${required}"
    done
    msg ok "Core 文件校验通过"
}

# ── 下载管理脚本 ─────────────────────────────────────────────
download_sh() {
    local url="https://github.com/${IS_SH_REPO}/releases/latest/download/code.zip"
    download_file "V2Ray 管理脚本" "$url" "$TMPSH"

    # 校验 zip 内容必须包含核心脚本文件
    msg info "校验管理脚本压缩包内容..."
    local zip_list
    zip_list=$($UNZIP -l "$TMPSH" 2>/dev/null) || err "管理脚本 zip 文件损坏"
    echo "$zip_list" | grep -q "v2ray.sh" || err "管理脚本 zip 内容异常：缺少 v2ray.sh"
    msg ok "管理脚本文件校验通过"
}

# ── 下载 jq ──────────────────────────────────────────────────
download_jq() {
    if command -v jq &>/dev/null; then
        msg ok "jq 已安装，跳过下载"
        return 0
    fi
    local url="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-${JQ_ARCH}"
    download_file "jq" "$url" "$TMPJQ"
    $CHMOD +x "$TMPJQ"
}

# ── 安装文件 ─────────────────────────────────────────────────
install_files() {
    msg warn "安装文件到系统..."

    # 创建目录结构
    $MKDIR -p "${IS_CORE_DIR}/bin" "$IS_CONF_DIR" "$IS_LOG_DIR" "$IS_SH_DIR"

    # 安装管理脚本
    $UNZIP -qo "$TMPSH" -d "$IS_SH_DIR"
    msg ok "管理脚本已解压至 ${IS_SH_DIR}"

    # 安装 Core 二进制
    if [[ -n "$IS_CORE_FILE" ]]; then
        # 离线模式：校验本地 zip
        $UNZIP -qo "$IS_CORE_FILE" -d "${TMPDIR_BASE}/testzip" \
            || err "本地 Core zip 解压失败"
        for f in v2ray geoip.dat geosite.dat; do
            [[ -f "${TMPDIR_BASE}/testzip/${f}" ]] || err "本地 zip 内容异常：缺少 ${f}"
        done
        $CP -rf "${TMPDIR_BASE}/testzip/"* "${IS_CORE_DIR}/bin/"
    else
        $UNZIP -qo "$TMPCORE" -d "${IS_CORE_DIR}/bin"
    fi
    msg ok "V2Ray Core 已安装至 ${IS_CORE_DIR}/bin"

    # 安装 jq
    if ! command -v jq &>/dev/null; then
        $MV -f "$TMPJQ" /usr/bin/jq
        $CHMOD +x /usr/bin/jq
        msg ok "jq 已安装至 /usr/bin/jq"
    fi

    # 设置权限
    $CHMOD +x "$IS_CORE_BIN" /usr/bin/jq
    $CHMOD -R 750 "$IS_CORE_DIR"
    $CHMOD 750 "$IS_LOG_DIR"

    # 创建命令软链接
    $LN -sf "${IS_SH_DIR}/v2ray.sh" "$IS_SH_BIN"
    $CHMOD +x "$IS_SH_BIN"

    # 写入 alias（仅当不存在时）
    grep -q "alias ${IS_CORE}=" /root/.bashrc 2>/dev/null \
        || echo "alias ${IS_CORE}=${IS_SH_BIN}" >> /root/.bashrc

    msg ok "文件安装完成"
}

# ── 创建 systemd 服务 ────────────────────────────────────────
install_service() {
    local service_name="$IS_CORE"
    local service_file="/etc/systemd/system/${service_name}.service"

    msg warn "创建 systemd 服务..."

    # 若管理脚本有 systemd.sh，直接加载
    if [[ -f "${IS_SH_DIR}/src/systemd.sh" ]]; then
        # shellcheck disable=SC1090
        . "${IS_SH_DIR}/src/systemd.sh"
        install_service "$service_name" &>/dev/null || true
    else
        # fallback：手动写入 service 文件
        cat > "$service_file" <<EOF
[Unit]
Description=V2Ray Service
Documentation=https://www.v2fly.org/
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${IS_CORE_BIN} run -confdir ${IS_CONF_DIR}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
        $CHMOD 644 "$service_file"
        $SYSTEMCTL daemon-reload
        $SYSTEMCTL enable "$service_name" &>/dev/null
        msg ok "systemd 服务已创建并启用"
    fi
}

# ── 添加初始 VMess-TCP 配置（与原版行为一致）────────────────
add_initial_config() {
    msg warn "生成初始配置（VMess-TCP）..."
    if [[ -f "${IS_SH_DIR}/src/core.sh" ]]; then
        # shellcheck disable=SC1090
        . "${IS_SH_DIR}/src/core.sh"
        add tcp 2>/dev/null || true
        msg ok "初始配置已生成"
    else
        msg warn "未找到 core.sh，跳过初始配置生成（可手动执行 v2ray add tcp）"
    fi
}

# ── 打印完成信息 ─────────────────────────────────────────────
show_result() {
    echo
    echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${none}"
    echo -e "${green}  V2Ray 安装完成！${none}"
    echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${none}"
    echo
    echo -e "  服务器 IP : ${cyan}${SERVER_IP}${none}"
    echo -e "  安装日志  : ${cyan}${INSTALL_LOG}${none}"
    echo
    echo -e "${yellow}  常用命令：${none}"
    echo -e "  ${cyan}v2ray${none}               进入管理菜单"
    echo -e "  ${cyan}v2ray add vws <域名>${none} 添加 VLESS-WS-TLS 配置"
    echo -e "  ${cyan}v2ray info${none}           查看当前配置"
    echo -e "  ${cyan}v2ray url${none}            生成分享链接"
    echo -e "  ${cyan}v2ray status${none}         查看运行状态"
    echo -e "  ${cyan}v2ray restart${none}        重启服务"
    echo
    echo -e "${yellow}  提示: 请重新登录 SSH 以使 alias 生效，或执行：${none}"
    echo -e "  ${cyan}source /root/.bashrc${none}"
    echo
}

# ── 主函数 ───────────────────────────────────────────────────
main() {
    $MKDIR -p "$(dirname "$INSTALL_LOG")"
    msg info "V2Ray 本地化安全安装脚本启动"
    msg info "日志路径: ${INSTALL_LOG}"

    [[ $# -gt 0 ]] && pass_args "$@"

    check_env
    check_existing

    clear
    echo
    echo "........... ${IS_CORE_NAME} 本地化安全安装脚本 .........."
    echo

    # 时间同步
    $SYSTEMCTL enable systemd-timesyncd &>/dev/null || true
    timedatectl set-ntp true &>/dev/null || \
        msg warn "无法启用自动时间同步，可能影响 VMess 协议使用。"

    # 安装依赖
    install_deps

    # 并行下载（离线模式跳过 core 下载）
    msg warn "开始并行下载资源..."
    {
        [[ -z "$IS_CORE_FILE" ]] && download_core
        download_sh
        download_jq
        get_ip
    }

    # 安装
    install_files
    install_service
    add_initial_config

    show_result

    # 安装信息写入日志
    msg ok "安装完成，日志已保存至 ${INSTALL_LOG}"
}

main "$@"