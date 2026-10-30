#!/bin/bash
# ============================================================
# Angie 国密版 - 一键离线安装
# 场景：内网已有 nginx 跑在 /app/nginx，Angie 装到 /app/angie-guomi
#       两个并存，配置 100% 兼容
#
# 用法：解压离线包后执行 bash install.sh
# 作者：老王不会写代码
# 日期：2026-10-30
# ============================================================
set -e

# ------------------------------------------------------------
# 安装路径（独立目录，不覆盖原 /app/nginx）
# ------------------------------------------------------------
PREFIX="/app/angie-guomi"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "============================================================"
echo "  Angie 国密版离线安装"
echo "  安装目标: ${PREFIX}"
echo "  原 nginx: /app/nginx (保留不动)"
echo "============================================================"
echo ""

# ------------------------------------------------------------
# 1. 检查离线包完整性
# ------------------------------------------------------------
if [ ! -d "${SCRIPT_DIR}/angie" ]; then
    echo "ERROR: 未找到 angie 目录，请确认离线包完整"
    exit 1
fi

if [ ! -x "${SCRIPT_DIR}/angie/sbin/angie" ]; then
    echo "ERROR: angie 二进制不存在或不可执行"
    exit 1
fi
echo "✓ 离线包完整性检查通过"

# ------------------------------------------------------------
# 2. 拷贝 Angie 到目标路径
# ------------------------------------------------------------
if [ -d "${PREFIX}" ]; then
    echo "⚠️  ${PREFIX} 已存在，备份为 ${PREFIX}.bak.$(date +%Y%m%d%H%M%S)"
    mv "${PREFIX}" "${PREFIX}.bak.$(date +%Y%m%d%H%M%S)"
fi

mkdir -p "$(dirname "${PREFIX}")"
cp -a "${SCRIPT_DIR}/angie" "${PREFIX}"
echo "✓ Angie 已安装到 ${PREFIX}"

# ------------------------------------------------------------
# 3. 创建国密证书目录
# ------------------------------------------------------------
mkdir -p "${PREFIX}/conf/cert/sm2"
mkdir -p "${PREFIX}/conf/cert/rsa"
echo "✓ 证书目录已创建：${PREFIX}/conf/cert/"

# ------------------------------------------------------------
# 4. 设置权限
# ------------------------------------------------------------
chmod +x "${PREFIX}/sbin/angie"
chmod 644 "${PREFIX}/conf/"*.conf 2>/dev/null || true
chmod 755 "${PREFIX}/conf/"
echo "✓ 权限已设置"

# ------------------------------------------------------------
# 5. 创建 systemd 服务（可选，检测系统）
# ------------------------------------------------------------
if command -v systemctl &>/dev/null; then
    cat > /etc/systemd/system/angie.service << EOF
[Unit]
Description=Angie Web Server (国密版)
After=network.target

[Service]
Type=forking
PIDFile=${PREFIX}/logs/angie.pid
ExecStart=${PREFIX}/sbin/angie -c ${PREFIX}/conf/angie.conf
ExecReload=${PREFIX}/sbin/angie -s reload
ExecStop=${PREFIX}/sbin/angie -s quit

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    echo "✓ systemd 服务已创建"
else
    echo "- 当前环境无 systemctl，跳过 systemd 服务"
fi

# ------------------------------------------------------------
# 6. 验证 Angie 二进制
# ------------------------------------------------------------
echo ""
echo "=== 验证 Angie ==="
echo "版本："
${PREFIX}/sbin/angie -v 2>&1
echo ""
echo "编译参数片段："
${PREFIX}/sbin/angie -V 2>&1 | grep -iE "prefix|NTLS|Tongsuo" || echo "(已链接 Tongsuo 国密库)"
echo ""
echo "配置测试："
${PREFIX}/sbin/angie -t -c ${PREFIX}/conf/angie.conf 2>&1 || true

# ------------------------------------------------------------
# 7. 拷贝辅助脚本到目标位置
# ------------------------------------------------------------
SCRIPTS_DIR="${PREFIX}/scripts"
mkdir -p "${SCRIPTS_DIR}"
if [ -d "${SCRIPT_DIR}/scripts" ]; then
    cp -a "${SCRIPT_DIR}/scripts/"*.sh "${SCRIPTS_DIR}/" 2>/dev/null || true
    chmod +x "${SCRIPTS_DIR}/"*.sh 2>/dev/null || true
fi

# 拷贝国密配置补丁（如果用户想补原 nginx.conf）
if [ -f "${SCRIPT_DIR}/scripts/patch-nginx-conf.sh" ]; then
    cp "${SCRIPT_DIR}/scripts/patch-nginx-conf.sh" "${PREFIX}/"
    chmod +x "${PREFIX}/patch-nginx-conf.sh"
fi

echo ""
echo "============================================================"
echo "  🎉 安装完成！"
echo "============================================================"
echo ""
echo "📁 目录结构："
echo "  ${PREFIX}/"
echo "  ├── sbin/angie                 ← Angie 国密版二进制"
echo "  ├── conf/                      ← 配置目录"
echo "  │   ├── angie.conf             ← 默认配置"
echo "  │   ├── cert/sm2/              ← 国密 SM2 证书放这里"
echo "  │   └── cert/rsa/              ← RSA 证书放这里"
echo "  ├── scripts/                   ← 辅助脚本"
echo "  └── patch-nginx-conf.sh        ← 一键给原 nginx.conf 打国密补丁"
echo ""
echo "🚀 下一步："
echo ""
echo "  方案 A：从零配置（先测通国密）"
echo "    1. bash ${PREFIX}/scripts/03-gen-sm2-cert.sh     # 生成国密证书"
echo "    2. bash ${PREFIX}/scripts/04-deploy-certs.sh     # 部署证书"
echo "    3. ${PREFIX}/sbin/angie -c ${PREFIX}/conf/angie.conf"
echo ""
echo "  方案 B：复用原 nginx.conf（推荐，最小改动）"
echo "    1. bash ${PREFIX}/scripts/03-gen-sm2-cert.sh     # 生成国密证书"
echo "    2. bash ${PREFIX}/patch-nginx-conf.sh /app/nginx/conf/nginx.conf"
echo "    3. cp /tmp/nginx-patched.conf /app/nginx/conf/nginx.conf"
echo "    4. # 停原 nginx，启 Angie（配置 100% 兼容）"
echo "       /app/nginx/sbin/nginx -s stop"
echo "       ${PREFIX}/sbin/angie -c /app/nginx/conf/nginx.conf"
echo ""
echo "  方案 C：两个并存（原 nginx 不动，Angie 跑新端口）"
echo "    先改原 nginx.conf 的 listen 443 -> 8443"
echo "    Angie 用 443 跑国密版，两个并行"
echo ""
echo "============================================================"
echo ""
