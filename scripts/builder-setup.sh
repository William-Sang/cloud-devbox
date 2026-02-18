#!/usr/bin/env bash
# GCE Builder 实例自动化配置脚本
# 复用 bootstrap/ 模块安装开发环境，避免重复维护安装逻辑。
#
# 前置要求: 基础镜像需使用 Ubuntu（bootstrap/ 仅支持 Ubuntu）
#   在 .env 或 build-image.sh 中配置:
#     BASE_IMAGE_FAMILY=ubuntu-2404-lts-amd64
#     BASE_IMAGE_PROJECT=ubuntu-os-cloud
#
# 用法: sudo bash ~/builder-setup.sh

set -euo pipefail

# ─── 运行时长追踪 ──────────────────────────────────────────────────────────────
SCRIPT_START_TIME=$(date +%s)
SCRIPT_NAME=$(basename "$0")

cleanup_and_show_duration() {
  local exit_code=$?
  local end_time duration minutes seconds
  end_time=$(date +%s)
  duration=$((end_time - SCRIPT_START_TIME))
  minutes=$((duration / 60))
  seconds=$((duration % 60))

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
echo "开始配置 Builder 实例"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── GCE: 创建用户 + sudo ─────────────────────────────────────────────────────
TARGET_USER=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/builder-username" || echo "dev")

echo "配置目标用户: $TARGET_USER"

if ! id "$TARGET_USER" &>/dev/null; then
  echo "创建用户 $TARGET_USER..."
  useradd -m -s /bin/bash "$TARGET_USER"
  echo "✓ 用户已创建"
else
  echo "✓ 用户已存在: $TARGET_USER"
fi

echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$TARGET_USER"
chmod 0440 "/etc/sudoers.d/$TARGET_USER"
echo "✓ sudo 权限已配置（免密）"
echo ""

# ─── GCE: 从 metadata 读取可配置参数 ─────────────────────────────────────────
_meta() {
  curl -sf -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1" || echo "${2:-}"
}

REPO_URL=$(_meta "builder-repo-url" "https://github.com/William-Sang/cloud-devbox.git")
BUILDER_REGION=$(_meta "builder-region" "")
BUILDER_PROXY=$(_meta "builder-proxy" "")
GIT_USER_NAME=$(_meta "builder-git-name" "")
GIT_USER_EMAIL=$(_meta "builder-git-email" "")

# ─── 交互式配置（metadata 未设置时，终端下询问）─────────────────────────────
if [[ -t 0 ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  配置选项（直接回车使用默认值）"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # 区域
  if [[ -z "$BUILDER_REGION" ]]; then
    echo "  选择区域:"
    echo "    1) overseas — 海外（官方源，默认）"
    echo "    2) cn       — 中国大陆（国内镜像加速）"
    read -rp "  请选择 [1/2] (默认 1): " _region_choice
    case "$_region_choice" in
      2) BUILDER_REGION="cn" ;;
      *) BUILDER_REGION="overseas" ;;
    esac
  fi
  echo "  区域: $BUILDER_REGION"
  echo ""

  # 代理
  if [[ -z "$BUILDER_PROXY" ]]; then
    read -rp "  代理 URL（如 http://host:port，回车跳过）: " BUILDER_PROXY
  fi
  if [[ -n "$BUILDER_PROXY" ]]; then
    echo "  代理: $BUILDER_PROXY"
  else
    echo "  代理: 无"
  fi
  echo ""

  # Git 信息
  if [[ -z "$GIT_USER_NAME" ]]; then
    read -rp "  Git user.name（回车跳过）: " GIT_USER_NAME
  fi
  if [[ -z "$GIT_USER_EMAIL" && -n "$GIT_USER_NAME" ]]; then
    read -rp "  Git user.email: " GIT_USER_EMAIL
  fi
  if [[ -n "$GIT_USER_NAME" ]]; then
    echo "  Git: $GIT_USER_NAME <$GIT_USER_EMAIL>"
  else
    echo "  Git: 跳过（可稍后手动配置）"
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
fi

# 确保区域有默认值
BUILDER_REGION=${BUILDER_REGION:-overseas}

REPO_DIR="/tmp/cloud-devbox"

echo "[1/5] 准备 bootstrap 环境..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl    # 确保 git/curl 可用

rm -rf "$REPO_DIR"
git clone --depth=1 "$REPO_URL" "$REPO_DIR"
echo "✓ 仓库已克隆到 $REPO_DIR"
echo ""

echo "[2/5] 运行 bootstrap 安装开发环境..."
# bootstrap 以目标用户身份运行（内部按需 sudo）
BOOTSTRAP_ARGS=(--all --yes --non-interactive --region "$BUILDER_REGION")
if [[ -n "$BUILDER_PROXY" ]]; then
  BOOTSTRAP_ARGS+=(--proxy "$BUILDER_PROXY")
fi
sudo -u "$TARGET_USER" bash "$REPO_DIR/bootstrap/init-devbox.sh" apply \
  "${BOOTSTRAP_ARGS[@]}"
echo ""

# ─── GCE: 个性化配置 ──────────────────────────────────────────────────────────
echo "[3/5] 配置 Git 用户信息和 Vim..."

# Git 用户信息（从 metadata 读取，未配置则跳过）
if [[ -n "$GIT_USER_NAME" && -n "$GIT_USER_EMAIL" ]]; then
  sudo -u "$TARGET_USER" git config --global user.name "$GIT_USER_NAME"
  sudo -u "$TARGET_USER" git config --global user.email "$GIT_USER_EMAIL"
  echo "✓ Git 用户信息已配置: $GIT_USER_NAME <$GIT_USER_EMAIL>"
else
  echo "⚠ Git 用户信息未配置（metadata 中未设置 builder-git-name/builder-git-email）"
  echo "  可在镜像启动后手动配置: git config --global user.name/email"
fi

# Vim 配置 (amix/vimrc)
sudo -u "$TARGET_USER" bash -c '
  if [[ ! -d ~/.vim_runtime ]]; then
    git clone --depth=1 https://github.com/amix/vimrc.git ~/.vim_runtime
    sh ~/.vim_runtime/install_awesome_vimrc.sh > /dev/null 2>&1
    echo "✓ Vim 配置完成 (amix/vimrc)"
  fi
'
echo ""

# ─── GCE: SSH 目录 + 工作目录 ──────────────────────────────────────────────────
echo "[4/5] 配置工作目录..."

# 仅准备 .ssh 目录，密钥将在 VM 首次启动时生成（避免烤入镜像共享密钥）
sudo -u "$TARGET_USER" bash -c '
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
'

mkdir -p /workspace
chown "$TARGET_USER:$TARGET_USER" /workspace
chmod 755 /workspace
echo "✓ /workspace 目录已创建"

# MOTD
cat > /etc/motd <<EOF
╔══════════════════════════════════════════════════════════════╗
║            GCE Dev 开发实例                                  ║
╚══════════════════════════════════════════════════════════════╝

配置用户: $TARGET_USER

已安装工具 (由 init-devbox bootstrap 管理):
  • fnm:     Node.js 版本管理器
  • Node.js: LTS + pnpm + bun
  • uv:      Python 版本管理器
  • Python:  3.12 + 3.13
  • Docker:  $TARGET_USER 可直接使用 (无需 sudo)
  • AI 工具: Claude Code, OpenCode, Codex, Qoder, Gemini

工作目录: /workspace (属于 $TARGET_USER)
SSH 密钥: 首次启动时自动生成于 /home/$TARGET_USER/.ssh/id_ed25519

常用命令:
  • fnm use 22 / fnm install --lts    Node.js 版本切换
  • uv run / uv add / uv sync         Python 项目管理
  • pnpm add / bun add                包管理
  • claude / opencode / gemini        AI 编码助手

完成配置后：
  1. 测试环境: docker run hello-world
  2. 关闭实例: sudo poweroff
  3. 创建镜像: bash scripts/build-image.sh create-image
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
echo ""

# ─── 镜像缓存清理 ──────────────────────────────────────────────────────────────
echo "[5/5] 清理缓存和临时文件..."
echo ""

# APT
echo "  • 清理 APT 缓存..."
apt-get clean
apt-get autoremove -y -qq
rm -rf /var/lib/apt/lists/*

# npm / pnpm
echo "  • 清理 npm/pnpm 缓存..."
sudo -u "$TARGET_USER" bash -c 'npm cache clean --force 2>/dev/null || true'
sudo -u "$TARGET_USER" bash -c 'pnpm store prune 2>/dev/null || true'

# uv
echo "  • 清理 uv 缓存..."
sudo -u "$TARGET_USER" bash -c 'uv cache clean 2>/dev/null || true'

# bun
echo "  • 清理 bun 缓存..."
sudo -u "$TARGET_USER" bash -c 'rm -rf ~/.bun/install/cache 2>/dev/null || true'

# Docker
echo "  • 清理 Docker 缓存..."
docker system prune -af 2>/dev/null || true

# 临时文件和日志
echo "  • 清理系统临时文件..."
rm -rf /tmp/* 2>/dev/null || true
rm -rf /var/tmp/* 2>/dev/null || true
find /var/log -type f -name "*.log" -delete 2>/dev/null || true
find /var/log -type f -name "*.gz" -delete 2>/dev/null || true
find /var/log -type f -name "*.old" -delete 2>/dev/null || true
truncate -s 0 /var/log/lastlog 2>/dev/null || true
truncate -s 0 /var/log/wtmp 2>/dev/null || true
truncate -s 0 /var/log/btmp 2>/dev/null || true

# Shell 历史
echo "  • 清理 Shell 历史..."
rm -f ~/.bash_history 2>/dev/null || true
sudo -u "$TARGET_USER" bash -c 'rm -f ~/.bash_history 2>/dev/null || true'
history -c 2>/dev/null || true

# Vim runtime git 历史（保留文件，减小镜像体积）
if [[ -d "/home/$TARGET_USER/.vim_runtime/.git" ]]; then
  rm -rf "/home/$TARGET_USER/.vim_runtime/.git"
fi

# systemd journal
journalctl --vacuum-time=1d 2>/dev/null || true

# 用户缓存
rm -rf ~/.cache/* 2>/dev/null || true
sudo -u "$TARGET_USER" bash -c 'rm -rf ~/.cache/* 2>/dev/null || true'

# 清理临时克隆的仓库
rm -rf "$REPO_DIR"

echo "✓ 缓存清理完成"
echo ""

# ─── 完成 ──────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Builder 配置完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "配置用户: $TARGET_USER (sudo 免密)"
echo ""
echo "下一步："
echo "  1. 测试: docker run hello-world"
echo "  2. 关机: sudo poweroff"
echo "  3. 创建镜像: bash scripts/build-image.sh create-image"
echo ""
