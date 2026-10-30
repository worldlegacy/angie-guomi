#!/bin/bash
# ============================================================
# 证书部署脚本
# 将生成的证书拷贝到 Angie 配置目录
# 作者：老王不会写代码
# 日期：2026-10-30
# ============================================================

set -e

# 路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CERTS_DIR="${PROJECT_ROOT}/certs"
ANGIE_CONF="/usr/local/angie/conf"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# 主流程
main() {
    echo ""
    echo "============================================================"
    echo "  部署证书到 Angie 配置目录"
    echo "============================================================"
    echo ""

    if [ ! -d "${ANGIE_CONF}" ]; then
        error "Angie 配置目录不存在：${ANGIE_CONF}"
    fi

    # 备份原有证书目录
    if [ -d "${ANGIE_CONF}/cert" ]; then
        warn "发现已有 cert 目录，备份为 cert.bak"
        mv "${ANGIE_CONF}/cert" "${ANGIE_CONF}/cert.bak.$(date +%Y%m%d%H%M%S)"
    fi

    # 创建目标目录
    mkdir -p "${ANGIE_CONF}/cert/sm2" "${ANGIE_CONF}/cert/rsa"

    # 拷贝 SM2 双证书
    info "拷贝 SM2 双证书..."
    if [ -d "${CERTS_DIR}/sm2" ]; then
        cp -v "${CERTS_DIR}/sm2/server_sign.crt" "${ANGIE_CONF}/cert/sm2/"
        cp -v "${CERTS_DIR}/sm2/server_sign.key" "${ANGIE_CONF}/cert/sm2/"
        cp -v "${CERTS_DIR}/sm2/server_enc.crt"  "${ANGIE_CONF}/cert/sm2/"
        cp -v "${CERTS_DIR}/sm2/server_enc.key"  "${ANGIE_CONF}/cert/sm2/"
    fi

    # 拷贝 RSA 证书
    info "拷贝 RSA 证书..."
    if [ -d "${CERTS_DIR}/rsa" ]; then
        cp -v "${CERTS_DIR}/rsa/server_rsa.crt" "${ANGIE_CONF}/cert/rsa/"
        cp -v "${CERTS_DIR}/rsa/server_rsa.key" "${ANGIE_CONF}/cert/rsa/"
    fi

    # 拷贝 CA 证书链（如果存在）
    if [ -f "${CERTS_DIR}/ca/chain-ca.crt" ]; then
        info "拷贝 CA 证书链..."
        cp -v "${CERTS_DIR}/ca/chain-ca.crt" "${ANGIE_CONF}/cert/ca-chain.crt"
    fi

    # 设置权限（私钥权限 600）
    info "设置证书权限..."
    chmod 644 "${ANGIE_CONF}/cert/"**/*.crt 2>/dev/null || true
    chmod 600 "${ANGIE_CONF}/cert/"**/*.key 2>/dev/null || true

    echo ""
    info "✓ 证书部署完成！"
    info "证书目录：${ANGIE_CONF}/cert/"
    ls -laR "${ANGIE_CONF}/cert/"

    echo ""
    info "下一步："
    info "  1. 配置 Angie：编辑 ${ANGIE_CONF}/nginx.conf 或添加 guomi.conf"
    info "  2. 重载配置：/usr/local/angie/sbin/angie -t && /usr/local/angie/sbin/angie -s reload"
    echo ""
}

main "$@"
