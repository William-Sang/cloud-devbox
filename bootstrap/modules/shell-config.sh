#!/usr/bin/env bash
# modules/shell-config.sh — Shell 环境配置

MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$MODULES_DIR/.." && pwd)"

source "$BOOTSTRAP_DIR/lib/common.sh"

# ─── 检查 ──────────────────────────────────────────────────────────────────────
check_shell_config() {
  grep -qF "# BEGIN_INIT_SHELL_ALIASES" "${HOME}/.bashrc" 2>/dev/null
}

# ─── 安装 ──────────────────────────────────────────────────────────────────────
install_shell_config() {
  log_step "配置 Shell 环境"

  # ── Bash 别名 ───────────────────────────────────────────────────────────────
  add_to_bashrc "SHELL_ALIASES" \
    '# 常用别名' \
    "alias ll='ls -alF'" \
    "alias la='ls -A'" \
    "alias l='ls -CF'" \
    "alias grep='grep --color=auto'" \
    "alias ..='cd ..'" \
    "alias ...='cd ../..'" \
    "alias df='df -h'" \
    "alias du='du -h'" \
    "alias free='free -h'" \
    "alias ports='ss -tulnp'"

  # ── PS1 提示符（显示 git 分支）──────────────────────────────────────────────
  add_to_bashrc "SHELL_PROMPT" \
    '# Git-aware PS1 提示符' \
    '__git_branch() { git branch 2>/dev/null | grep "^\*" | sed "s/\* //"; }' \
    'PS1='"'"'\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$(branch=$(__git_branch); [ -n "$branch" ] && echo " \[\033[01;33m\]($branch)\[\033[00m\]")\$ '"'"

  # ── Git 全局配置 ────────────────────────────────────────────────────────────
  log_info "配置 git 全局默认..."

  git config --global color.ui auto 2>/dev/null || true
  git config --global init.defaultBranch main 2>/dev/null || true
  git config --global core.editor vim 2>/dev/null || true
  git config --global pull.rebase false 2>/dev/null || true

  # 不覆盖已有的 user.name/user.email
  if [[ -z "$(git config --global user.name 2>/dev/null)" ]]; then
    log_warn "git user.name 未设置。请运行: git config --global user.name 'Your Name'"
  fi
  if [[ -z "$(git config --global user.email 2>/dev/null)" ]]; then
    log_warn "git user.email 未设置。请运行: git config --global user.email 'you@example.com'"
  fi

  # ── 工具补全 ────────────────────────────────────────────────────────────────
  if check_command fnm; then
    add_to_bashrc "FNM_COMPLETIONS" \
      '# fnm bash completions' \
      'eval "$(fnm completions --shell bash 2>/dev/null || true)"'
  fi

  if check_command uv; then
    add_to_bashrc "UV_COMPLETIONS" \
      '# uv bash completions' \
      'eval "$(uv generate-shell-completion bash 2>/dev/null || true)"'
  fi

  if check_command pnpm; then
    add_to_bashrc "PNPM_SETUP" \
      '# pnpm global bin' \
      'export PNPM_HOME="${HOME}/.local/share/pnpm"' \
      'export PATH="${PNPM_HOME}:${PATH}"'
  fi

  log_success "Shell 环境配置完成。"
  log_info "请重启 shell 或运行: source ~/.bashrc"
}

# ─── 独立运行 ──────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  INIT_START=$(date +%s)
  trap 'echo ""; echo "[shell-config.sh] 耗时: $(show_duration $INIT_START)"' EXIT
  install_shell_config
fi
