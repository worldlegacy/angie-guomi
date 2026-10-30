#!/bin/bash
# ============================================================
# Angie 国密方案测试验证脚本
# 用途：验证 Angie 国密部署是否成功
# 作者：老王不会写代码
# 日期：2026-10-30
# ============================================================

set -e

# ------------------------------------------------------------
# 配置
# ------------------------------------------------------------
ANGIE_BIN="${ANGIE_BIN:-/usr/local/angie/sbin/angie}"
OPENSSL_BIN="${OPENSSL_BIN:-openssl}"
SERVER_HOST="${SERVER_HOST:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-443}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[PASS]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
step()  { echo -e "\n${BLUE}==== $* ====${NC}"; }

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

record_pass() { PASS_COUNT=$((PASS_COUNT + 1)); info "$1"; }
record_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); fail "$1"; }
record_warn() { WARN_COUNT=$((WARN_COUNT + 1)); warn "$1"; }

# ------------------------------------------------------------
# 1. 检查 Angie 安装
# ------------------------------------------------------------
test_angie_install() {
    step "检查 Angie 安装"

    if [ ! -x "${ANGIE_BIN}" ]; then
        record_fail "Angie 二进制不存在或不可执行：${ANGIE_BIN}"
        return 1
    fi

    record_pass "Angie 二进制存在：${ANGIE_BIN}"

    local version
    version=$(${ANGIE_BIN} -v 2>&1)
    record_pass "版本：${version}"

    # 检查编译参数中是否包含 NTLS/Tongsuo
    local build_info
    build_info=$(${ANGIE_BIN} -V 2>&1)

    if echo "${build_info}" | grep -qi "ntls\|tongsuo\|sm2"; then
        record_pass "编译参数包含国密支持（NTLS/Tongsuo/SM2）"
    else
        record_warn "编译参数中未检测到国密关键字，请确认是否正确编译"
    fi
}

# ------------------------------------------------------------
# 2. 检查配置文件
# ------------------------------------------------------------
test_config() {
    step "检查配置文件"

    # 检查配置语法
    if ${ANGIE_BIN} -t 2>&1; then
        record_pass "配置文件语法检查通过"
    else
        record_fail "配置文件语法错误"
        return 1
    fi
}

# ------------------------------------------------------------
# 3. 检查 Angie 运行状态
# ------------------------------------------------------------
test_angie_running() {
    step "检查 Angie 运行状态"

    if pgrep -x angie &>/dev/null; then
        record_pass "Angie 进程正在运行"
    else
        record_warn "Angie 未运行，尝试启动..."
        ${ANGIE_BIN} 2>/dev/null || record_fail "Angie 启动失败"
        sleep 1
        if pgrep -x angie &>/dev/null; then
            record_pass "Angie 启动成功"
        else
            record_fail "Angie 启动失败"
        fi
    fi
}

# ------------------------------------------------------------
# 4. 使用 OpenSSL 测试国密 NTLS 连接
# ------------------------------------------------------------
test_ntls_connection() {
    step "测试国密 NTLS 连接"

    # 检查 openssl 是否支持 NTLS
    if ! ${OPENSSL_BIN} version 2>/dev/null | grep -qi "tongsuo\|baba"; then
        record_warn "建议使用 Tongsuo 编译的 openssl 进行国密测试"
    fi

    # 测试 ECC-SM2-SM4-CBC-SM3 套件（静态密钥交换）
    echo "" | ${OPENSSL_BIN} s_client \
        -connect "${SERVER_HOST}:${SERVER_PORT}" \
        -cipher ECC-SM2-SM4-CBC-SM3 \
        -enable_ntls -ntls \
        -brief 2>&1 | tee /tmp/sm2_test1.log

    if grep -q "Verify return code\|verify return code" /tmp/sm2_test1.log; then
        if grep -q "ok\|0 (ok)" /tmp/sm2_test1.log; then
            record_pass "ECC-SM2-SM4-CBC-SM3 国密连接成功"
        else
            record_warn "国密连接返回了证书验证问题（自签名证书属正常情况）"
        fi
    elif grep -q "handshake failure\|error\|alert" /tmp/sm2_test1.log; then
        record_fail "ECC-SM2-SM4-CBC-SM3 国密握手失败"
    fi

    # 测试 ECDHE-SM2-WITH-SM4-SM3 套件（临时密钥交换，推荐）
    echo "" | ${OPENSSL_BIN} s_client \
        -connect "${SERVER_HOST}:${SERVER_PORT}" \
        -cipher ECDHE-SM2-WITH-SM4-SM3 \
        -enable_ntls -ntls \
        -brief 2>&1 | tee /tmp/sm2_test2.log

    if grep -q "Verify return code\|verify return code" /tmp/sm2_test2.log; then
        if grep -q "ok\|0 (ok)" /tmp/sm2_test2.log; then
            record_pass "ECDHE-SM2-WITH-SM4-SM3 国密连接成功"
        else
            record_warn "国密连接返回了证书验证问题"
        fi
    elif grep -q "handshake failure\|error\|alert" /tmp/sm2_test2.log; then
        record_fail "ECDHE-SM2-WITH-SM4-SM3 国密握手失败"
    fi
}

