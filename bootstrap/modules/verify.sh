#!/usr/bin/env bash
# modules/verify.sh — 安装后验证 + 策略合规检查

MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$MODULES_DIR/.." && pwd)"

source "$BOOTSTRAP_DIR/lib/common.sh"
source "$BOOTSTRAP_DIR/lib/region.sh"

# ─── 验证结果收集 ─────────────────────────────────────────────────────────────
declare -a _VERIFY_RESULTS=()
_VERIFY_PASS=0
_VERIFY_WARN=0
_VERIFY_FAIL=0

_check_pass() { log_success "$1"; ((_VERIFY_PASS++)); _VERIFY_RESULTS+=("PASS|$1"); }
_check_warn() { log_warn "$1";    ((_VERIFY_WARN++)); _VERIFY_RESULTS+=("WARN|$1"); }
_check_fail() { log_error "$1";   ((_VERIFY_FAIL++)); _VERIFY_RESULTS+=("FAIL|$1"); }

# ─── 版本检查 ─────────────────────────────────────────────────────────────────
_verify_versions() {
  log_step "工具版本检查"

  # fnm
  if check_command fnm; then
    _check_pass "fnm: $(fnm --version 2>/dev/null)"
  else
    _check_fail "fnm: 未安装"
  fi

  # Node.js
  if check_command node; then
    local node_ver
    node_ver=$(node --version 2>/dev/null)
    local node_major
    node_major=$(echo "$node_ver" | sed 's/v//' | cut -d. -f1)
    if [[ "$node_major" -ge 20 ]]; then
      _check_pass "node: $node_ver (>= 20)"
    else
      _check_warn "node: $node_ver (< 20, 部分工具可能不兼容)"
    fi
  else
    _check_fail "node: 未安装"
  fi

  # npm
  if check_command npm; then
    _check_pass "npm: $(npm --version 2>/dev/null)"
  else
    _check_fail "npm: 未安装"
  fi

  # pnpm
  if check_command pnpm; then
    _check_pass "pnpm: $(pnpm --version 2>/dev/null)"
  else
    _check_warn "pnpm: 未安装"
  fi

  # bun
  if check_command bun; then
    _check_pass "bun: $(bun --version 2>/dev/null)"
  else
    _check_warn "bun: 未安装"
  fi

  # uv
  if check_command uv; then
    _check_pass "uv: $(uv --version 2>/dev/null)"
  else
    _check_fail "uv: 未安装"
  fi

  # Docker
  if check_command docker; then
    _check_pass "docker: $(docker --version 2>/dev/null | head -1)"
  else
    _check_warn "docker: 未安装（可选模块）"
  fi

  # AI 工具
  for tool in claude opencode codex gemini; do
    if check_command "$tool"; then
      _check_pass "$tool: 已安装"
    else
      _check_warn "$tool: 未安装（可选）"
    fi
  done
  if check_command qodercli || check_command qoder; then
    _check_pass "qoder: 已安装"
  else
    _check_warn "qoder: 未安装（可选）"
  fi
}

