#!/usr/bin/env bash
# remote-install.sh — 远程一键安装入口（curl | bash）
# 仅负责: 安装 git/curl → clone 仓库 → 启动 init-devbox.sh apply
# 本地已有仓库时请直接运行: bash bootstrap/init-devbox.sh apply
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/William-Sang/cloud-devbox/main/bootstrap/remote-install.sh | bash
#   curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/William-Sang/cloud-devbox/main/bootstrap/remote-install.sh | bash -s -- --region cn
set -euo pipefail

REPO_URL="https://github.com/William-Sang/cloud-devbox.git"
INSTALL_DIR="${HOME}/.local/share/init-devbox"
SCRIPT_NAME="remote-install.sh"

# ─── 解析 --region 和 --proxy 参数 ─────────────────────────────────────────────
REGION=""
PROXY=""
NEXT_IS=""
for arg in "$@"; do
  if [[ -n "$NEXT_IS" ]]; then
    case "$NEXT_IS" in
      region) REGION="$arg" ;;
      proxy)  PROXY="$arg" ;;
    esac
    NEXT_IS=""
    continue
  fi
  case "$arg" in
    --region=*) REGION="${arg#--region=}" ;;
    --region)   NEXT_IS="region" ;;
    --proxy=*)  PROXY="${arg#--proxy=}" ;;
    --proxy)    NEXT_IS="proxy" ;;
  esac
done

# 代理：export 环境变量，使后续 git clone / apt-get 也走代理
if [[ -n "$PROXY" ]]; then
  export HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY" ALL_PROXY="$PROXY"
  export http_proxy="$PROXY" https_proxy="$PROXY" all_proxy="$PROXY"
fi

# 中国区域：git clone 通过代理
if [[ "$REGION" == "cn" ]]; then
  REPO_URL="https://ghfast.top/https://github.com/William-Sang/cloud-devbox.git"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       init-devbox — Ubuntu 全栈开发环境初始化工具       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ─── 确保 git 和 curl 可用 ─────────────────────────────────────────────────────
for cmd in git curl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "[$SCRIPT_NAME] $cmd 未找到，正在安装..."
    sudo apt-get update -qq && sudo apt-get install -y -qq "$cmd"
  fi
done

# ─── 克隆或更新仓库 ────────────────────────────────────────────────────────────
if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "[$SCRIPT_NAME] 更新已有安装..."
  git -C "$INSTALL_DIR" pull --ff-only --quiet 2>/dev/null || {
    echo "[$SCRIPT_NAME] git pull 失败，重新克隆..."
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  }
else
  echo "[$SCRIPT_NAME] 下载 init-devbox..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

echo "[$SCRIPT_NAME] 安装目录: $INSTALL_DIR"
echo ""

# ─── 启动安装 ──────────────────────────────────────────────────────────────────
exec bash "$INSTALL_DIR/bootstrap/init-devbox.sh" apply "$@"
