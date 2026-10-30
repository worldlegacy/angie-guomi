#!/bin/bash
# ============================================================
# 一键：提交到 GitHub Actions 编译
# 步骤：git init -> commit -> push -> 等编译 -> 下载 artifact
# 作者：老王不会写代码
# 日期：2026-10-30
# ============================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo "============================================================"
echo "  Angie 国密版 - 提交 GitHub Actions 编译"
echo "============================================================"
echo ""

# ------------------------------------------------------------
# 1. 检查 git
# ------------------------------------------------------------
if ! command -v git &>/dev/null; then
    error "未找到 git，请先安装"
fi

# ------------------------------------------------------------
# 2. git init
# ------------------------------------------------------------
if [ ! -d ".git" ]; then
    info "初始化 git 仓库..."
    git init
else
    info "已有 git 仓库，跳过 init"
fi

# ------------------------------------------------------------
# 3. 写 .gitignore（排除源码包和测试证书）
# ------------------------------------------------------------
cat > .gitignore << 'EOF'
# 源码包（直接下载可能被墙，让 workflow 自己下）
/packages/*.tar.gz
/packages/*.zip
/packages/*.tgz

# 编译产物
/build/
/output/

# 临时文件
*.swp
*.swo
*~
.DS_Store
/tmp/

# 证书私钥（安全起见不要提交到公开仓库！）
/certs/ca/*.key
/certs/sm2/*.key
/certs/rsa/*.key
/certs/sm2/test-certs/*.key

# IDE
.idea/
.vscode/
EOF

# ------------------------------------------------------------
# 4. 确认远程仓库
# ------------------------------------------------------------
echo ""
info "当前 git remote："
git remote -v 2>/dev/null || echo "（无）"
echo ""

if git remote | grep -q origin; then
    info "已有 origin 远程，跳过添加"
else
    read -rp "请输入 GitHub 仓库地址（例如 https://github.com/你的名字/angie-guomi.git）: " REMOTE_URL
    if [ -z "${REMOTE_URL}" ]; then
        error "仓库地址不能为空"
    fi
    git remote add origin "${REMOTE_URL}"
fi

# ------------------------------------------------------------
# 5. commit（排除 .key 私钥文件，安全第一）
# ------------------------------------------------------------
info "添加文件到暂存区..."
git add -A

info "提交..."
git commit -m "feat: Angie 国密版项目初始化 + GitHub Actions 编译"

# ------------------------------------------------------------
# 6. 推送到 GitHub
# ------------------------------------------------------------
echo ""
info "推送到 GitHub..."
info "（如果失败，可能需要先在 GitHub 创建仓库）"
info ""

git branch -M main
git push -u origin main

if [ $? -eq 0 ]; then
    echo ""
    echo "============================================================"
    info "✅ 推送成功！"
    echo ""
    info "下一步："
    info "  1. 打开浏览器访问你的 GitHub 仓库"
    info "  2. 点击 Actions 标签页"
    info "  3. 等待 Build workflow 运行完成（约 3-5 分钟）"
    info "  4. 下载 artifact：angie-guomi-offline-linux-x86_64"
    info "  5. 解压到内网服务器，执行 bash install.sh"
    echo ""
    info "如果想再触发编译："
    info "  推新代码会自动触发，或在 Actions 页面点 Run workflow"
    echo "============================================================"
else
    echo ""
    warn "推送失败。可能的原因："
    warn "  1. GitHub 仓库还没创建"
    warn "  2. git credential 没配置（首次 push 需要登录）"
    warn "  3. 网络问题"
    echo ""
    info "手动推送命令："
    info "  git add -A && git commit -m 'init' && git push -u origin main"
    echo ""
fi
