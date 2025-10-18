#!/usr/bin/env bash
# GCE Builder 实例自动化配置脚本
# 此脚本会在 builder 实例创建时自动执行
# 根据需求自定义安装内容

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 开始配置 Builder 实例"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 更新系统
echo "[1/6] 更新系统包..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# 安装基础工具
echo "[2/6] 安装基础工具..."
apt-get install -y -qq \
  curl \
  wget \
  git \
  vim \
  tmux \
  htop \
  build-essential \
  ca-certificates \
  gnupg \
  lsb-release

# 安装 Docker
echo "[3/6] 安装 Docker..."
if ! command -v docker &> /dev/null; then
  # 添加 Docker 官方 GPG key
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  # 添加 Docker 仓库
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

  # 安装 Docker Engine
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # 启动 Docker 服务
  systemctl enable docker
  systemctl start docker

  echo "✓ Docker 安装完成: $(docker --version)"
else
  echo "✓ Docker 已安装: $(docker --version)"
fi

# 安装 Node.js (使用 NodeSource 仓库安装最新 LTS)
echo "[4/6] 安装 Node.js..."
if ! command -v node &> /dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  apt-get install -y -qq nodejs
  echo "✓ Node.js 安装完成: $(node --version)"
  echo "✓ npm 版本: $(npm --version)"
else
  echo "✓ Node.js 已安装: $(node --version)"
fi

# 安装 Python 和 pip
echo "[5/6] 安装 Python..."
apt-get install -y -qq \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev

echo "✓ Python 安装完成: $(python3 --version)"
echo "✓ pip 版本: $(pip3 --version)"

# 安装常用 Python 包
pip3 install --quiet --upgrade pip setuptools wheel

# 配置用户环境
echo "[6/6] 配置环境..."

# 创建工作目录
mkdir -p /workspace
chmod 755 /workspace

# 配置 Docker 权限（允许非 root 用户使用）
if getent group docker > /dev/null 2>&1; then
  # 获取默认用户（通常是创建实例时的用户）
  DEFAULT_USER=$(ls /home | head -n 1)
  if [[ -n "$DEFAULT_USER" ]]; then
    usermod -aG docker "$DEFAULT_USER" || true
  fi
fi

# 设置欢迎消息
cat > /etc/motd <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║            🛠️  GCE Builder 实例                              ║
╚══════════════════════════════════════════════════════════════╝

已安装的工具：
  • Docker:  $(docker --version 2>/dev/null || echo "未安装")
  • Node.js: $(node --version 2>/dev/null || echo "未安装")
  • Python:  $(python3 --version 2>/dev/null || echo "未安装")
  • Git:     $(git --version 2>/dev/null || echo "未安装")

工作目录: /workspace

完成配置后：
  1. 测试环境: docker run hello-world
  2. 关闭实例: sudo poweroff
  3. 创建镜像: bash scripts/build-image.sh create-image

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 自定义安装内容
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 在下面添加您需要的额外工具和配置

# 示例：安装 Go
# echo "安装 Go..."
# wget -q https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
# tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
# echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile

# 示例：安装 Rust
# echo "安装 Rust..."
# curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# 示例：安装特定的 Python 包
# echo "安装 Python 包..."
# pip3 install --quiet requests pandas numpy flask

# 示例：克隆常用的仓库
# echo "克隆仓库..."
# cd /workspace
# git clone https://github.com/your/repo.git

# 示例：配置 vim
# echo "配置 vim..."
# cat > ~/.vimrc <<'VIMRC'
# set number
# set expandtab
# set tabstop=2
# VIMRC

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Builder 配置完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "已安装："
echo "  • Docker:  $(docker --version)"
echo "  • Node.js: $(node --version)"
echo "  • npm:     $(npm --version)"
echo "  • Python:  $(python3 --version)"
echo "  • Git:     $(git --version)"
echo ""
echo "提示："
echo "  • 如需手动添加配置，可以 SSH 进入实例"
echo "  • 配置完成后运行: sudo poweroff"
echo "  • 然后创建镜像: bash scripts/build-image.sh create-image"
echo ""

