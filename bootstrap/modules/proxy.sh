#!/usr/bin/env bash
# modules/proxy.sh — 代理持久化与工具级代理配置

MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$MODULES_DIR/.." && pwd)"

source "$BOOTSTRAP_DIR/lib/common.sh"
source "$BOOTSTRAP_DIR/lib/config.sh"
source "$BOOTSTRAP_DIR/lib/proxy.sh"

# ─── 检查 ──────────────────────────────────────────────────────────────────────
check_proxy() {
  [[ -n "${HTTP_PROXY:-}" ]] || grep -qF "# BEGIN_INIT_PROXY" "${HOME}/.bashrc" 2>/dev/null
}

# ─── 安装 ──────────────────────────────────────────────────────────────────────
install_proxy() {
  log_step "配置代理"

  # 未配置代理时，交互式询问
  local _proxy_from_interactive=false
  local _proxy_persist_bashrc=false
  if [[ -z "$PROXY_URL" ]]; then
    if [[ -t 0 ]]; then
      echo ""
      echo "未检测到代理配置。如需代理访问外网，请输入代理地址。"
      echo "支持格式: http://host:port, socks5://host:port"
      echo ""
      local input_proxy
      read -r -p "代理地址 (留空跳过): " input_proxy
      if [[ -n "$input_proxy" ]]; then
        resolve_proxy "$input_proxy"
        if [[ -z "$PROXY_URL" ]]; then
          log_warn "代理地址格式无效，跳过代理配置。"
          return 0
        fi
        _proxy_from_interactive=true
        PROXY_SOURCE="interactive"
        # 询问是否持久化到 .bashrc
        local persist_choice
        read -r -p "是否将代理写入 ~/.bashrc 以便永久生效? [Y/n]: " persist_choice
        case "$persist_choice" in
          [nN]*) _proxy_persist_bashrc=false ;;
          *)     _proxy_persist_bashrc=true ;;
        esac
      else
        log_info "未配置代理，跳过。"
        return 0
      fi
    else
      log_info "未配置代理，跳过。"
      return 0
    fi
  fi

  # ── 1. 持久化到 .bashrc ──────────────────────────────────────────────────────
  # CLI --proxy：默认持久化；交互式输入：由用户选择；其他来源：看 config
  local _should_persist=false
  if [[ "$_proxy_from_interactive" == true ]]; then
    _should_persist="$_proxy_persist_bashrc"
  elif [[ "${PROXY_SOURCE:-}" == "cli" ]]; then
    _should_persist=true
  elif config_is_true "proxy.persist_bashrc" 2>/dev/null; then
    _should_persist=true
  fi

  if [[ "$_should_persist" == true ]]; then
    add_to_bashrc "PROXY" \
      '# HTTP/SOCKS 代理' \
      "export HTTP_PROXY=\"${PROXY_URL}\"" \
      "export HTTPS_PROXY=\"${PROXY_URL}\"" \
      "export ALL_PROXY=\"${PROXY_URL}\"" \
      "export NO_PROXY=\"${PROXY_NO_PROXY}\"" \
      "export http_proxy=\"${PROXY_URL}\"" \
      "export https_proxy=\"${PROXY_URL}\"" \
      "export all_proxy=\"${PROXY_URL}\"" \
      "export no_proxy=\"${PROXY_NO_PROXY}\""
    log_success "代理已写入 ~/.bashrc"
  else
    log_dim "proxy.persist_bashrc = false，跳过 .bashrc 写入。"
  fi

  # ── 2. Git 代理 ─────────────────────────────────────────────────────────────
  if [[ "${PROXY_SOURCE:-}" == "cli" ]] || [[ "${PROXY_SOURCE:-}" == "interactive" ]] \
     || config_is_true "proxy.git" 2>/dev/null; then
    log_info "配置 git 代理..."
    git config --global http.proxy "$PROXY_URL" 2>/dev/null || true
    git config --global https.proxy "$PROXY_URL" 2>/dev/null || true
    log_success "git 代理已配置: $PROXY_URL"
  fi

  # ── 3. Docker 守护进程代理 ───────────────────────────────────────────────────
  if [[ "${PROXY_SOURCE:-}" == "cli" ]] || [[ "${PROXY_SOURCE:-}" == "interactive" ]] \
     || config_is_true "proxy.docker" 2>/dev/null; then
    _setup_docker_proxy
  fi

  log_success "代理配置完成。"
}

# ─── Docker 守护进程代理（systemd drop-in）──────────────────────────────────────
_setup_docker_proxy() {
  local dropin_dir="/etc/systemd/system/docker.service.d"
  local dropin_file="${dropin_dir}/proxy.conf"

  # 幂等：已配置且 URL 相同则跳过
  if [[ -f "$dropin_file" ]] && grep -qF "$PROXY_URL" "$dropin_file" 2>/dev/null; then
    log_dim "Docker 代理已配置，跳过。"
    return 0
  fi

  log_info "配置 Docker 守护进程代理..."
  sudo mkdir -p "$dropin_dir"
  sudo tee "$dropin_file" > /dev/null <<EOF
[Service]
Environment="HTTP_PROXY=${PROXY_URL}"
Environment="HTTPS_PROXY=${PROXY_URL}"
Environment="NO_PROXY=${PROXY_NO_PROXY}"
EOF

  # 仅在 docker.service 存在时 reload
  if systemctl list-unit-files docker.service &>/dev/null; then
    sudo systemctl daemon-reload
    sudo systemctl restart docker 2>/dev/null || log_warn "Docker 重启失败（可能尚未安装）。"
  fi

  log_success "Docker 守护进程代理已配置。"
}

# ─── 独立运行 ──────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  source "$BOOTSTRAP_DIR/lib/config.sh"
  config_init "$BOOTSTRAP_DIR"
  INIT_START=$(date +%s)
  trap 'echo ""; echo "[proxy.sh] 耗时: $(show_duration $INIT_START)"' EXIT
  resolve_proxy ""
  install_proxy
fi
