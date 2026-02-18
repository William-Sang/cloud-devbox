#!/usr/bin/env bash
# modules/docker.sh — Docker Engine 安装

MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$MODULES_DIR/.." && pwd)"

source "$BOOTSTRAP_DIR/lib/common.sh"
source "$BOOTSTRAP_DIR/lib/region.sh"

# ─── 检查 ──────────────────────────────────────────────────────────────────────
check_docker() {
  check_command docker && docker --version &>/dev/null
}

# ─── 安装 ──────────────────────────────────────────────────────────────────────
install_docker() {
  log_step "安装 Docker Engine"

  if check_docker; then
    log_success "Docker 已安装: $(docker --version)"
    return 0
  fi

  check_ubuntu || return 1
  export DEBIAN_FRONTEND=noninteractive

  # 安装前置依赖
  sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release

  # ─── GPG Key（幂等）──────────────────────────────────────────────────────────
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    log_info "添加 Docker GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings

    local gpg_url="https://download.docker.com/linux/ubuntu/gpg"
    if [[ -n "$MIRROR_DOCKER_CE" ]]; then
      gpg_url="${MIRROR_DOCKER_CE}/linux/ubuntu/gpg"
    fi

    curl -fsSL "$gpg_url" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  # ─── apt 源（幂等）──────────────────────────────────────────────────────────
  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    log_info "添加 Docker apt 源..."
    local repo_url="https://download.docker.com"
    if [[ -n "$MIRROR_DOCKER_CE" ]]; then
      repo_url="$MIRROR_DOCKER_CE"
    fi

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${repo_url}/linux/ubuntu ${UBUNTU_CODENAME} stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  fi

  # ─── 安装 Docker ─────────────────────────────────────────────────────────────
  sudo apt-get update -qq
  sudo apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  # ─── Docker Hub 镜像加速（中国区域）──────────────────────────────────────────
  if [[ -n "$MIRROR_DOCKER_HUB" ]]; then
    local daemon_json="/etc/docker/daemon.json"
    if [[ ! -f "$daemon_json" ]] || ! grep -q "registry-mirrors" "$daemon_json" 2>/dev/null; then
      log_info "配置 Docker Hub 镜像加速..."
      sudo mkdir -p /etc/docker
      if [[ -f "$daemon_json" ]] && check_command jq; then
        # 合并到已有配置，保留其他字段
        local tmp_daemon
        tmp_daemon=$(jq --arg mirror "$MIRROR_DOCKER_HUB" \
          '. + {"registry-mirrors": [$mirror]}' "$daemon_json")
        echo "$tmp_daemon" | sudo tee "$daemon_json" > /dev/null
      else
        # 文件不存在或 jq 不可用，直接写入
        cat <<EOF | sudo tee "$daemon_json" > /dev/null
{
  "registry-mirrors": ["${MIRROR_DOCKER_HUB}"]
}
EOF
      fi
    fi
  fi

  # ─── 用户组 + 安全提示 ──────────────────────────────────────────────────────
  local docker_mode
  docker_mode=$(config_get "docker.mode" "group" 2>/dev/null || echo "group")

  local current_user="${SUDO_USER:-$USER}"

  if [[ "$docker_mode" == "group" ]]; then
    if [[ "$current_user" != "root" ]]; then
      sudo usermod -aG docker "$current_user"
    fi

    echo ""
    log_warn "━━━ Docker 安全提示 ━━━"
    log_warn "已将用户 '$current_user' 添加到 docker 组。"
    log_warn "docker 组成员拥有等同 root 的权限，请注意安全风险。"
    log_warn "详见: https://docs.docker.com/engine/install/linux-postinstall/"
    log_warn "如需更安全的方案，可在 config.toml 中设置 docker.mode = \"rootless\""
    echo ""
  elif [[ "$docker_mode" == "rootless" ]]; then
    log_info "安装 rootless Docker..."
    sudo apt-get install -y -qq uidmap
    if [[ "$current_user" != "root" ]]; then
      sudo -u "$current_user" dockerd-rootless-setuptool.sh install 2>/dev/null || {
        log_warn "rootless Docker 安装可能需要手动配置。"
        log_warn "请参考: https://docs.docker.com/engine/security/rootless/"
      }
    fi
  fi

  # ─── 启动服务 ───────────────────────────────────────────────────────────────
  sudo systemctl enable docker 2>/dev/null || true
  sudo systemctl start docker 2>/dev/null || true

  unset DEBIAN_FRONTEND
  log_success "Docker 安装完成: $(docker --version)"
  log_warn "需要重新登录 shell 才能不加 sudo 使用 docker。"
}

# ─── 独立运行 ──────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  source "$BOOTSTRAP_DIR/lib/config.sh"
  config_init "$BOOTSTRAP_DIR"
  INIT_START=$(date +%s)
  trap 'echo ""; echo "[docker.sh] 耗时: $(show_duration $INIT_START)"' EXIT
  check_ubuntu || exit 1
  ensure_sudo  || exit 1
  resolve_region "" "false"
  install_docker
fi
