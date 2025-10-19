#!/usr/bin/env bash
# GCE Builder 实例自动化配置脚本
# 此脚本会在 builder 实例创建时自动执行
# 根据需求自定义安装内容

set -euo pipefail

# 记录脚本开始时间
SCRIPT_START_TIME=$(date +%s)
SCRIPT_NAME=$(basename "$0")

# 在脚本退出时显示运行时长
cleanup_and_show_duration() {
  local exit_code=$?
  local end_time=$(date +%s)
  local duration=$((end_time - SCRIPT_START_TIME))
  local minutes=$((duration / 60))
  local seconds=$((duration % 60))
  
  echo ""
  if [ $minutes -gt 0 ]; then
    echo "[$SCRIPT_NAME] 运行时长: ${minutes}m ${seconds}s"
  else
    echo "[$SCRIPT_NAME] 运行时长: ${seconds}s"
  fi
  
  exit $exit_code
}

trap cleanup_and_show_duration EXIT

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 开始配置 Builder 实例"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 从 metadata 获取目标用户名
TARGET_USER=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/builder-username" || echo "dev")

echo "配置目标用户: $TARGET_USER"
echo ""

# 创建用户（如果不存在）
if ! id "$TARGET_USER" &>/dev/null; then
  echo "创建用户 $TARGET_USER..."
  useradd -m -s /bin/bash "$TARGET_USER"
  echo "✓ 用户已创建"
else
  echo "✓ 用户已存在: $TARGET_USER"
fi

# 配置 sudo 权限（免密）
echo "配置 sudo 权限..."
echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$TARGET_USER
chmod 0440 /etc/sudoers.d/$TARGET_USER
echo "✓ sudo 权限已配置（免密）"
echo ""

# 更新系统
echo "[1/7] 更新系统包..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# 安装基础工具
echo "[2/7] 安装基础工具..."
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
echo "[3/7] 安装 Docker..."
if ! command -v docker &> /dev/null; then
  # 检测操作系统类型
  . /etc/os-release
  if [[ "$ID" == "ubuntu" ]]; then
    DOCKER_OS="ubuntu"
  elif [[ "$ID" == "debian" ]]; then
    DOCKER_OS="debian"
  else
    echo "⚠️  未识别的操作系统: $ID，尝试使用 ubuntu"
    DOCKER_OS="ubuntu"
  fi
  
  echo "检测到系统: $ID $VERSION_CODENAME"
  
  # 添加 Docker 官方 GPG key
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/${DOCKER_OS}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  # 添加 Docker 仓库
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DOCKER_OS} \
    $VERSION_CODENAME stable" | \
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
echo "[4/7] 安装 mise 版本管理器..."
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
echo "[5/7] 使用 mise 安装 Node.js 和 Python..."
export PATH="$HOME/.local/bin:$PATH"
eval "$(~/.local/bin/mise activate bash)"

# 安装 Node.js LTS
echo "  • 安装 Node.js LTS..."
mise use -g node@lts

# 更新 PATH 以包含 Node
export PATH="$(mise where node)/bin:$PATH"
echo "✓ Node.js 安装完成: $(node --version)"
echo "✓ npm 版本: $(npm --version)"

# 安装 Python 3.12
echo "  • 安装 Python 3.12..."
mise use -g python@3.12

# 更新 PATH 以包含 Python
export PATH="$(mise where python)/bin:$PATH"
echo "✓ Python 安装完成: $(python --version)"
echo "✓ pip 版本: $(pip --version)"

# 升级 pip 和基础包
pip install --quiet --upgrade pip setuptools wheel

# 配置用户环境
echo "[6/7] 配置 Docker 权限和环境..."

# 配置 Docker 权限（允许目标用户使用）
if getent group docker > /dev/null 2>&1; then
  usermod -aG docker "$TARGET_USER" || true
  echo "✓ $TARGET_USER 已添加到 docker 组"
fi

# 配置 mise 自动激活（全局和用户级别）
echo 'eval "$(mise activate bash)"' >> /etc/bash.bashrc
if [[ -f "/home/$TARGET_USER/.bashrc" ]]; then
  echo 'eval "$(mise activate bash)"' >> "/home/$TARGET_USER/.bashrc"
  echo "✓ mise 自动激活已配置"
