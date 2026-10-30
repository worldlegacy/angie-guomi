#!/bin/bash
# ============================================================
# Angie 国密方案一键部署脚本
# 整合：下载 + 编译 + 生成证书 + 部署证书 + 配置
# 作者：老王不会写代码
# 日期：2026-10-30
# ============================================================

set -e

# ------------------------------------------------------------
# 路径配置
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${BLUE}============================================================${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${BLUE}============================================================${NC}"; }

# ------------------------------------------------------------
# 显示帮助
# ------------------------------------------------------------
show_help() {
    cat << EOF
Angie 国密方案一键部署脚本

用法：
    $0 <步骤>

步骤：
    all          全部执行（下载 -> 编译 -> 证书 -> 配置 -> 测试）
    download     仅下载源码包
    install      仅编译安装 Angie
    certs        仅生成证书
    deploy       仅部署证书和配置文件
    config       仅复制配置文件
    test         仅运行测试验证
    help         显示此帮助信息

示例：
    $0 all              # 完整安装部署
    $0 download         # 仅下载源码（外网机器执行）
    $0 install          # 编译安装（内网机器执行）
    $0 certs            # 生成证书
    SERVER_HOST=gm.example.com $0 test   # 指定服务器测试
EOF
}

# ------------------------------------------------------------
# 主流程
# ------------------------------------------------------------
main() {
    local STEP="${1:-all}"

    # 给脚本添加执行权限
    chmod +x "${SCRIPT_DIR}/"download/*.sh "${SCRIPT_DIR}/"install/*.sh \
              "${SCRIPT_DIR}/"certs/*.sh "${SCRIPT_DIR}/"test/*.sh 2>/dev/null || true

    case "${STEP}" in
        download)
            step "步骤 1：下载源码包"
            bash "${SCRIPT_DIR}/download/01-download.sh"
            ;;
        install)
            step "步骤 2：编译安装 Angie"
            bash "${SCRIPT_DIR}/install/02-install.sh"
            ;;
        certs)
            step "步骤 3：生成国密证书"
            bash "${SCRIPT_DIR}/certs/03-gen-sm2-cert.sh"
            ;;
        deploy)
            step "步骤 4：部署证书到 Angie"
            bash "${SCRIPT_DIR}/certs/04-deploy-certs.sh"
            ;;
        config)
            step "步骤 5：部署配置文件"
            deploy_configs
            ;;
        test)
            step "步骤 6：测试验证"
            bash "${SCRIPT_DIR}/test/05-verify.sh"
            ;;
        all)
            step "步骤 1：下载源码包"
            bash "${SCRIPT_DIR}/download/01-download.sh"

            step "步骤 2：编译安装 Angie"
            bash "${SCRIPT_DIR}/install/02-install.sh"

            step "步骤 3：生成国密证书"
            bash "${SCRIPT_DIR}/certs/03-gen-sm2-cert.sh"

            step "步骤 4：部署证书到 Angie"
            bash "${SCRIPT_DIR}/certs/04-deploy-certs.sh"

            step "步骤 5：部署配置文件"
            deploy_configs

            step "步骤 6：测试验证"
            bash "${SCRIPT_DIR}/test/05-verify.sh"

            step "🎉 部署完成！"
            echo ""
            info "Angie 国密方案已部署完成"
            info "配置文件：/usr/local/angie/conf/nginx.conf"
            info "证书目录：/usr/local/angie/conf/cert/"
            info "启动命令：systemctl start angie"
            echo ""
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "未知步骤：${STEP}"
            show_help
            ;;
    esac
}

# ------------------------------------------------------------
# 部署配置文件
# ------------------------------------------------------------
deploy_configs() {
    local ANGIE_CONF="/usr/local/angie/conf"

    if [ ! -d "${ANGIE_CONF}" ]; then
        error "Angie 配置目录不存在：${ANGIE_CONF}"
    fi

    # 备份原配置
    if [ -f "${ANGIE_CONF}/nginx.conf" ]; then
        warn "备份原有 nginx.conf"
        cp "${ANGIE_CONF}/nginx.conf" "${ANGIE_CONF}/nginx.conf.bak.$(date +%Y%m%d%H%M%S)"
    fi

    # 复制新配置
    info "复制 nginx.conf..."
    cp "${PROJECT_ROOT}/config/nginx.conf" "${ANGIE_CONF}/nginx.conf"

    info "复制 guomi.conf..."
    cp "${PROJECT_ROOT}/config/guomi.conf" "${ANGIE_CONF}/guomi.conf"

    info "✓ 配置文件已部署"
}

main "$@"
