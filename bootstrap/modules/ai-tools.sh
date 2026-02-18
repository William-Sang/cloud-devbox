#!/usr/bin/env bash
# modules/ai-tools.sh — AI 编码 CLI 工具安装

MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$MODULES_DIR/.." && pwd)"

source "$BOOTSTRAP_DIR/lib/common.sh"
source "$BOOTSTRAP_DIR/lib/region.sh"

# ─── 检查 ──────────────────────────────────────────────────────────────────────
check_ai_tools() {
  # 至少有一个 AI 工具已安装
  check_command claude || check_command opencode || check_command codex || check_command gemini
}

# ─── 各工具独立安装函数 ────────────────────────────────────────────────────────

_install_claude_code() {
  if check_command claude; then
    log_success "Claude Code 已安装。"
    return 0
  fi
  log_info "安装 Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
  # Claude Code 安装到 ~/.local/bin
  export PATH="${HOME}/.local/bin:${PATH}"
  log_success "Claude Code 安装完成。"
}

_install_opencode() {
  if check_command opencode; then
    log_success "OpenCode 已安装。"
    return 0
  fi
  log_info "安装 OpenCode (sst/opencode)..."
  local install_url="https://opencode.ai/install"
  curl -fsSL "$install_url" | bash
  log_success "OpenCode 安装完成。"
}

_install_codex() {
  if check_command codex; then
    log_success "OpenAI Codex CLI 已安装。"
    return 0
  fi
  if ! check_command npm; then
    log_warn "npm 未找到，跳过 Codex CLI 安装。请先安装 Node.js。"
    return 1
  fi
  log_info "安装 OpenAI Codex CLI..."
  npm install -g @openai/codex
  log_success "OpenAI Codex CLI 安装完成。"
}

_install_qoder() {
  if check_command qodercli || check_command qoder; then
    log_success "Qoder CLI 已安装。"
    return 0
  fi
  if ! check_command npm; then
    log_warn "npm 未找到，跳过 Qoder CLI 安装。请先安装 Node.js。"
    return 1
  fi
  log_info "安装 Qoder CLI..."
  npm install -g @qoder-ai/qodercli
  log_success "Qoder CLI 安装完成。"
}

_install_gemini() {
  if check_command gemini; then
    log_success "Google Gemini CLI 已安装。"
    return 0
  fi
  if ! check_command node; then
    log_warn "Node.js 未找到，跳过 Gemini CLI 安装。"
    return 1
  fi

  # 检查 Node.js 版本 >= 20
  local node_major
  node_major=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
  if [[ -z "$node_major" ]] || [[ "$node_major" -lt 20 ]]; then
    log_warn "Gemini CLI 需要 Node.js 20+，当前: $(node --version 2>/dev/null || echo '未安装')。跳过。"
    return 1
  fi

  log_info "安装 Google Gemini CLI..."
  npm install -g @google/gemini-cli
  log_success "Google Gemini CLI 安装完成。"
}

# ─── 主安装函数 ────────────────────────────────────────────────────────────────
install_ai_tools() {
  log_step "安装 AI 编码 CLI 工具"

  if ! check_command node; then
    log_warn "Node.js 未找到。npm-based AI 工具（Codex, Qoder, Gemini）将被跳过。"
    log_warn "请先运行 node 模块：bash bootstrap/modules/node.sh"
  fi

  local failed_tools=()
  local installed_tools=()

  _install_claude_code && installed_tools+=("claude-code") || failed_tools+=("claude-code")
  _install_opencode    && installed_tools+=("opencode")    || failed_tools+=("opencode")
  _install_codex       && installed_tools+=("codex")       || failed_tools+=("codex")
  _install_qoder       && installed_tools+=("qoder")       || failed_tools+=("qoder")
  _install_gemini      && installed_tools+=("gemini")      || failed_tools+=("gemini")

  # ── 汇总 ────────────────────────────────────────────────────────────────────
  echo ""
  if [[ ${#installed_tools[@]} -gt 0 ]]; then
    log_success "已安装: ${installed_tools[*]}"
  fi
  if [[ ${#failed_tools[@]} -gt 0 ]]; then
    log_warn "安装失败或跳过: ${failed_tools[*]}"
    log_warn "可单独重试，重新运行此模块即可。"
    if [[ "$REGION" == "cn" ]]; then
      log_warn "提示: 部分 AI 工具的安装需要访问外网，请确保网络可用。"
    fi
  fi

  echo ""
  log_info "各工具需要的认证:"
  log_dim "  Claude Code  — Anthropic 账号（claude.ai）"
  log_dim "  OpenCode     — 支持多种 API key（ANTHROPIC/OPENAI/GEMINI_API_KEY）"
  log_dim "  Codex CLI    — OpenAI API key 或 ChatGPT 订阅"
  log_dim "  Qoder CLI    — Qoder 账号（qoder.com）"
  log_dim "  Gemini CLI   — Google 账号（免费额度）或 GEMINI_API_KEY"
}

# ─── 独立运行 ──────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  source "$BOOTSTRAP_DIR/lib/config.sh"
  config_init "$BOOTSTRAP_DIR"
  INIT_START=$(date +%s)
  trap 'echo ""; echo "[ai-tools.sh] 耗时: $(show_duration $INIT_START)"' EXIT
  check_ubuntu || exit 1
  resolve_region "" "false"
  install_ai_tools
fi
