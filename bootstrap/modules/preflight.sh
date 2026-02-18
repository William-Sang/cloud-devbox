#!/usr/bin/env bash
# modules/preflight.sh — 预检模块（doctor 子命令）

MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$MODULES_DIR/.." && pwd)"

# shellcheck source=../lib/common.sh
source "$BOOTSTRAP_DIR/lib/common.sh"

# ─── 预检函数 ──────────────────────────────────────────────────────────────────
run_preflight() {
  log_step "系统预检 / Preflight Check"
  print_separator

  local pass=0
  local warn=0
  local fail=0

  # 1. OS 检测
  if check_ubuntu; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    log_error "不支持的操作系统"
  fi

  # 2. sudo 权限
  if [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null; then
    log_success "sudo 权限: 可用"
    pass=$((pass + 1))
  else
    log_warn "sudo 权限: 需要输入密码"
    warn=$((warn + 1))
  fi

  # 3. 磁盘空间
  local avail_gb
  avail_gb=$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -d ' G')
  if [[ -n "$avail_gb" ]] && [[ "$avail_gb" -ge 5 ]]; then
    log_success "磁盘空间: ${avail_gb}GB 可用 (>= 5GB)"
    pass=$((pass + 1))
  elif [[ -n "$avail_gb" ]]; then
    log_error "磁盘空间: ${avail_gb}GB 可用 (< 5GB 不足)"
    fail=$((fail + 1))
  else
    log_warn "磁盘空间: 无法检测"
    warn=$((warn + 1))
  fi

  # 4. 网络连通性（根据区域或缓存选择测试 URL）
  local test_url="https://www.google.com"
  local cached_region="${REGION:-}"
  if [[ -z "$cached_region" && -f "${HOME}/.config/init-devbox/region" ]]; then
    cached_region=$(cat "${HOME}/.config/init-devbox/region")
  fi
  if [[ "$cached_region" == "cn" ]]; then
    test_url="https://mirrors.aliyun.com"
  fi
  if check_url "$test_url" 5; then
    log_success "网络连通: $test_url 可达"
    pass=$((pass + 1))
  else
    log_warn "网络连通: $test_url 不可达（可能影响安装）"
    warn=$((warn + 1))
  fi

  # 5. 区域设置
  if [[ -n "${REGION:-}" ]]; then
    log_info "当前区域: $REGION"
  elif [[ -f "${HOME}/.config/init-devbox/region" ]]; then
    log_info "缓存区域: $(cat "${HOME}/.config/init-devbox/region")"
  else
    log_info "区域: 未设置（首次 apply 时会询问）"
  fi

  # 6. 已安装工具清单
  echo ""
  log_step "已安装工具状态"
  print_separator

  local tools=("git" "curl" "docker" "fnm" "node" "npm" "pnpm" "bun" "uv" "python3" "claude" "opencode" "codex" "gemini")
  for tool in "${tools[@]}"; do
    if check_command "$tool"; then
      local ver
      ver=$("$tool" --version 2>/dev/null | head -1) || ver="已安装"
      [[ -z "$ver" ]] && ver="已安装"
      log_success "$tool: $ver"
    else
      log_dim "$tool: 未安装"
    fi
  done

  # 汇总
  echo ""
  print_separator
  log_info "预检结果: ${pass} 通过, ${warn} 警告, ${fail} 失败"

  [[ $fail -eq 0 ]]
}

# ─── 独立运行 ──────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  run_preflight
fi
