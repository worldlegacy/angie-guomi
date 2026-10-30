#!/bin/bash
# ============================================================
# Angie + Tongsuo（铜锁）源码一键下载脚本
# 用途：在外网下载编译所需的源码包，用于内网编译部署
# 作者：老王不会写代码
# 日期：2026-10-30
# ============================================================

set -e

# ------------------------------------------------------------
# 版本配置（可按需修改）
# ------------------------------------------------------------
ANGIE_VERSION="1.12.4"
# Tongsuo 是铜锁的开源项目，GitHub 仓库：Tongsuo-Project/Tongsuo
TONGSUO_VERSION="8.5.0"

# ------------------------------------------------------------
# 下载目录（脚本所在目录的上两级 packages 目录）
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DOWNLOAD_DIR="${PROJECT_ROOT}/packages"

# 创建下载目录
mkdir -p "${DOWNLOAD_DIR}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ------------------------------------------------------------
# 检查必要的下载工具
# ------------------------------------------------------------
check_tools() {
    info "检查下载工具..."
    if command -v wget &>/dev/null; then
        DOWNLOADER="wget"
        info "使用 wget 下载"
    elif command -v curl &>/dev/null; then
        DOWNLOADER="curl"
        info "使用 curl 下载"
    else
        error "未找到 wget 或 curl，请先安装其中一个"
    fi
}

# ------------------------------------------------------------
# 下载函数
# ------------------------------------------------------------
download_file() {
    local url="$1"
    local filename="$2"
    local filepath="${DOWNLOAD_DIR}/${filename}"

    if [ -f "${filepath}" ]; then
        warn "文件已存在，跳过下载：${filename}"
        return 0
    fi

    info "下载：${filename}"
    info "URL: ${url}"

    if [ "${DOWNLOADER}" = "wget" ]; then
        wget -c -O "${filepath}" "${url}"
    else
        curl -fSL -o "${filepath}" "${url}"
    fi

    if [ $? -eq 0 ]; then
        info "✓ 下载成功：${filename}"
    else
        error "✗ 下载失败：${filename}"
    fi
}

# ------------------------------------------------------------
# 主流程
# ------------------------------------------------------------
main() {
    echo ""
    echo "============================================================"
    echo " Angie + Tongsuo（铜锁）源码下载脚本"
    echo " Angie 版本: ${ANGIE_VERSION}"
    echo " Tongsuo 版本: ${TONGSUO_VERSION}"
    echo " 下载目录: ${DOWNLOAD_DIR}"
    echo "============================================================"
    echo ""

    check_tools

    # ----------------------------------------------------------
    # 1. 下载 Angie 源码
    # ----------------------------------------------------------
    info "===== 开始下载 Angie 源码 ====="
    ANGIE_FILENAME="angie-${ANGIE_VERSION}.tar.gz"
    ANGIE_URL="https://download.angie.software/files/${ANGIE_FILENAME}"
    # 备用下载地址（GitHub）
    ANGIE_URL_FALLBACK="https://github.com/webserver-llc/angie/archive/refs/tags/Angie-${ANGIE_VERSION}.tar.gz"

    download_file "${ANGIE_URL}" "${ANGIE_FILENAME}" || \
        download_file "${ANGIE_URL_FALLBACK}" "${ANGIE_FILENAME}"

    # ----------------------------------------------------------
    # 2. 下载 Tongsuo（铜锁）源码
    # ----------------------------------------------------------
    info "===== 开始下载 Tongsuo（铜锁）源码 ====="
    TONGSUO_FILENAME="Tongsuo-${TONGSUO_VERSION}.tar.gz"
    TONGSUO_URL="https://github.com/Tongsuo-Project/Tongsuo/archive/refs/tags/${TONGSUO_VERSION}.tar.gz"

    download_file "${TONGSUO_URL}" "${TONGSUO_FILENAME}"

    # ----------------------------------------------------------
    # 3. 可选：下载 Tongsuo 测试用国密证书
    # ----------------------------------------------------------
    info "===== （可选）下载 Tongsuo 测试用国密证书 ====="
    CERTS_DIR="${PROJECT_ROOT}/certs/sm2/test-certs"
    mkdir -p "${CERTS_DIR}"

    # 测试证书列表（兼容 mac 自带 bash 3.x，不使用关联数组）
    CERT_BASE="https://raw.githubusercontent.com/Tongsuo-Project/Tongsuo/master/test/certs/sm2"
    CERT_NAMES="server_sign.crt server_sign.key server_enc.crt server_enc.key chain-ca.crt"

    for cert_name in ${CERT_NAMES}; do
        local_cert="${CERTS_DIR}/${cert_name}"
        if [ ! -f "${local_cert}" ]; then
            info "下载测试证书：${cert_name}"
            if [ "${DOWNLOADER}" = "wget" ]; then
                wget -q -O "${local_cert}" "${CERT_BASE}/${cert_name}" 2>/dev/null && \
                    info "  ✓ ${cert_name}" || warn "  ✗ ${cert_name}（可忽略）"
            else
                curl -sSL -o "${local_cert}" "${CERT_BASE}/${cert_name}" 2>/dev/null && \
                    info "  ✓ ${cert_name}" || warn "  ✗ ${cert_name}（可忽略）"
            fi
        else
            warn "  已存在，跳过：${cert_name}"
        fi
    done

    # ----------------------------------------------------------
    # 完成
    # ----------------------------------------------------------
    echo ""
    echo "============================================================"
    info "所有文件下载完成！"
    echo ""
    info "📦 源码包："
    ls -lh "${DOWNLOAD_DIR}/"*.tar.gz 2>/dev/null
    echo ""
    info "📜 测试证书（如果下载成功）："
    ls -lh "${CERTS_DIR}/"*.crt "${CERTS_DIR}/"*.key 2>/dev/null || true
    echo ""
    info "下一步："
    info "  1. 将整个项目目录拷贝到内网服务器"
    info "  2. 在内网服务器上执行：bash scripts/install/02-install.sh"
    echo "============================================================"
    echo ""
}

main "$@"
