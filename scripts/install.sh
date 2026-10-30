#!/bin/bash
# ============================================================
# Angie 国密版 - 一键离线安装脚本
# 用法：解压离线包后执行 bash install.sh
# 作者：老王不会写代码
# 日期：2026-10-30
# ============================================================
set -e

# ------------------------------------------------------------
# 安装目标路径
# ------------------------------------------------------------
PREFIX="/usr/local/angie"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "===== Angie 国密版离线安装 ====="
echo ""

# ------------------------------------------------------------
# 1. 拷贝 Angie 到目标路径
# ------------------------------------------------------------
if [ ! -d "${SCRIPT_DIR}/angie" ]; then
    echo "ERROR: 未找到 angie 目录，请确认离线包完整"
    exit 1
fi

if [ -d "${PREFIX}" ]; then
    echo "WARNING: ${PREFIX} 已存在，备份为 ${PREFIX}.bak.$(date +%Y%m%d%H%M%S)"
    mv "${PREFIX}" "${PREFIX}.bak.$(date +%Y%m%d%H%M%S)"
fi

cp -a "${SCRIPT_DIR}/angie" "${PREFIX}"
echo "OK: Angie 已安装到 ${PREFIX}"

# ------------------------------------------------------------
# 2. 拷贝配置文件
# ------------------------------------------------------------
if [ -f "${PREFIX}/conf/nginx.conf" ]; then
    echo "备份原有 nginx.conf"
    cp "${PREFIX}/conf/nginx.conf" "${PREFIX}/conf/nginx.conf.bak.$(date +%Y%m%d%H%M%S)"
fi
cp "${SCRIPT_DIR}/config/nginx.conf" "${PREFIX}/conf/"
cp "${SCRIPT_DIR}/config/guomi.conf" "${PREFIX}/conf/"
echo "OK: 配置文件已部署"

# ------------------------------------------------------------
# 3. 创建必要的目录
# ------------------------------------------------------------
mkdir -p "${PREFIX}/conf/cert/sm2" "${PREFIX}/conf/cert/rsa" \
         "${PREFIX}/logs" "${PREFIX}/html"

# ------------------------------------------------------------
# 4. 设置权限
# ------------------------------------------------------------
chmod +x "${PREFIX}/sbin/angie"
chmod 644 "${PREFIX}/conf/"*.conf 2>/dev/null || true
chmod 755 "${PREFIX}/conf/"
echo "OK: 权限已设置"

# ------------------------------------------------------------
# 5. 创建 systemd 服务（如果存在）
# ------------------------------------------------------------
if command -v systemctl &>/dev/null; then
    cat > /etc/systemd/system/angie.service << EOF
[Unit]
Description=Angie Web Server (国密版)
After=network.target

[Service]
Type=forking
PIDFile=${PREFIX}/logs/angie.pid
ExecStart=${PREFIX}/sbin/angie
ExecReload=${PREFIX}/sbin/angie -s reload
ExecStop=${PREFIX}/sbin/angie -s quit

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    echo "OK: systemd 服务已创建"
fi

# ------------------------------------------------------------
# 6. 验证安装
# ------------------------------------------------------------
echo ""
echo "===== 验证安装 ====="
${PREFIX}/sbin/angie -v 2>&1
${PREFIX}/sbin/angie -t 2>&1 || true

echo ""
echo "===== 安装完成 ====="
echo ""
echo "下一步："
echo "  1. 生成国密证书（需要 Tongsuo 编译的 openssl）"
echo "     bash scripts/03-gen-sm2-cert.sh"
echo "  2. 部署证书"
echo "     bash scripts/04-deploy-certs.sh"
echo "  3. 启动 Angie"
echo "     systemctl start angie  # 或：${PREFIX}/sbin/angie"
echo "  4. 测试验证"
echo "     bash scripts/05-verify.sh"
echo ""