fi

# 为目标用户安装 Node 和 Python
echo "为 $TARGET_USER 用户安装 Node.js 和 Python..."
sudo -u "$TARGET_USER" bash <<USERSCRIPT
  # 确保 mise 在 PATH 中
  export PATH="/usr/local/bin:\$PATH"
  
  # 配置 mise
  eval "\$(mise activate bash 2>/dev/null || true)"
  
  # 安装 Node 和 Python
  mise use --global node@lts 2>/dev/null || echo "  ⚠️  Node: 将使用 root 配置"
  mise use --global python@3.12 2>/dev/null || echo "  ⚠️  Python: 将使用 root 配置"
  
  echo "  ✓ $TARGET_USER 的 mise 配置完成"
USERSCRIPT

# 安装 amix/vimrc 配置
echo "[7/7] 配置 Git、SSH 和 Vim..."
echo "  • 配置 Vim (amix/vimrc)..."
# 为目标用户安装
sudo -u "$TARGET_USER" bash -c '
  if [[ ! -d ~/.vim_runtime ]]; then
    git clone --depth=1 https://github.com/amix/vimrc.git ~/.vim_runtime
    sh ~/.vim_runtime/install_awesome_vimrc.sh > /dev/null 2>&1
    echo "    ✓ Vim 配置完成"
  fi
'

# 配置 Git
echo "  • 配置 Git..."
sudo -u "$TARGET_USER" bash -c '
  git config --global user.name "willliam.sang"
  git config --global user.email "sang.williams@gmail.com"
  git config --global init.defaultBranch main
  git config --global core.editor vim
'
echo "    ✓ Git 配置完成"

# 生成 SSH 密钥
echo "  • 生成 SSH 密钥..."
sudo -u "$TARGET_USER" bash -c '
  if [[ ! -f ~/.ssh/id_ed25519 ]]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keygen -t ed25519 -C "gcp-dev-machine" -f ~/.ssh/id_ed25519 -N ""
    echo "    ✓ SSH 密钥已生成"
  fi
'

# 创建并配置工作目录
echo "  • 配置工作目录..."
mkdir -p /workspace
chown $TARGET_USER:$TARGET_USER /workspace
chmod 755 /workspace
echo "    ✓ /workspace 目录已创建并设置权限"

# 设置欢迎消息（注入用户名）
cat > /etc/motd <<EOF
╔══════════════════════════════════════════════════════════════╗
║            🛠️  GCE Builder 实例                              ║
╚══════════════════════════════════════════════════════════════╝

配置用户: $TARGET_USER

已安装的工具：
  • mise:    版本管理器 (node, python)
  • Docker:  已安装，$TARGET_USER 用户可直接使用
  • Node.js: LTS 版本
  • Python:  3.12
  • Git:     已配置
  • Vim:     amix/vimrc (已配置)

工作目录: /workspace (属于 $TARGET_USER)

Git 配置:
  • 用户名: willliam.sang
  • 邮箱:   sang.williams@gmail.com

