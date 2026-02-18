#!/usr/bin/env bash
# modules/base.sh — 基础系统工具包安装

MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$MODULES_DIR/.." && pwd)"

source "$BOOTSTRAP_DIR/lib/common.sh"

# ─── 包列表 ────────────────────────────────────────────────────────────────────
BASE_PACKAGES=(
  git curl wget vim tmux htop
  build-essential ca-certificates gnupg
  lsb-release ripgrep jq unzip
  software-properties-common
)

# ─── 检查 ──────────────────────────────────────────────────────────────────────
check_base() {
  local missing=0
  for cmd in git curl wget vim tmux ripgrep jq unzip; do
    # ripgrep 的二进制名为 rg
    local bin="$cmd"
    [[ "$cmd" == "ripgrep" ]] && bin="rg"
    check_command "$bin" || ((missing++))
  done
  [[ $missing -eq 0 ]]
}

# ─── 安装 ──────────────────────────────────────────────────────────────────────
install_base() {
  log_step "安装基础系统工具"

  if check_base; then
    log_success "基础工具已安装，跳过。"
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive

  log_info "更新软件包索引..."
  sudo apt-get update -qq

  log_info "升级已安装的软件包..."
  sudo apt-get upgrade -y -qq

  log_info "安装基础工具: ${BASE_PACKAGES[*]}"
  sudo apt-get install -y -qq "${BASE_PACKAGES[@]}"

  log_success "基础工具安装完成。"
}

# ─── 独立运行 ──────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  INIT_START=$(date +%s)
  trap 'echo ""; echo "[base.sh] 耗时: $(show_duration $INIT_START)"' EXIT
  check_ubuntu || exit 1
  ensure_sudo  || exit 1
  install_base
fi
