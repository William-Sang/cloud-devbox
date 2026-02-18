#!/usr/bin/env bash
# modules/python.sh — Python 生态安装（uv + Python 3.12/3.13）

MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$MODULES_DIR/.." && pwd)"

source "$BOOTSTRAP_DIR/lib/common.sh"
source "$BOOTSTRAP_DIR/lib/region.sh"

# ─── 检查 ──────────────────────────────────────────────────────────────────────
check_python() {
  check_command uv
}

# ─── 安装 ──────────────────────────────────────────────────────────────────────
install_python() {
  log_step "安装 Python 生态 (uv + Python)"

  # ── uv ───────────────────────────────────────────────────────────────────────
  if check_command uv; then
    log_success "uv 已安装: $(uv --version)"
  else
    log_info "安装 uv..."
    # astral.sh 国内通常可达，不需要代理
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # uv 安装到 ~/.local/bin
    export PATH="${HOME}/.local/bin:${PATH}"

    add_to_bashrc "UV_SETUP" \
      '# uv — Python package & version manager' \
      'export PATH="${HOME}/.local/bin:${PATH}"'

    log_success "uv 安装完成: $(uv --version)"
  fi

  # 确保 uv 在 PATH 中
  export PATH="${HOME}/.local/bin:${PATH}"

  # ── 读取配置 ────────────────────────────────────────────────────────────────
  local python_versions python_default
  python_versions=$(config_get "python.versions" "3.12 3.13" 2>/dev/null || echo "3.12 3.13")
  python_default=$(config_get "python.default" "3.12" 2>/dev/null || echo "3.12")

  # ── 安装 Python 版本 ────────────────────────────────────────────────────────
  for ver in $python_versions; do
    if uv python list --only-installed 2>/dev/null | grep -q "cpython-${ver}"; then
      log_success "Python $ver 已安装。"
    else
      log_info "安装 Python $ver..."
      uv python install "$ver"
      log_success "Python $ver 安装完成。"
    fi
  done

  # ── 设置默认 Python 版本 ────────────────────────────────────────────────────
  add_to_bashrc "UV_PYTHON_DEFAULT" \
    "# 默认 Python 版本（uv 使用）" \
    "export UV_PYTHON=\"${python_default}\""

  # ── 策略提示 ────────────────────────────────────────────────────────────────
  echo ""
  log_info "Python 生态安装完成:"
  log_dim "  uv:     $(uv --version 2>/dev/null || echo 'N/A')"
  for ver in $python_versions; do
    local full_ver
    full_ver=$(uv python list --only-installed 2>/dev/null | grep "cpython-${ver}" | head -1 | awk '{print $1}' || echo "$ver")
    log_dim "  python: $full_ver"
  done
  log_dim "  默认:   Python $python_default"
  echo ""
  log_info "使用提示（PEP 668 友好）:"
  log_dim "  创建项目:   uv init myproject && cd myproject"
  log_dim "  添加依赖:   uv add requests fastapi"
  log_dim "  运行脚本:   uv run python script.py"
  log_dim "  安装 CLI:   uv tool install ruff"
  log_warn "请勿使用 pip install 全局安装包，使用 uv 替代。"
}

# ─── 独立运行 ──────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  source "$BOOTSTRAP_DIR/lib/config.sh"
  config_init "$BOOTSTRAP_DIR"
  INIT_START=$(date +%s)
  trap 'echo ""; echo "[python.sh] 耗时: $(show_duration $INIT_START)"' EXIT
  check_ubuntu || exit 1
  resolve_region "" "false"
  install_python
fi
