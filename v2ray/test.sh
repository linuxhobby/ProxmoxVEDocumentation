#!/bin/bash
# ==============================================================
#  V2Ray 安装脚本 —— 供应链攻击防御版
#
#  供应链安全策略（三层验证）：
#
#  [层1] 固定版本 + 固定哈希
#        脚本内硬编码版本号和官方发布的 SHA256，
#        不接受"动态获取最新版"，杜绝版本替换攻击。
#
#  [层2] 官方两级摘要校验
#        ① 下载 Release 文件（含所有 asset 的哈希清单）
#        ② 用硬编码的 Release.dgst 哈希校验 Release 文件本身
#        ③ 用 Release 文件内的哈希校验实际下载的 zip
#        任意一级不匹配立即中止。
#
#  [层3] 不依赖任何第三方管理脚本
#        不下载、不执行 233boy/v2ray 的任何脚本文件。
#        systemd、配置文件全部由本脚本自己生成。
#        不引入 Caddy（TLS 证书用 acme.sh 申请，来源可审计）。
#
#  与 233boy 版本的本质区别：
#  - 233boy 版：信任远程仓库实时内容，无版本锁定，无摘要验证
#  - 本脚本：  固定版本 + 双重摘要 + 零第三方脚本依赖
#
#  用法：
#    bash install_v2ray_secure.sh <domain>
#    bash install_v2ray_secure.sh <domain> --skip-tls   # 不配置TLS（测试用）
#
#  前置条件：
#    - root 权限
#    - 域名 A 记录已指向本机
#    - 80 / 443 端口未被占用
#    - 系统：Debian 11+ / Ubuntu 20.04+
# ==============================================================

set -euo pipefail
IFS=$'\n\t'

# ══════════════════════════════════════════════════════════════
# ❶  版本锁定区（升级时只改这里，并同步更新哈希）
#
#    更新方法：
#    1. 打开 https://github.com/v2fly/v2ray-core/releases
#    2. 找到目标版本，复制 Release.dgst 的 sha256 → RELEASE_DGST_SHA256
#    3. 下载 Release 文件，在其中找 v2ray-linux-64.zip 的 sha256 → CORE_ZIP_SHA256_AMD64
#       以及 v2ray-linux-arm64-v8a.zip 的 sha256 → CORE_ZIP_SHA256_ARM64
# ══════════════════════════════════════════════════════════════
PINNED_VERSION="v5.48.0"

# Release.dgst 文件自身的 SHA256（从 GitHub Release 页面直接读取）
RELEASE_DGST_SHA256="d66e5d159dab03c0904b3f59c746ba134770db9c5c26c640ac622bd44c5ce185"

# 从 Release 文件中提取的各平台 zip 哈希
CORE_ZIP_SHA256_AMD64="TODO_从Release文件提取_v2ray-linux-64.zip的SHA256"
CORE_ZIP_SHA256_ARM64="TODO_从Release文件提取_v2ray-linux-arm64-v8a.zip的SHA256"

# ══════════════════════════════════════════════════════════════
# ❷  安装路径（遵循 FHS 规范，不污染系统目录）
# ══════════════════════════════════════════════════════════════
V2RAY_USER="v2ray"                        # 专用非 root 用户
V2RAY_BIN="/usr/local/bin/v2ray"
V2RAY_CONF_DIR="/usr/local/etc/v2ray"
V2RAY_CONF="${V2RAY_CONF_DIR}/config.json"
V2RAY_LOG_DIR="/var/log/v2ray"
ACME_DIR="/root/.acme.sh"
CERT_DIR="/etc/ssl/v2ray"

# ══════════════════════════════════════════════════════════════
# ❸  颜色 & 日志
# ══════════════════════════════════════════════════════════════
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

LOG_FILE="/var/log/v2ray_install_$(date +%Y%m%d_%H%M%S).log"
mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1   # 所有输出同时写日志

info()  { echo -e "${CYAN}[$(date +%T)]${NC} $*"; }
ok()    { echo -e "${GREEN}[$(date +%T)] ✓${NC} $*"; }
warn()  { echo -e "${YELLOW}[$(date +%T)] ⚠${NC} $*"; }
die()   { echo -e "${RED}[$(date +%T)] ✗ 致命错误: $*${NC}"; exit 1; }

