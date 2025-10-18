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

# 安装 mise (统一版本管理器)
echo "[4/6] 安装 mise 版本管理器..."
if ! command -v mise &> /dev/null; then
  # 安装 mise
  curl https://mise.run | sh
  
  # 配置环境变量
  export PATH="$HOME/.local/bin:$PATH"
  eval "$(~/.local/bin/mise activate bash)"
  
  # 为系统范围安装 mise
  if [[ ! -f /usr/local/bin/mise ]]; then
    cp ~/.local/bin/mise /usr/local/bin/mise
  fi
  
  echo "✓ mise 安装完成: $(mise --version)"
else
  echo "✓ mise 已安装: $(mise --version)"
fi

# 使用 mise 安装 Node.js 和 Python
echo "[5/6] 使用 mise 安装 Node.js 和 Python..."
export PATH="$HOME/.local/bin:$PATH"
eval "$(~/.local/bin/mise activate bash)"

# 安装 Node.js LTS
mise use -g node@lts
echo "✓ Node.js 安装完成: $(node --version)"
echo "✓ npm 版本: $(npm --version)"

# 安装 Python 3.12
mise use -g python@3.12
echo "✓ Python 安装完成: $(python --version)"
echo "✓ pip 版本: $(pip --version)"

# 升级 pip 和基础包
pip install --quiet --upgrade pip setuptools wheel

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

# 配置 mise 自动激活
echo 'eval "$(mise activate bash)"' >> /etc/bash.bashrc
if [[ -n "$DEFAULT_USER" ]] && [[ -f "/home/$DEFAULT_USER/.bashrc" ]]; then
  echo 'eval "$(mise activate bash)"' >> "/home/$DEFAULT_USER/.bashrc"
fi

# 安装 amix/vimrc 配置
echo "配置 Vim (amix/vimrc)..."
# 为 root 用户安装
if [[ ! -d ~/.vim_runtime ]]; then
  git clone --depth=1 https://github.com/amix/vimrc.git ~/.vim_runtime
  sh ~/.vim_runtime/install_awesome_vimrc.sh > /dev/null 2>&1
  echo "✓ Vim 配置完成 (root)"
fi

# 为默认用户安装
if [[ -n "$DEFAULT_USER" ]]; then
  sudo -u "$DEFAULT_USER" bash -c '
    if [[ ! -d ~/.vim_runtime ]]; then
      git clone --depth=1 https://github.com/amix/vimrc.git ~/.vim_runtime
      sh ~/.vim_runtime/install_awesome_vimrc.sh > /dev/null 2>&1
      echo "✓ Vim 配置完成 ('"$DEFAULT_USER"')"
    fi
  '
fi

# 配置 Git
echo "配置 Git..."
git config --global user.name "willliam.sang"
git config --global user.email "sang.williams@gmail.com"
git config --global init.defaultBranch main
git config --global core.editor vim

# 为默认用户配置 Git
if [[ -n "$DEFAULT_USER" ]]; then
  sudo -u "$DEFAULT_USER" bash -c '
    git config --global user.name "willliam.sang"
    git config --global user.email "sang.williams@gmail.com"
    git config --global init.defaultBranch main
    git config --global core.editor vim
  '
fi
echo "✓ Git 配置完成"

# 生成 SSH 密钥
echo "生成 SSH 密钥..."
# 为 root 用户生成
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  ssh-keygen -t ed25519 -C "gcp-dev-machine" -f ~/.ssh/id_ed25519 -N ""
  echo "✓ SSH 密钥生成完成 (root)"
  echo "  公钥位置: ~/.ssh/id_ed25519.pub"
fi

# 为默认用户生成
if [[ -n "$DEFAULT_USER" ]]; then
  sudo -u "$DEFAULT_USER" bash -c '
    if [[ ! -f ~/.ssh/id_ed25519 ]]; then
      mkdir -p ~/.ssh
      chmod 700 ~/.ssh
      ssh-keygen -t ed25519 -C "gcp-dev-machine" -f ~/.ssh/id_ed25519 -N ""
      echo "✓ SSH 密钥生成完成 ('"$DEFAULT_USER"')"
      echo "  公钥位置: ~/.ssh/id_ed25519.pub"
    fi
  '
fi

# 设置欢迎消息
cat > /etc/motd <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║            🛠️  GCE Builder 实例                              ║
╚══════════════════════════════════════════════════════════════╝

已安装的工具：
  • mise:    版本管理器 (node, python)
  • Docker:  $(docker --version 2>/dev/null || echo "未安装")
  • Node.js: $(node --version 2>/dev/null || echo "未安装")
  • Python:  $(python --version 2>/dev/null || echo "未安装")
  • Git:     $(git --version 2>/dev/null || echo "未安装")
  • Vim:     amix/vimrc (已配置)

工作目录: /workspace

Git 配置:
  • 用户名: willliam.sang
  • 邮箱:   sang.williams@gmail.com

SSH 密钥: ~/.ssh/id_ed25519.pub

mise 使用:
  • mise use node@20 python@3.11  # 设置项目版本
  • mise ls                       # 查看已安装版本
  • mise current                  # 查看当前版本

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
echo "  • mise:    $(mise --version)"
echo "  • Docker:  $(docker --version)"
echo "  • Node.js: $(node --version)"
echo "  • npm:     $(npm --version)"
echo "  • Python:  $(python --version)"
echo "  • Git:     $(git --version)"
echo "  • Vim:     amix/vimrc (已配置)"
echo ""
echo "Git 配置："
echo "  • 用户名: willliam.sang"
echo "  • 邮箱:   sang.williams@gmail.com"
echo ""
echo "SSH 密钥已生成："
if [[ -f ~/.ssh/id_ed25519.pub ]]; then
  echo "  Root 用户公钥:"
  echo "  $(cat ~/.ssh/id_ed25519.pub)"
fi
if [[ -n "$DEFAULT_USER" ]] && [[ -f "/home/$DEFAULT_USER/.ssh/id_ed25519.pub" ]]; then
  echo ""
  echo "  $DEFAULT_USER 用户公钥:"
  echo "  $(cat /home/$DEFAULT_USER/.ssh/id_ed25519.pub)"
fi
echo ""
echo "提示："
echo "  • mise 已配置为自动激活（重新登录后生效）"
echo "  • 如需手动添加配置，可以 SSH 进入实例"
echo "  • 配置完成后运行: sudo poweroff"
echo "  • 然后创建镜像: bash scripts/build-image.sh create-image"
echo ""