SSH 密钥: /home/$TARGET_USER/.ssh/id_ed25519.pub

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
echo "[8/8] 清理缓存和临时文件..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. 清理 APT 包管理器缓存
echo "  • 清理 APT 缓存..."
apt-get clean
apt-get autoremove -y -qq
rm -rf /var/lib/apt/lists/*
echo "    ✓ APT 缓存已清理"

# 2. 清理 Python/pip 缓存
echo "  • 清理 pip 缓存..."
# 清理 root 用户的 pip 缓存
pip cache purge 2>/dev/null || true
rm -rf ~/.cache/pip 2>/dev/null || true
# 清理目标用户的 pip 缓存
sudo -u "$TARGET_USER" bash -c 'pip cache purge 2>/dev/null || true'
sudo -u "$TARGET_USER" bash -c 'rm -rf ~/.cache/pip 2>/dev/null || true'
echo "    ✓ pip 缓存已清理"

# 3. 清理 Node.js/npm 缓存
echo "  • 清理 npm 缓存..."
# 清理 root 用户的 npm 缓存
npm cache clean --force 2>/dev/null || true
# 清理目标用户的 npm 缓存
sudo -u "$TARGET_USER" bash -c 'npm cache clean --force 2>/dev/null || true'
echo "    ✓ npm 缓存已清理"

# 4. 清理 mise 缓存
echo "  • 清理 mise 缓存..."
# 清理 root 用户的 mise 缓存
rm -rf ~/.local/share/mise/downloads/* 2>/dev/null || true
rm -rf ~/.local/share/mise/installs/*/downloads 2>/dev/null || true
# 清理目标用户的 mise 缓存
sudo -u "$TARGET_USER" bash -c 'rm -rf ~/.local/share/mise/downloads/* 2>/dev/null || true'
sudo -u "$TARGET_USER" bash -c 'rm -rf ~/.local/share/mise/installs/*/downloads 2>/dev/null || true'
echo "    ✓ mise 缓存已清理"

# 5. 清理系统临时文件和日志
echo "  • 清理系统临时文件..."
rm -rf /tmp/* 2>/dev/null || true
rm -rf /var/tmp/* 2>/dev/null || true
# 清理日志但保留目录结构
find /var/log -type f -name "*.log" -delete 2>/dev/null || true
find /var/log -type f -name "*.gz" -delete 2>/dev/null || true
find /var/log -type f -name "*.old" -delete 2>/dev/null || true
truncate -s 0 /var/log/lastlog 2>/dev/null || true
truncate -s 0 /var/log/wtmp 2>/dev/null || true
truncate -s 0 /var/log/btmp 2>/dev/null || true
echo "    ✓ 临时文件和日志已清理"

# 6. 清理 Shell 历史
echo "  • 清理 Shell 历史..."
rm -f ~/.bash_history 2>/dev/null || true
sudo -u "$TARGET_USER" bash -c 'rm -f ~/.bash_history 2>/dev/null || true'
# 清空当前会话历史
history -c 2>/dev/null || true
echo "    ✓ Shell 历史已清理"

# 7. 清理 Git 仓库缓存（保留文件）
echo "  • 清理 Git 仓库缓存..."
# 清理 vim runtime 的 git 历史
if [[ -d ~/.vim_runtime/.git ]]; then
  rm -rf ~/.vim_runtime/.git
fi
if [[ -d /home/$TARGET_USER/.vim_runtime/.git ]]; then
  rm -rf /home/$TARGET_USER/.vim_runtime/.git
fi
echo "    ✓ Git 仓库缓存已清理"

# 8. 清理其他缓存
echo "  • 清理其他缓存..."
# 清理 Docker 构建缓存（如果有）
docker system prune -af 2>/dev/null || true
# 清理 systemd journal 日志
journalctl --vacuum-time=1d 2>/dev/null || true
# 清理用户缓存目录
rm -rf ~/.cache/* 2>/dev/null || true
sudo -u "$TARGET_USER" bash -c 'rm -rf ~/.cache/* 2>/dev/null || true'
echo "    ✓ 其他缓存已清理"

echo ""
echo "✅ 缓存清理完成，镜像已优化"
echo ""

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Builder 配置完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "配置用户: $TARGET_USER (sudo 权限已启用)"
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
if [[ -f "/home/$TARGET_USER/.ssh/id_ed25519.pub" ]]; then
  echo "  $TARGET_USER 用户公钥:"
  echo "  $(cat /home/$TARGET_USER/.ssh/id_ed25519.pub)"
fi
echo ""
echo "工作目录："
echo "  • /workspace (属于 $TARGET_USER:$TARGET_USER)"
echo ""
echo "提示："
echo "  • mise 已配置为自动激活（重新登录后生效）"
echo "  • 所有工具已为 $TARGET_USER 用户配置完成"
echo "  • Docker 可直接使用，无需 sudo"
echo "  • 如需手动添加配置，可以 SSH 进入实例"
echo "  • 配置完成后运行: sudo poweroff"
echo "  • 然后创建镜像: bash scripts/build-image.sh create-image"
echo ""