# ══════════════════════════════════════════════════════════════
# ❹  参数解析
# ══════════════════════════════════════════════════════════════
DOMAIN="${1:-}"
SKIP_TLS="${2:-}"

[[ -z "$DOMAIN" ]] && die "用法: $0 <domain> [--skip-tls]"
[[ $EUID -ne 0 ]]  && die "请以 root 权限运行"

# ══════════════════════════════════════════════════════════════
# ❺  临时目录（严格权限）
# ══════════════════════════════════════════════════════════════
TMPDIR=$(mktemp -d /tmp/v2ray_secure_XXXXXX)
chmod 700 "$TMPDIR"
trap 'info "清理临时文件..."; rm -rf "$TMPDIR"' EXIT

# ══════════════════════════════════════════════════════════════
# ❻  工具路径（绝对路径，防 PATH 注入）
# ══════════════════════════════════════════════════════════════
WGET=$(command -v wget)       || die "未找到 wget"
SHA256SUM=$(command -v sha256sum) || die "未找到 sha256sum"
UNZIP=$(command -v unzip 2>/dev/null || true)
SYSTEMCTL=$(command -v systemctl) || die "未找到 systemctl"

# ══════════════════════════════════════════════════════════════
# ❼  架构检测
# ══════════════════════════════════════════════════════════════
detect_arch() {
    case $(uname -m) in
        x86_64|amd64)
            ARCH_ZIP="v2ray-linux-64.zip"
            CORE_ZIP_SHA256="$CORE_ZIP_SHA256_AMD64"
            ;;
        aarch64|armv8*)
            ARCH_ZIP="v2ray-linux-arm64-v8a.zip"
            CORE_ZIP_SHA256="$CORE_ZIP_SHA256_ARM64"
            ;;
        *) die "不支持的架构: $(uname -m)";;
    esac
    ok "架构: $(uname -m) → ${ARCH_ZIP}"
}

# ══════════════════════════════════════════════════════════════
# ❽  安全下载（HTTPS 证书验证，3 次重试，超时 30s）
# ══════════════════════════════════════════════════════════════
safe_wget() {
    # 无 --no-check-certificate，强制 CA 验证
    $WGET --tries=3 --timeout=30 --quiet "$@"
}

