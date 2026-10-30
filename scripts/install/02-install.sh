#!/bin/bash
# ============================================================
# Angie + Tongsuo（铜锁）编译安装脚本
# 用途：在内网服务器上编译安装支持国密的 Angie
# 系统：CentOS/RHEL/Ubuntu/Debian（需预装编译工具链）
# 作者：老王不会写代码
# 日期：2026-10-30
# ============================================================

set -e

# ------------------------------------------------------------
# 版本配置（需与下载脚本保持一致）
# ------------------------------------------------------------
ANGIE_VERSION="1.12.4"
TONGSUO_VERSION="8.5.0"

# ------------------------------------------------------------
# 路径配置
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PACKAGES_DIR="${PROJECT_ROOT}/packages"
INSTALL_PREFIX="/usr/local/angie"
BUILD_DIR="/tmp/angie-build"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "${BLUE}==== $* ====${NC}"; }

# ------------------------------------------------------------
# 1. 检查系统环境
# ------------------------------------------------------------
check_env() {
    step "检查系统环境"

    # 检查 root 权限
    if [ "$(id -u)" -ne 0 ]; then
        warn "建议使用 root 用户或 sudo 执行本脚本"
    fi

    # 检查必要的编译工具
    local tools=("gcc" "make" "tar")
    for tool in "${tools[@]}"; do
        if ! command -v "${tool}" &>/dev/null; then
            error "缺少编译工具：${tool}，请先安装 build-essential/gcc"
        fi
    done

    # 检查编译依赖库
    step "检查编译依赖库"
    local deps=("pcre" "zlib" "perl")
    local missing=()

    for dep in "${deps[@]}"; do
        case "${dep}" in
            pcre)
                if ! dpkg -l | grep -q libpcre3-dev 2>/dev/null && \
                   ! rpm -q pcre-devel &>/dev/null; then
                    missing+=("pcre-devel/libpcre3-dev")
                fi
                ;;
            zlib)
                if ! dpkg -l | grep -q zlib1g-dev 2>/dev/null && \
                   ! rpm -q zlib-devel &>/dev/null; then
                    missing+=("zlib-devel/zlib1g-dev")
                fi
                ;;
            perl)
                if ! command -v perl &>/dev/null; then
                    missing+=("perl")
                fi
                ;;
        esac
    done

    if [ ${#missing[@]} -gt 0 ]; then
        warn "缺少依赖库：${missing[*]}"
        echo ""
        info "Ubuntu/Debian 安装命令："
        info "  sudo apt-get install -y build-essential libpcre3-dev zlib1g-dev perl"
        info "CentOS/RHEL 安装命令："
        info "  sudo yum install -y gcc gcc-c++ make pcre-devel zlib-devel perl"
        echo ""
        read -p "是否继续编译？(y/N): " confirm
        if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then
            error "已取消安装"
        fi
    fi

    info "环境检查通过 ✓"
}

# ------------------------------------------------------------
# 2. 解压源码包
# ------------------------------------------------------------
extract_sources() {
    step "解压源码包"

    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    # 解压 Tongsuo
    if [ ! -d "Tongsuo-${TONGSUO_VERSION}" ]; then
        if [ -f "${PACKAGES_DIR}/Tongsuo-${TONGSUO_VERSION}.tar.gz" ]; then
            info "解压 Tongsuo-${TONGSUO_VERSION}.tar.gz"
            tar -xzf "${PACKAGES_DIR}/Tongsuo-${TONGSUO_VERSION}.tar.gz"
        else
            # GitHub tarball 格式
            info "解压 Tongsuo（从 GitHub 下载的可能是 -main 后缀）"
            tar -xzf "${PACKAGES_DIR}/Tongsuo-${TONGSUO_VERSION}.tar.gz" 2>/dev/null || \
            tar -xzf "${PACKAGES_DIR}/Tongsuo-${TONGSUO_VERSION:0:3}.tar.gz" 2>/dev/null || \
                error "未找到 Tongsuo 源码包，请确认 ${PACKAGES_DIR} 目录下有对应文件"
        fi
    else
        warn "Tongsuo 源码已解压，跳过"
    fi

    # 解压 Angie
    local angie_dir="angie-${ANGIE_VERSION}"
    if [ ! -d "${angie_dir}" ]; then
        info "解压 angie-${ANGIE_VERSION}.tar.gz"
        if [ -f "${PACKAGES_DIR}/angie-${ANGIE_VERSION}.tar.gz" ]; then
            tar -xzf "${PACKAGES_DIR}/angie-${ANGIE_VERSION}.tar.gz"
        else
            # 尝试 GitHub tarball 格式
            tar -xzf "${PACKAGES_DIR}/angie-${ANGIE_VERSION}.tar.gz" 2>/dev/null || \
                error "未找到 Angie 源码包"
        fi
    else
        warn "Angie 源码已解压，跳过"
    fi

    info "源码解压完成 ✓"
}

# ------------------------------------------------------------
# 3. 查找实际目录名（GitHub tarball 可能带分支名）
# ------------------------------------------------------------
find_real_dir() {
    local base_name="$1"
    local found_dir

    # 精确匹配
    found_dir=$(find "${BUILD_DIR}" -maxdepth 1 -type d -name "${base_name}*" | head -1)

    if [ -z "${found_dir}" ]; then
        error "未找到 ${base_name} 源码目录"
    fi

    echo "${found_dir}"
}

# ------------------------------------------------------------
# 4. 编译安装 Angie（链接 Tongsuo 铜锁）
# ------------------------------------------------------------
compile_install() {
    step "编译安装 Angie（链接 Tongsuo 铜锁）"

    cd "${BUILD_DIR}"

    local TONGSUO_SRC
    TONGSUO_SRC=$(find_real_dir "Tongsuo")

    local ANGIE_SRC
    ANGIE_SRC=$(find_real_dir "angie")

    info "Tongsuo 源码目录：${TONGSUO_SRC}"
    info "Angie 源码目录：${ANGIE_SRC}"

    cd "${ANGIE_SRC}"

    # 生成配置参数
    step "执行 ./configure"

    ./configure \
        --prefix="${INSTALL_PREFIX}" \
        --with-openssl="${TONGSUO_SRC}" \
        --with-openssl-opt="enable-ntls" \
        --with-ntls \
        --with-http_ssl_module \
        --with-stream_ssl_module \
        --with-http_v2_module \
        --with-http_stub_status_module \
        --with-http_realip_module \
        --with-pcre \
        --with-zlib \
        --with-compat

    if [ $? -ne 0 ]; then
        error "./configure 执行失败，请检查错误信息"
    fi

    step "执行 make -j$(nproc 2>/dev/null || echo 2)"
    make -j"$(nproc 2>/dev/null || echo 2)"

    if [ $? -ne 0 ]; then
        error "make 编译失败"
    fi

    step "执行 make install"
    make install

    if [ $? -ne 0 ]; then
        error "make install 安装失败"
    fi

    info "Angie 安装完成 ✓"
}

# ------------------------------------------------------------
# 5. 创建系统服务
# ------------------------------------------------------------
create_service() {
    step "创建 Systemd 服务"

    local service_file="/etc/systemd/system/angie.service"

    if [ -f "${service_file}" ]; then
        warn "服务文件已存在，跳过创建"
        return 0
    fi

    cat > "${service_file}" << 'EOF'
[Unit]
Description=Angie Web Server
After=network.target

[Service]
Type=forking
PIDFile=/usr/local/angie/logs/angie.pid
ExecStart=/usr/local/angie/sbin/angie
ExecReload=/usr/local/angie/sbin/angie -s reload
ExecStop=/usr/local/angie/sbin/angie -s quit
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    info "服务文件已创建：${service_file}"

    # 重载 systemd
    systemctl daemon-reload

    info "✓ systemd 服务已创建"
}

# ------------------------------------------------------------
# 6. 验证安装
# ------------------------------------------------------------
verify_install() {
    step "验证安装"

    echo ""
    info "Angie 版本信息："
    "${INSTALL_PREFIX}/sbin/angie" -v 2>&1 || true

    echo ""
    info "编译参数（检查是否包含 NTLS/Tongsuo）："
    "${INSTALL_PREFIX}/sbin/angie" -V 2>&1 | head -20

    echo ""
    info "测试配置文件："
    "${INSTALL_PREFIX}/sbin/angie" -t 2>&1 || true

    echo ""
    info "启动 Angie 服务："
    systemctl start angie 2>/dev/null || "${INSTALL_PREFIX}/sbin/angie"
    sleep 1

    if pgrep -x angie &>/dev/null; then
        info "✓ Angie 已成功启动"
    else
        warn "Angie 可能未启动，请手动检查"
    fi
}

# ------------------------------------------------------------
# 主流程
# ------------------------------------------------------------
main() {
    echo ""
    echo "============================================================"
    echo " Angie + Tongsuo（铜锁）编译安装脚本"
    echo " Angie 版本: ${ANGIE_VERSION}"
    echo " Tongsuo 版本: ${TONGSUO_VERSION}"
    echo " 安装路径: ${INSTALL_PREFIX}"
    echo "============================================================"
    echo ""

    check_env
    extract_sources
    compile_install
    create_service
    verify_install

    echo ""
    echo "============================================================"
    info "🎉 Angie 国密版安装完成！"
    echo ""
    info "常用命令："
    info "  systemctl start angie      # 启动"
    info "  systemctl stop angie       # 停止"
    info "  systemctl restart angie    # 重启"
    info "  systemctl reload angie     # 重载配置"
    info "  systemctl status angie     # 查看状态"
    echo ""
    info "下一步："
    info "  1. 生成国密证书：bash scripts/certs/03-gen-sm2-cert.sh"
    info "  2. 部署配置文件：cp config/guomi.conf /usr/local/angie/conf/"
    echo "============================================================"
    echo ""
}

main "$@"
