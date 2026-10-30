#!/bin/bash
# ============================================================
# 一键给原 nginx.conf 打国密补丁
# 场景：内网已有 /app/nginx/conf/nginx.conf，要在不破坏原配置的基础上加国密
#
# 用法：
#   bash patch-nginx-conf.sh [原 nginx.conf 路径] [输出文件路径]
#   示例：bash patch-nginx-conf.sh /app/nginx/conf/nginx.conf /tmp/nginx-patched.conf
#
# 作者：老王不会写代码
# 日期：2026-10-30
# ============================================================
set -e

# ------------------------------------------------------------
# 默认路径（按你的内网环境）
# ------------------------------------------------------------
NGINX_CONF="${1:-/app/nginx/conf/nginx.conf}"
OUTPUT="${2:-/tmp/nginx-patched.conf}"
BACKUP="${NGINX_CONF}.bak.$(date +%Y%m%d%H%M%S)"

# 国密证书路径（Angie 国密版的默认位置）
SM2_CERT_DIR="/app/angie-guomi/conf/cert/sm2"

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo "============================================================"
echo "  nginx.conf 国密补丁脚本"
echo "  原配置: ${NGINX_CONF}"
echo "  输出:   ${OUTPUT}"
echo "============================================================"
echo ""

# ------------------------------------------------------------
# 1. 检查原配置是否存在
# ------------------------------------------------------------
if [ ! -f "${NGINX_CONF}" ]; then
    error "原配置文件不存在：${NGINX_CONF}"
fi

info "✓ 原配置文件存在"

# ------------------------------------------------------------
# 2. 备份原配置
# ------------------------------------------------------------
cp -a "${NGINX_CONF}" "${BACKUP}"
info "✓ 已备份原配置到：${BACKUP}"

# ------------------------------------------------------------
# 3. 检查是否已经打过补丁
# ------------------------------------------------------------
if grep -q "ssl_ntls" "${NGINX_CONF}"; then
    warn "原配置已包含国密配置（ssl_ntls on），跳过补丁"
    warn "如需重新补丁，请先还原备份：cp ${BACKUP} ${NGINX_CONF}"
    exit 0
fi

# ------------------------------------------------------------
# 4. 注入国密配置到每个 server 块的 listen 443 ssl 后面
# ------------------------------------------------------------
info "正在注入国密配置..."

# 国密补丁内容
PATCH='
    # ============ 国密配置（自动注入）============
    ssl_ntls on;

    # 国密 SM2 双证书（签名 + 加密）
    ssl_certificate      /app/angie-guomi/conf/cert/sm2/server_sign.crt
                         /app/angie-guomi/conf/cert/sm2/server_enc.crt;
    ssl_certificate_key  /app/angie-guomi/conf/cert/sm2/server_sign.key
                         /app/angie-guomi/conf/cert/sm2/server_enc.key;

    # 国密密码套件（加在原 ssl_ciphers 前面）
    ssl_ciphers ECC-SM2-SM4-CBC-SM3:ECDHE-SM2-WITH-SM4-SM3:
    # ===============================================
'

# 用 Python 处理（比 sed 更可靠，能正确处理多行）
python3 << PYEOF
import re, sys

with open("${NGINX_CONF}", "r") as f:
    content = f.read()

# 统计处理了多少个 server 块
count = 0

# 找到每个 "listen ... ssl;" 行（在 server {} 块内），在后面插入国密配置
lines = content.split('\n')
new_lines = []
i = 0

# 先找所有 server 块的起止位置
in_server = False
server_depth = 0
server_listen_lines = []  # 每个 server 块里 listen ssl 的行号

while i < len(lines):
    line = lines[i]
    
    # 检测进入 server 块
    if re.match(r'^server\s*\{', line) or re.match(r'^\s+server\s*\{', line):
        in_server = True
        server_depth = 1
        i += 1
        new_lines.append(line)
        continue
    
    if in_server:
        # 检测 server 块里的 listen ssl
        if re.search(r'listen\s+\d+\s+ssl', line):
            server_listen_lines.append(len(new_lines))
            count += 1
        
        # 检测花括号深度
        opens = line.count('{')
        closes = line.count('}')
        server_depth += opens - closes
        if server_depth <= 0:
            in_server = False
    
    new_lines.append(line)
    i += 1

# 现在在每个 listen ssl 行后面插入补丁
# 从后往前插，避免行号变化
for idx in reversed(server_listen_lines):
    # 找到 listen ssl 这一行，在后面插入补丁
    insert_after = idx  # 就在 listen ssl 这一行后面
    
    # 构造补丁（去掉首尾空行）
    patch_lines = [
        '',
        '    # ============ 国密配置（自动注入）============',
        '    ssl_ntls on;',
        '',
        '    # 国密 SM2 双证书（签名 + 加密）',
        '    ssl_certificate      /app/angie-guomi/conf/cert/sm2/server_sign.crt',
        '                         /app/angie-guomi/conf/cert/sm2/server_enc.crt;',
        '    ssl_certificate_key  /app/angie-guomi/conf/cert/sm2/server_sign.key',
        '                         /app/angie-guomi/conf/cert/sm2/server_enc.key;',
        '',
        '    # 国密密码套件（加在原 ssl_ciphers 前面）',
        '    ssl_ciphers ECC-SM2-SM4-CBC-SM3:ECDHE-SM2-WITH-SM4-SM3:',
        '    # ===============================================',
        ''
    ]
    
    # 在 insert_after 后面插
    for j, pl in enumerate(patch_lines):
        new_lines.insert(insert_after + 1 + j, pl)

with open("${OUTPUT}", "w") as f:
    f.write('\n'.join(new_lines))

print(f"✓ 处理完成，共给 {count} 个 server 块注入了国密配置")
PYEOF

# ------------------------------------------------------------
# 5. 验证输出
# ------------------------------------------------------------
info "✓ 补丁已生成：${OUTPUT}"
echo ""
info "国密配置预览（diff）："
diff -u "${BACKUP}" "${OUTPUT}" 2>&1 | grep -A2 -B2 "国密\|ssl_ntls" || true

echo ""
echo "============================================================"
info "下一步："
echo "  1. 确认补丁内容正确"
echo "  2. 生成 SM2 国密证书：bash scripts/03-gen-sm2-cert.sh"
echo "  3. 部署证书：bash scripts/04-deploy-certs.sh"
echo "  4. 替换配置："
echo "     cp ${OUTPUT} ${NGINX_CONF}"
echo "  5. 用 Angie 替换 nginx（Angie 配置 100% 兼容）："
echo "     # 停原 nginx"
echo "     /app/nginx/sbin/nginx -s stop"
echo "     # 启动 Angie（同一配置文件）"
echo "     /app/angie-guomi/sbin/angie -c ${NGINX_CONF}"
echo "  6. 测试：openssl s_client -connect 域名:443 -cipher ECDHE-SM2-WITH-SM4-SM3 -enable_ntls -ntls"
echo ""
info "如果想回滚：cp ${BACKUP} ${NGINX_CONF} && /app/nginx/sbin/nginx"
echo "============================================================"
echo ""