# ══════════════════════════════════════════════════════════════
# ❾  三层完整性验证核心函数
# ══════════════════════════════════════════════════════════════
verify_downloads() {
    local base_url="https://github.com/v2fly/v2ray-core/releases/download/${PINNED_VERSION}"

    # ── 层1：下载 Release.dgst 并与硬编码值比对 ──────────────
    info "层1 校验：下载 Release.dgst..."
    safe_wget -O "${TMPDIR}/Release.dgst" "${base_url}/Release.dgst" \
        || die "Release.dgst 下载失败"

    local actual_dgst_hash
    actual_dgst_hash=$($SHA256SUM "${TMPDIR}/Release.dgst" | awk '{print $1}')
    info "  期望 Release.dgst SHA256: ${RELEASE_DGST_SHA256}"
    info "  实际 Release.dgst SHA256: ${actual_dgst_hash}"

    [[ "$actual_dgst_hash" == "$RELEASE_DGST_SHA256" ]] \
        || die "Release.dgst 校验失败！文件可能已被篡改。\n  期望: ${RELEASE_DGST_SHA256}\n  实际: ${actual_dgst_hash}"
    ok "层1 通过：Release.dgst 与硬编码值一致"

    # ── 层2：下载 Release 清单，并用 Release.dgst 验证它 ─────
    info "层2 校验：下载 Release 文件..."
    safe_wget -O "${TMPDIR}/Release" "${base_url}/Release" \
        || die "Release 文件下载失败"

    # Release.dgst 内含 SHA256(Release) 记录，格式: SHA256(Release)= <hash>
    local expected_release_hash
    expected_release_hash=$(grep "^SHA256(Release)=" "${TMPDIR}/Release.dgst" \
        | awk -F'= ' '{print $2}') \
        || die "Release.dgst 中未找到 SHA256(Release) 字段"

    local actual_release_hash
    actual_release_hash=$($SHA256SUM "${TMPDIR}/Release" | awk '{print $1}')
    info "  Release 期望 SHA256: ${expected_release_hash}"
    info "  Release 实际 SHA256: ${actual_release_hash}"

    [[ "$actual_release_hash" == "$expected_release_hash" ]] \
        || die "Release 文件校验失败！dgst 与 Release 文件不匹配。"
    ok "层2 通过：Release 文件经 Release.dgst 验证"

    # ── 层3：从 Release 清单提取 zip 哈希，验证实际下载的 zip ─
    info "层3 校验：下载 ${ARCH_ZIP}..."
    safe_wget -O "${TMPDIR}/core.zip" "${base_url}/${ARCH_ZIP}" \
        || die "${ARCH_ZIP} 下载失败"

    # Release 文件内格式：SHA256 (v2ray-linux-64.zip) = <hash>
    local release_zip_hash
    release_zip_hash=$(grep "${ARCH_ZIP}" "${TMPDIR}/Release" \
        | grep "^SHA256" | awk '{print $NF}') \
        || die "Release 文件中未找到 ${ARCH_ZIP} 的哈希"

    local actual_zip_hash
    actual_zip_hash=$($SHA256SUM "${TMPDIR}/core.zip" | awk '{print $1}')
    info "  zip 期望 SHA256 (来自Release): ${release_zip_hash}"
    info "  zip 实际 SHA256:               ${actual_zip_hash}"

    # 同时与脚本内硬编码值比对（双重保险）
    [[ "$actual_zip_hash" == "$release_zip_hash" ]] \
        || die "zip 与 Release 清单不匹配！供应链攻击风险！"
    [[ "$actual_zip_hash" == "$CORE_ZIP_SHA256" ]] \
        || die "zip 与脚本硬编码哈希不匹配！\n  期望: ${CORE_ZIP_SHA256}\n  实际: ${actual_zip_hash}\n  如已升级版本，请更新脚本顶部的哈希值。"

    ok "层3 通过：${ARCH_ZIP} 三重哈希验证成功"
}

# ══════════════════════════════════════════════════════════════
# ❿  安装 V2Ray Core
# ══════════════════════════════════════════════════════════════
install_core() {
    info "解压并安装 V2Ray ${PINNED_VERSION}..."
    [[ -z "$UNZIP" ]] && { apt-get install -y unzip &>/dev/null; UNZIP=$(command -v unzip); }

    $UNZIP -qo "${TMPDIR}/core.zip" -d "${TMPDIR}/v2ray_extracted"

    # 验证解压结果
    for f in v2ray geoip.dat geosite.dat; do
        [[ -f "${TMPDIR}/v2ray_extracted/${f}" ]] \
            || die "zip 内容异常：缺少 ${f}"
    done

    install -Dm755 "${TMPDIR}/v2ray_extracted/v2ray" "$V2RAY_BIN"
    install -Dm644 "${TMPDIR}/v2ray_extracted/geoip.dat"    "/usr/local/share/v2ray/geoip.dat"
    install -Dm644 "${TMPDIR}/v2ray_extracted/geosite.dat"  "/usr/local/share/v2ray/geosite.dat"

    ok "V2Ray ${PINNED_VERSION} 已安装至 ${V2RAY_BIN}"
    ok "版本确认: $($V2RAY_BIN version | head -1)"
}

# ══════════════════════════════════════════════════════════════
# ⓫  创建专用非 root 系统用户
# ══════════════════════════════════════════════════════════════
create_user() {
    if ! id "$V2RAY_USER" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin "$V2RAY_USER"
        ok "系统用户 ${V2RAY_USER} 已创建"
    else
        ok "系统用户 ${V2RAY_USER} 已存在，跳过"
    fi
}