# ------------------------------------------------------------
# 5. 测试 RSA 连接（兼容性）
# ------------------------------------------------------------
test_rsa_connection() {
    step "测试 RSA 兼容连接"

    echo "" | ${OPENSSL_BIN} s_client \
        -connect "${SERVER_HOST}:${SERVER_PORT}" \
        -tls1_2 \
        -brief 2>&1 | tee /tmp/rsa_test.log

    if grep -q "Verify return code\|verify return code" /tmp/rsa_test.log; then
        if grep -q "ok\|0 (ok)" /tmp/rsa_test.log; then
            record_pass "RSA 兼容连接成功（TLS 1.2）"
        else
            record_warn "RSA 连接返回了证书验证问题"
        fi
    elif grep -q "handshake failure\|error\|alert" /tmp/rsa_test.log; then
        record_fail "RSA 兼容连接失败（请检查是否配置了 RSA 证书）"
    fi
}

# ------------------------------------------------------------
# 6. 使用 curl 测试 HTTP 访问
# ------------------------------------------------------------
test_http_access() {
    step "测试 HTTP 访问"

    # 测试 HTTPS（普通 TLS）
    if command -v curl &>/dev/null; then
        local http_code
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" "https://${SERVER_HOST}:${SERVER_PORT}/" 2>/dev/null || echo "000")

        if [ "${http_code}" != "000" ] && [ "${http_code}" != "" ]; then
            record_pass "HTTPS 访问成功，HTTP 状态码：${http_code}"
        else
            record_fail "HTTPS 访问失败"
        fi

        # 测试 HTTP 是否跳转
        local redirect_code
        redirect_code=$(curl -s -o /dev/null -w "%{http_code}" "http://${SERVER_HOST}:$((${SERVER_PORT} - 343))/" 2>/dev/null || echo "000")
        # 如果 80 端口在跑，会返回 301
        if [ "${redirect_code}" = "301" ] || [ "${redirect_code}" = "302" ]; then
            record_pass "HTTP 跳转到 HTTPS 正常"
        fi
    else
        record_warn "未安装 curl，跳过 HTTP 访问测试"
    fi
}

# ------------------------------------------------------------
# 7. 测试常见国密浏览器提示
# ------------------------------------------------------------
test_browser_hint() {
    step "国密浏览器提示"

    echo ""
    info "支持国密的浏览器："
    echo "  - 红莲花浏览器（国密版）"
    echo "  - 360 安全浏览器（国密版）"
    echo "  - 密信浏览器"
    echo "  - Chrome 浏览器 + 国密插件"
    echo ""
    info "测试方法："
    echo "  1. 在国密浏览器中访问 https://${SERVER_HOST}:${SERVER_PORT}"
    echo "  2. 查看地址栏是否显示国密标识"
    echo "  3. 打开 F12 开发者工具 -> Security 面板查看连接信息"
    echo ""
}

# ------------------------------------------------------------
# 汇总报告
# ------------------------------------------------------------
print_report() {
    echo ""
    echo "============================================================"
    echo "  测试报告"
    echo "============================================================"
    echo ""
    echo "  通过: ${GREEN}${PASS_COUNT}${NC}"
    echo "  警告: ${YELLOW}${WARN_COUNT}${NC}"
    echo "  失败: ${RED}${FAIL_COUNT}${NC}"
    echo ""

    if [ "${FAIL_COUNT}" -eq 0 ]; then
        if [ "${WARN_COUNT}" -eq 0 ]; then
            info "🎉 所有测试通过！国密部署完全正常"
        else
            warn "⚠️  测试完成，但有警告需要关注"
        fi
    else
        fail "❌ 测试失败，请检查上面的错误信息"
    fi

    echo ""
    echo "============================================================"
    echo "  详细日志保存在 /tmp/sm2_test*.log"
    echo "============================================================"
    echo ""
}

# ------------------------------------------------------------
# 主流程
# ------------------------------------------------------------
main() {
    echo ""
    echo "============================================================"
    echo "  Angie 国密方案测试验证"
    echo "============================================================"
    echo ""
    echo "  服务器：${SERVER_HOST}:${SERVER_PORT}"
    echo "  Angie： ${ANGIE_BIN}"
    echo "  OpenSSL：${OPENSSL_BIN}"
    echo ""

    test_angie_install
    test_config
    test_angie_running
    test_ntls_connection
    test_rsa_connection
    test_http_access
    test_browser_hint
    print_report
}

main "$@"
