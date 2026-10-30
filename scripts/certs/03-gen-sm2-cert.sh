#!/bin/bash
# ============================================================
# SM2 国密双证书生成脚本
# 说明：国密协议使用"双证书"机制
#   - 签名证书（sign）：用于身份认证和数字签名
#   - 加密证书（enc）：用于密钥交换和数据加密
# 作者：老王不会写代码
# 日期：2026-10-30
# ============================================================

set -e

# ------------------------------------------------------------
# 路径配置
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CERTS_DIR="${PROJECT_ROOT}/certs"
SM2_DIR="${CERTS_DIR}/sm2"
CA_DIR="${CERTS_DIR}/ca"
RSA_DIR="${CERTS_DIR}/rsa"

# 默认使用 Tongsuo 编译的 openssl
OPENSSL_BIN="${OPENSSL_BIN:-openssl}"

# 证书有效期（天）
DAYS=3650

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
# 获取用户输入
# ------------------------------------------------------------
get_user_input() {
    echo ""
    echo "============================================================"
    echo "  SM2 国密双证书生成"
    echo "============================================================"
    echo ""

    # 域名
    read -rp "请输入域名（例如：guomi.example.com）: " DOMAIN
    if [ -z "${DOMAIN}" ]; then
        error "域名不能为空"
    fi

    # 组织信息
    read -rp "组织名称（O）[默认：Your Company]: " ORG
    ORG="${ORG:-Your Company}"

    read -rp "组织单位（OU）[默认：IT Dept]: " OU
    OU="${OU:-IT Dept}"

    read -rp "国家代码（C）[默认：CN]: " COUNTRY
    COUNTRY="${COUNTRY:-CN}"

    read -rp "省份（ST）[默认：Beijing]: " STATE
    STATE="${STATE:-Beijing}"

    read -rp "城市（L）[默认：Beijing]: " CITY
    CITY="${CITY:-Beijing}"

    # SM2 ID（国密协议中用于标识签名方，GM/T 0009 规范）
    read -rp "SM2 ID [默认：1234567812345678]: " SM2_ID
    SM2_ID="${SM2_ID:-1234567812345678}"

    echo ""
    info "证书信息确认："
    info "  域名: ${DOMAIN}"
    info "  组织: ${ORG} / ${OU}"
    info "  地点: ${COUNTRY} / ${STATE} / ${CITY}"
    info "  SM2 ID: ${SM2_ID}"
    info "  有效期: ${DAYS} 天"
    echo ""

    read -rp "确认生成？(y/N): " confirm
    if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then
        error "已取消"
    fi
}

# ------------------------------------------------------------
# 检查 OpenSSL 版本（必须支持 SM2）
# ------------------------------------------------------------
check_openssl() {
    step "检查 OpenSSL/Tongsuo"

    if ! command -v "${OPENSSL_BIN}" &>/dev/null; then
        error "未找到 openssl 命令：${OPENSSL_BIN}"
    fi

    local version
    version=$(${OPENSSL_BIN} version 2>&1)
    info "OpenSSL 版本：${version}"

    # 检查是否支持 SM2
    if ! ${OPENSSL_BIN} ecparam -list_curves 2>/dev/null | grep -q sm2; then
        warn "当前 OpenSSL 可能不支持 SM2 曲线"
        warn "请确认使用 Tongsuo 编译的 openssl"
        warn "Tongsuo 自带的 openssl 通常在 /usr/local/angie/openssl/bin/openssl"
        echo ""
        read -rp "是否继续？(y/N): " confirm
        if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then
            error "已取消"
        fi
    fi

    info "OpenSSL 检查通过 ✓"
}

