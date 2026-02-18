#!/usr/bin/env bash
# modules/node.sh — Node.js 生态安装（fnm + Node LTS + pnpm + bun）

MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$MODULES_DIR/.." && pwd)"

source "$BOOTSTRAP_DIR/lib/common.sh"
source "$BOOTSTRAP_DIR/lib/region.sh"

# ─── 检查 ──────────────────────────────────────────────────────────────────────
check_node() {
  check_command fnm && check_command node
}

# ─── 安装 ──────────────────────────────────────────────────────────────────────
install_node() {
  log_step "安装 Node.js 生态 (fnm + Node LTS + pnpm + bun)"

  # ── fnm ──────────────────────────────────────────────────────────────────────
  if check_command fnm; then
    log_success "fnm 已安装: $(fnm --version)"
  else
    log_info "安装 fnm..."

    local arch
    arch=$(uname -m)
    case "$arch" in
      x86_64)  arch="linux" ;;
      aarch64) arch="arm64" ;;
      *) log_error "不支持的 CPU 架构: $arch"; return 1 ;;
    esac
    local fnm_url="https://github.com/Schniz/fnm/releases/latest/download/fnm-${arch}.zip"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    github_download "$fnm_url" "$tmp_dir/fnm.zip" || { rm -rf "$tmp_dir"; return 1; }
    unzip -q "$tmp_dir/fnm.zip" -d "$tmp_dir"
    mkdir -p "${HOME}/.local/share/fnm"
    mv "$tmp_dir/fnm" "${HOME}/.local/share/fnm/fnm"
    chmod +x "${HOME}/.local/share/fnm/fnm"
    rm -rf "$tmp_dir"

    # fnm 安装到 ~/.local/share/fnm
    export PATH="${HOME}/.local/share/fnm:${PATH}"

    add_to_bashrc "FNM_SETUP" \
      '# fnm — Fast Node Manager' \
      'export PATH="${HOME}/.local/share/fnm:${PATH}"' \
      'eval "$(fnm env --use-on-cd --shell bash)"'

    log_success "fnm 安装完成: $(fnm --version)"
  fi

  # 激活 fnm（当前 session）
  eval "$(fnm env --use-on-cd --shell bash 2>/dev/null || true)"

  # ── Node.js LTS ─────────────────────────────────────────────────────────────
  local node_lts
  node_lts=$(config_get "node.lts" "" 2>/dev/null || echo "")

  if check_command node; then
    log_success "Node.js 已安装: $(node --version)"
  else
    # 中国区域: 使用 npmmirror 的 Node 分发镜像
    if [[ -n "$MIRROR_FNM_NODE_DIST" ]]; then
      export FNM_NODE_DIST_MIRROR="$MIRROR_FNM_NODE_DIST"
    fi

    if [[ -n "$node_lts" ]]; then
      log_info "安装 Node.js $node_lts..."
      fnm install "$node_lts"
      fnm default "$node_lts"
      fnm use "$node_lts"
    else
      log_info "安装 Node.js LTS..."
      fnm install --lts
      fnm default lts-latest
      fnm use lts-latest
    fi

    log_success "Node.js 安装完成: $(node --version)"
  fi

  # 确保 node/npm 在 PATH 中
  eval "$(fnm env --shell bash 2>/dev/null || true)"

  # ── pnpm（不使用 Corepack，直接 npm install）────────────────────────────────
  if config_is_true "node.package_managers.pnpm" 2>/dev/null; then
    if check_command pnpm; then
      log_success "pnpm 已安装: $(pnpm --version)"
    else
      log_info "安装 pnpm..."
      npm install -g pnpm
      log_success "pnpm 安装完成: $(pnpm --version)"
    fi
  else
    log_dim "pnpm 安装已跳过（config: node.package_managers.pnpm = false）"
  fi

  # ── bun ──────────────────────────────────────────────────────────────────────
  if ! config_is_true "node.package_managers.bun" 2>/dev/null; then
    log_dim "bun 安装已跳过（config: node.package_managers.bun = false）"
  elif check_command bun; then
    log_success "bun 已安装: $(bun --version)"
  else
    log_info "安装 bun..."

    # 统一使用直接二进制下载，避免官方脚本额外修改 .bashrc 导致重复 PATH
    local bun_arch
    bun_arch=$(uname -m)
    case "$bun_arch" in
      x86_64)  bun_arch="bun-linux-x64" ;;
      aarch64) bun_arch="bun-linux-aarch64" ;;
      *) log_error "bun 不支持的 CPU 架构: $bun_arch"; return 1 ;;
    esac
    local bun_url="https://github.com/oven-sh/bun/releases/latest/download/${bun_arch}.zip"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    github_download "$bun_url" "$tmp_dir/bun.zip" || { rm -rf "$tmp_dir"; return 1; }
    unzip -q "$tmp_dir/bun.zip" -d "$tmp_dir"
    mkdir -p "${HOME}/.bun/bin"
    mv "$tmp_dir/${bun_arch}/bun" "${HOME}/.bun/bin/bun"
    chmod +x "${HOME}/.bun/bin/bun"
    rm -rf "$tmp_dir"

    export PATH="${HOME}/.bun/bin:${PATH}"
    add_to_bashrc "BUN_SETUP" \
      '# bun — JavaScript runtime & toolkit' \
      'export BUN_INSTALL="${HOME}/.bun"' \
      'export PATH="${BUN_INSTALL}/bin:${PATH}"'

    log_success "bun 安装完成: $(bun --version)"
  fi

  # ── 汇总 ────────────────────────────────────────────────────────────────────
  echo ""
  log_info "Node.js 生态安装完成:"
  log_dim "  node:  $(node --version 2>/dev/null || echo 'N/A')"
  log_dim "  npm:   $(npm --version 2>/dev/null || echo 'N/A')"
  log_dim "  pnpm:  $(pnpm --version 2>/dev/null || echo 'N/A')"
  log_dim "  bun:   $(bun --version 2>/dev/null || echo 'N/A')"
  log_dim "  fnm:   $(fnm --version 2>/dev/null || echo 'N/A')"
  log_info "TypeScript 策略: 不全局安装，请在项目中使用 pnpm add -D typescript"
}

# ─── 独立运行 ──────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  source "$BOOTSTRAP_DIR/lib/config.sh"
  config_init "$BOOTSTRAP_DIR"
  INIT_START=$(date +%s)
  trap 'echo ""; echo "[node.sh] 耗时: $(show_duration $INIT_START)"' EXIT
  check_ubuntu || exit 1
  resolve_region "" "false"
  install_node
fi