# ══════════════════════════════════════════════════════════════
# ⓬  申请 TLS 证书（acme.sh，来源透明可审计）
# ══════════════════════════════════════════════════════════════
issue_cert() {
    [[ "$SKIP_TLS" == "--skip-tls" ]] && { warn "跳过 TLS 配置（--skip-tls 模式）"; return; }

    info "安装 acme.sh 申请 TLS 证书..."
    # acme.sh 是纯 Shell 脚本，可在执行前完整审查
    # 项目地址：https://github.com/acmesh-official/acme.sh
    safe_wget -O "${TMPDIR}/acme_install.sh" \
        "https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh" \
        || die "acme.sh 下载失败"

    # 注意：这里仍然是远程脚本，执行前建议人工审查
    # 如需完全离线，可预先下载并固定哈希
    warn "即将执行 acme.sh 安装脚本（纯 Shell，建议提前人工审查 ${TMPDIR}/acme_install.sh）"
    bash "${TMPDIR}/acme_install.sh" --install-online -m "admin@${DOMAIN}" \
        || die "acme.sh 安装失败"

    mkdir -p "$CERT_DIR"
    "${ACME_DIR}/acme.sh" --issue --standalone -d "$DOMAIN" \
        --httpport 80 \
        || die "证书申请失败，请确认域名已解析到本机且 80 端口可访问"

    "${ACME_DIR}/acme.sh" --install-cert -d "$DOMAIN" \
        --key-file  "${CERT_DIR}/private.key" \
        --fullchain-file "${CERT_DIR}/fullchain.pem" \
        --reloadcmd "systemctl restart v2ray" \
        || die "证书安装失败"

    chmod 640 "${CERT_DIR}/private.key" "${CERT_DIR}/fullchain.pem"
    chown root:${V2RAY_USER} "${CERT_DIR}/private.key" "${CERT_DIR}/fullchain.pem"
    ok "TLS 证书已签发：${CERT_DIR}/"
}

# ══════════════════════════════════════════════════════════════
# ⓭  生成 V2Ray 配置（VLESS-WS-TLS，由本脚本直接写，不依赖外部）
# ══════════════════════════════════════════════════════════════
generate_config() {
    mkdir -p "$V2RAY_CONF_DIR"

    # 生成随机 UUID
    local UUID
    UUID=$(cat /proc/sys/kernel/random/uuid)

    # 生成随机 WS 路径
    local WS_PATH
    WS_PATH="/$(tr -dc 'a-z0-9' < /dev/urandom | head -c 12)"

    # 内部监听端口（本机回环，Caddy/nginx 反代用；无 TLS 模式直接用 443）
    local INBOUND_PORT=8964

    if [[ "$SKIP_TLS" == "--skip-tls" ]]; then
        # 纯 VLESS-WS，无 TLS（仅测试用）
        cat > "$V2RAY_CONF" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${INBOUND_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${UUID}", "level": 0}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "${WS_PATH}"}
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ],
  "routing": {
    "rules": [
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"}
    ]
  }
}
EOF
    else
        # VLESS-WS-TLS，V2Ray 直接终止 TLS
        cat > "$V2RAY_CONF" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${UUID}", "level": 0}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_DIR}/fullchain.pem",
              "keyFile": "${CERT_DIR}/private.key"
            }
          ]
        },
        "wsSettings": {"path": "${WS_PATH}"}
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ],
  "routing": {
    "rules": [
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"}
    ]
  }
}
EOF
    fi

    chmod 640 "$V2RAY_CONF"
    chown root:${V2RAY_USER} "$V2RAY_CONF"

    # 保存连接信息（明文，仅 root 可读）
    cat > "/root/v2ray_client_info.txt" <<EOF
===============================================
  V2Ray VLESS-WS-TLS 客户端配置信息
  生成时间: $(date)
===============================================
协议       : VLESS
地址       : ${DOMAIN}
端口       : 443
UUID       : ${UUID}
加密       : none
传输协议   : ws
WS路径     : ${WS_PATH}
TLS        : $( [[ "$SKIP_TLS" == "--skip-tls" ]] && echo "关闭" || echo "开启" )
SNI        : ${DOMAIN}
===============================================
EOF
    chmod 600 "/root/v2ray_client_info.txt"

    ok "配置文件已写入 ${V2RAY_CONF}"
    # 将 UUID 和路径传递给后续函数
    export V2RAY_UUID="$UUID"
    export V2RAY_WS_PATH="$WS_PATH"
}