# ------------------------------------------------------------
# 1. 生成自签名 CA 证书（SM2）
# ------------------------------------------------------------
gen_sm2_ca() {
    step "生成 SM2 自签名 CA 根证书"

    mkdir -p "${CA_DIR}"
    cd "${CA_DIR}"

    # CA 签名私钥（SM2 曲线）
    info "生成 CA 签名私钥..."
    ${OPENSSL_BIN} genpkey -algorithm ec \
        -pkeyopt ec_paramgen_curve:SM2 \
        -out ca_sign.key

    # CA 加密私钥（SM2 曲线）
    info "生成 CA 加密私钥..."
    ${OPENSSL_BIN} genpkey -algorithm ec \
        -pkeyopt ec_paramgen_curve:SM2 \
        -out ca_enc.key

    # 生成 CA 证书（自签名）
    info "生成 CA 根证书（自签名）..."

    # 创建临时 openssl 配置
    cat > ca_sm2.cnf << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = ${COUNTRY}
ST = ${STATE}
L = ${CITY}
O = ${ORG}
OU = ${OU}
CN = SM2 Root CA

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

    # CA 签名证书（自签名，10年有效）
    ${OPENSSL_BIN} req -new -x509 \
        -key ca_sign.key \
        -out ca_sign.crt \
        -days 3650 \
        -sm3 \
        -config ca_sm2.cnf \
        -sm2-id "${SM2_ID}" \
        -sigopt "sm2_id:${SM2_ID}"

    # CA 加密证书
    cat > ca_sm2_enc.cnf << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca_enc
prompt = no

[req_distinguished_name]
C = ${COUNTRY}
ST = ${STATE}
L = ${CITY}
O = ${ORG}
OU = ${OU}
CN = SM2 Root CA Enc

[v3_ca_enc]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, keyEncipherment, dataEncipherment, keyAgreement
EOF

    ${OPENSSL_BIN} req -new -x509 \
        -key ca_enc.key \
        -out ca_enc.crt \
        -days 3650 \
        -sm3 \
        -config ca_sm2_enc.cnf \
        -sm2-id "${SM2_ID}" \
        -sigopt "sm2_id:${SM2_ID}"

    # 合并 CA 链
    cat ca_sign.crt ca_enc.crt > chain-ca.crt

    # 清理临时文件
    rm -f ca_sm2.cnf ca_sm2_enc.cnf

    info "✓ SM2 CA 根证书生成完成"
    info "  CA 签名证书：${CA_DIR}/ca_sign.crt"
    info "  CA 加密证书：${CA_DIR}/ca_enc.crt"
}