# ─── 策略合规检查 ─────────────────────────────────────────────────────────────
_verify_policies() {
  log_step "策略合规检查"

  # 1. 全局 pip 污染检查（PEP 668）
  if check_command pip3; then
    local pip_user_pkgs
    pip_user_pkgs=$(pip3 list --user 2>/dev/null | tail -n +3 | wc -l)
    if [[ "$pip_user_pkgs" -gt 0 ]]; then
      _check_warn "全局 pip 包: 检测到 ${pip_user_pkgs} 个用户级 pip 包（建议使用 uv tool install）"
    else
      _check_pass "全局 pip 包: 无污染"
    fi
  else
    _check_pass "全局 pip 包: pip3 不在 PATH（符合预期）"
  fi

  # 2. fnm PATH 检查
  if check_command node; then
    local node_path
    node_path=$(which node 2>/dev/null)
    if [[ "$node_path" == *".local/share/fnm"* ]] || [[ "$node_path" == *"/fnm_multishells/"* ]]; then
      _check_pass "fnm PATH: node 由 fnm 管理 ($node_path)"
    elif [[ "$node_path" == *"nvm"* ]]; then
      _check_warn "fnm PATH: node 由 nvm 管理（非预期）: $node_path"
    else
      _check_warn "fnm PATH: node 路径非 fnm 管理: $node_path"
    fi
  fi

  # 3. Corepack 检查
  if check_command corepack; then
    # 检查 corepack 是否被用来管理 pnpm
    local corepack_pnpm
    corepack_pnpm=$(corepack ls 2>/dev/null | grep -c "pnpm" || echo "0")
    if [[ "$corepack_pnpm" -gt 0 ]]; then
      _check_warn "Corepack: 检测到 corepack 管理 pnpm（Node 25+ 将不再内置 corepack）"
    else
      _check_pass "Corepack: 未用于管理 pnpm"
    fi
  else
    _check_pass "Corepack: 未安装（符合预期）"
  fi

  # 4. Docker 权限检查
  if check_command docker; then
    local current_user="${SUDO_USER:-$USER}"
    if groups "$current_user" 2>/dev/null | grep -q docker; then
      _check_pass "Docker 权限: $current_user 在 docker 组中"
    else
      _check_warn "Docker 权限: $current_user 不在 docker 组中（需要 sudo 使用 docker）"
    fi
  fi

  # 5. 镜像源检查
  if [[ "${REGION:-}" == "cn" ]]; then
    # npm registry
    if check_command npm; then
      local npm_reg
      npm_reg=$(npm config get registry 2>/dev/null || echo "")
      if [[ "$npm_reg" == *"npmmirror"* ]]; then
        _check_pass "npm 镜像: 已配置 npmmirror"
      else
        _check_warn "npm 镜像: 中国区域但未配置 npmmirror ($npm_reg)"
      fi
    fi

    # uv index
    local uv_toml="${HOME}/.config/uv/uv.toml"
    if [[ -f "$uv_toml" ]] && grep -q "aliyun\|tuna" "$uv_toml" 2>/dev/null; then
      _check_pass "PyPI 镜像: 已配置国内源"
    elif [[ -f "$uv_toml" ]]; then
      _check_warn "PyPI 镜像: uv.toml 存在但未配置国内源"
    fi
  fi
}

# ─── 生成 JSON 报告 ───────────────────────────────────────────────────────────
_generate_json_report() {
  local report_file="$1"
  local json="{"
  json+="\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  json+="\"region\":\"${REGION:-unknown}\","
  json+="\"ubuntu_version\":\"${UBUNTU_VERSION_ID:-unknown}\","
  json+="\"summary\":{\"pass\":${_VERIFY_PASS},\"warn\":${_VERIFY_WARN},\"fail\":${_VERIFY_FAIL}},"
  json+="\"checks\":["

  local first=true
  for result in "${_VERIFY_RESULTS[@]}"; do
    local status="${result%%|*}"
    local msg="${result#*|}"
    if [[ "$first" == true ]]; then
      first=false
    else
      json+=","
    fi
    # 转义 JSON 字符串中的特殊字符
    msg="${msg//\\/\\\\}"
    msg="${msg//\"/\\\"}"
    json+="{\"status\":\"${status}\",\"message\":\"${msg}\"}"
  done

  json+="]}"

  echo "$json" > "$report_file"
  log_info "JSON 报告已导出: $report_file"
}

# ─── 主验证函数 ────────────────────────────────────────────────────────────────
run_verify() {
  local report_json="${1:-}"

  log_step "安装验证 / Verify"
  print_separator

  _verify_versions
  _verify_policies

  # 汇总
  echo ""
  print_separator
  log_info "验证结果: ${_VERIFY_PASS} 通过, ${_VERIFY_WARN} 警告, ${_VERIFY_FAIL} 失败"
  print_separator

  # 可选 JSON 报告
  if [[ -n "$report_json" ]]; then
    _generate_json_report "$report_json"
  fi

  [[ $_VERIFY_FAIL -eq 0 ]]
}

# ─── 独立运行 ──────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  source "$BOOTSTRAP_DIR/lib/config.sh"
  config_init "$BOOTSTRAP_DIR"

  # 读取缓存区域
  if [[ -f "${HOME}/.config/init-devbox/region" ]]; then
    REGION=$(cat "${HOME}/.config/init-devbox/region")
  fi
  check_ubuntu 2>/dev/null || true

  run_verify "${1:-}"
fi