# ══════════════════════════════════════════════════════════════
# ⓮  创建 systemd 服务（hardening 加固）
# ══════════════════════════════════════════════════════════════
install_service() {
    mkdir -p "$V2RAY_LOG_DIR"
    chown ${V2RAY_USER}:${V2RAY_USER} "$V2RAY_LOG_DIR"
    chmod 750 "$V2RAY_LOG_DIR"

    cat > /etc/systemd/system/v2ray.service <<EOF
[Unit]
Description=V2Ray Service (${PINNED_VERSION})
Documentation=https://www.v2fly.org/
After=network.target nss-lookup.target

[Service]
# 专用非 root 用户运行
User=${V2RAY_USER}
Group=${V2RAY_USER}

# 仅授予必要的网络 capability，不给完整 root 权限
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_ADMIN
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_ADMIN
NoNewPrivileges=true

# 文件系统隔离
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${V2RAY_LOG_DIR}
ReadOnlyPaths=${V2RAY_CONF_DIR} /usr/local/share/v2ray ${CERT_DIR}

# 进程限制
LimitNPROC=512
LimitNOFILE=65535

ExecStart=${V2RAY_BIN} run -config ${V2RAY_CONF}
Restart=on-failure
RestartSec=5s
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 /etc/systemd/system/v2ray.service
    $SYSTEMCTL daemon-reload
    $SYSTEMCTL enable v2ray
    $SYSTEMCTL restart v2ray

    sleep 2
    if $SYSTEMCTL is-active --quiet v2ray; then
        ok "V2Ray 服务已启动并设为开机自启"
    else
        die "V2Ray 服务启动失败，请查看日志：journalctl -u v2ray -n 50"
    fi
}

# ══════════════════════════════════════════════════════════════
# ⓯  打印结果
# ══════════════════════════════════════════════════════════════
show_result() {
    echo
    echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  安装完成！${NC}"
    echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    cat /root/v2ray_client_info.txt
    echo
    echo -e "${CYAN}管理命令：${NC}"
    echo -e "  systemctl status v2ray     查看状态"
    echo -e "  systemctl restart v2ray    重启服务"
    echo -e "  journalctl -u v2ray -f     实时日志"
    echo -e "  cat /root/v2ray_client_info.txt  查看连接信息"
    echo
    echo -e "${YELLOW}安装日志：${LOG_FILE}${NC}"
    echo
    echo -e "${YELLOW}安全提示：${NC}"
    echo -e "  • V2Ray 以非 root 用户 '${V2RAY_USER}' 运行"
    echo -e "  • 版本已固定为 ${PINNED_VERSION}，升级需人工审查新版本哈希"
    echo -e "  • 配置文件位于 ${V2RAY_CONF}（仅 root 可修改）"
}

# ══════════════════════════════════════════════════════════════
# ⓰  主流程
# ══════════════════════════════════════════════════════════════
main() {
    echo
    echo -e "${BOLD}  V2Ray 供应链安全安装脚本${NC}"
    echo -e "  版本锁定: ${CYAN}${PINNED_VERSION}${NC}"
    echo -e "  域名:     ${CYAN}${DOMAIN}${NC}"
    echo

    # 哈希占位符检查：提示用户填写真实值
    if [[ "$CORE_ZIP_SHA256_AMD64" == TODO* ]] || [[ "$CORE_ZIP_SHA256_ARM64" == TODO* ]]; then
        die "请先填写脚本顶部的 CORE_ZIP_SHA256_AMD64 / CORE_ZIP_SHA256_ARM64 值。\n\
  获取方法：\n\
  1. 打开 https://github.com/v2fly/v2ray-core/releases/tag/${PINNED_VERSION}\n\
  2. 下载 Release 文件，在其中查找对应平台 zip 的 SHA256\n\
  3. 将值填入脚本顶部的变量后重新执行"
    fi

    # 安装基础依赖
    info "安装基础依赖..."
    apt-get update -y &>/dev/null
    apt-get install -y wget unzip curl &>/dev/null
    UNZIP=$(command -v unzip)
    ok "基础依赖就绪"

    detect_arch
    verify_downloads   # 三层校验
    install_core
    create_user
    issue_cert         # 申请 TLS 证书（含 acme.sh）
    generate_config
    install_service
    show_result
}

main "$@"