# ------------------------------------------------------------
# 2. 生成服务端 SM2 双证书
# ------------------------------------------------------------
gen_sm2_server_certs() {
    step "生成服务端 SM2 双证书"

    mkdir -p "${SM2_DIR}"
    cd "${SM2_DIR}"

    # ----------------------------------------------------------
    # 2.1 服务端签名证书
    # ----------------------------------------------------------
    info "生成服务端签名私钥..."
    ${OPENSSL_BIN} genpkey -algorithm ec \
        -pkeyopt ec_paramgen_curve:SM2 \
        -out server_sign.key

    info "生成服务端签名 CSR..."

    cat > server_sign.cnf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = ${COUNTRY}
ST = ${STATE}
L = ${CITY}
O = ${ORG}
OU = ${OU}
CN = ${DOMAIN}

[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = www.${DOMAIN}
IP.1  = 127.0.0.1
EOF

    ${OPENSSL_BIN} req -new \
        -key server_sign.key \
        -out server_sign.csr \
        -config server_sign.cnf \
        -sm2-id "${SM2_ID}"

    info "签发服务端签名证书..."

    cat > sign_ext.cnf << EOF
[v3_sign]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = www.${DOMAIN}
IP.1  = 127.0.0.1
EOF

    ${OPENSSL_BIN} x509 -req \
        -in server_sign.csr \
        -CA "${CA_DIR}/ca_sign.crt" \
        -CAkey "${CA_DIR}/ca_sign.key" \
        -CAcreateserial \
        -out server_sign.crt \
        -days "${DAYS}" \
        -sm3 \
        -extensions v3_sign \
        -extfile sign_ext.cnf \
        -sm2-id "${SM2_ID}" \
        -sigopt "sm2_id:${SM2_ID}"

    # ----------------------------------------------------------
    # 2.2 服务端加密证书
    # ----------------------------------------------------------
    info "生成服务端加密私钥..."
    ${OPENSSL_BIN} genpkey -algorithm ec \
        -pkeyopt ec_paramgen_curve:SM2 \
        -out server_enc.key

    info "生成服务端加密 CSR..."

    cat > server_enc.cnf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req_enc
prompt = no

[req_distinguished_name]
C = ${COUNTRY}
ST = ${STATE}
L = ${CITY}
O = ${ORG}
OU = ${OU}
CN = ${DOMAIN}

[v3_req_enc]
keyUsage = critical, keyEncipherment, dataEncipherment, keyAgreement
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = www.${DOMAIN}
IP.1  = 127.0.0.1
EOF

    ${OPENSSL_BIN} req -new \
        -key server_enc.key \
        -out server_enc.csr \
        -config server_enc.cnf \
        -sm2-id "${SM2_ID}"

    info "签发服务端加密证书..."

    cat > enc_ext.cnf << EOF
[v3_enc]
basicConstraints = CA:FALSE
keyUsage = critical, keyEncipherment, dataEncipherment, keyAgreement
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = www.${DOMAIN}
IP.1  = 127.0.0.1
EOF

    ${OPENSSL_BIN} x509 -req \
        -in server_enc.csr \
        -CA "${CA_DIR}/ca_enc.crt" \
        -CAkey "${CA_DIR}/ca_enc.key" \
        -CAcreateserial \
        -out server_enc.crt \
        -days "${DAYS}" \
        -sm3 \
        -extensions v3_enc \
        -extfile enc_ext.cnf \
        -sm2-id "${SM2_ID}" \
        -sigopt "sm2_id:${SM2_ID}"

    # 清理临时文件
    rm -f *.csr *.cnf *_ext.cnf

    info "✓ 服务端 SM2 双证书生成完成"
}

# ------------------------------------------------------------
# 3. 生成 RSA 证书（兼容非国密客户端）
# ------------------------------------------------------------
gen_rsa_certs() {
    step "生成 RSA 证书（兼容非国密客户端）"

    mkdir -p "${RSA_DIR}"
    cd "${RSA_DIR}"

    info "生成 RSA 私钥（2048位）..."
    ${OPENSSL_BIN} genrsa -out server_rsa.key 2048

    info "生成 RSA 自签名证书..."

    cat > rsa.cnf << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = ${COUNTRY}
ST = ${STATE}
L = ${CITY}
O = ${ORG}
OU = ${OU}
CN = ${DOMAIN}

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = www.${DOMAIN}
IP.1  = 127.0.0.1
EOF

    ${OPENSSL_BIN} req -new -x509 \
        -key server_rsa.key \
        -out server_rsa.crt \
        -days "${DAYS}" \
        -config rsa.cnf

    rm -f rsa.cnf

    info "✓ RSA 证书生成完成"
}

# ------------------------------------------------------------
# 4. 验证证书
# ------------------------------------------------------------
verify_certs() {
    step "验证证书"

    cd "${PROJECT_ROOT}"

    echo ""
    info "SM2 签名证书信息："
    ${OPENSSL_BIN} x509 -in "${SM2_DIR}/server_sign.crt" -noout -subject -issuer -dates

    echo ""
    info "SM2 加密证书信息："
    ${OPENSSL_BIN} x509 -in "${SM2_DIR}/server_enc.crt" -noout -subject -issuer -dates

    echo ""
    info "RSA 证书信息："
    ${OPENSSL_BIN} x509 -in "${RSA_DIR}/server_rsa.crt" -noout -subject -issuer -dates

    echo ""
    info "验证 SM2 签名证书与私钥匹配："
    local cert_pubkey
    local key_pubkey
    cert_pubkey=$(${OPENSSL_BIN} x509 -in "${SM2_DIR}/server_sign.crt" -noout -pubkey 2>/dev/null | ${OPENSSL_BIN} pkey -pubin -outform PEM 2>/dev/null)
    key_pubkey=$(${OPENSSL_BIN} pkey -in "${SM2_DIR}/server_sign.key" -pubout 2>/dev/null)
    if [ "${cert_pubkey}" = "${key_pubkey}" ]; then
        info "  ✓ 签名证书与私钥匹配"
    else
        warn "  ✗ 签名证书与私钥不匹配！"
    fi
}

# ------------------------------------------------------------
# 主流程
# ------------------------------------------------------------
main() {
    # 创建目录
    mkdir -p "${SM2_DIR}" "${CA_DIR}" "${RSA_DIR}"

    get_user_input
    check_openssl
    gen_sm2_ca
    gen_sm2_server_certs
    gen_rsa_certs
    verify_certs

    echo ""
    echo "============================================================"
    info "🎉 所有证书生成完成！"
    echo ""
    info "证书文件结构："
    echo "  ${CERTS_DIR}/"
    echo "  ├── ca/"
    echo "  │   ├── ca_sign.crt    # CA 签名证书"
    echo "  │   ├── ca_sign.key    # CA 签名私钥（请妥善保管）"
    echo "  │   ├── ca_enc.crt     # CA 加密证书"
    echo "  │   ├── ca_enc.key     # CA 加密私钥（请妥善保管）"
    echo "  │   └── chain-ca.crt   # CA 证书链（用于客户端验证）"
    echo "  ├── sm2/"
    echo "  │   ├── server_sign.crt   # 服务端签名证书"
    echo "  │   ├── server_sign.key   # 服务端签名私钥"
    echo "  │   ├── server_enc.crt    # 服务端加密证书"
    echo "  │   └── server_enc.key    # 服务端加密私钥"
    echo "  └── rsa/"
    echo "      ├── server_rsa.crt    # RSA 证书（兼容非国密客户端）"
    echo "      └── server_rsa.key    # RSA 私钥"
    echo ""
    info "下一步："
    info "  部署证书到 Angie：bash scripts/certs/04-deploy-certs.sh"
    echo "============================================================"
    echo ""
}

main "$@"
