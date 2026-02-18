#!/usr/bin/env bash
# modules/mirror.sh — 镜像源配置模块

MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$MODULES_DIR/.." && pwd)"

source "$BOOTSTRAP_DIR/lib/common.sh"
source "$BOOTSTRAP_DIR/lib/region.sh"

# ─── 检查镜像是否已配置 ────────────────────────────────────────────────────────
check_mirror() {
  [[ "$REGION" == "overseas" ]] && return 0
  # 中国区域：检查 npm registry 是否已配置
  if check_command npm; then
    local current_registry
    current_registry=$(npm config get registry 2>/dev/null || echo "")
    [[ "$current_registry" == *"npmmirror"* ]] && return 0
  fi
  return 1
}

# ─── 连通性探测 + 回退逻辑 ─────────────────────────────────────────────────────
_probe_mirror() {
  local mirror_url="$1"
  local mirror_name="$2"
  local fallback="${3:-true}"

  if [[ -z "$mirror_url" ]]; then
    return 0
  fi

  if check_url "$mirror_url" 5; then
    log_success "$mirror_name 镜像可达: $mirror_url"
    return 0
  fi

  if [[ "$fallback" == "true" ]]; then
    log_warn "$mirror_name 镜像不可达: $mirror_url — 回退到官方源"
    return 1
  else
    log_error "$mirror_name 镜像不可达: $mirror_url"
    return 1
  fi
}

# ─── 配置 apt 镜像 ────────────────────────────────────────────────────────────
_setup_apt_mirror() {
  [[ -z "$MIRROR_APT" ]] && return 0
  log_info "配置 apt 镜像源..."

  if ! _probe_mirror "$MIRROR_APT" "apt"; then
    return 0
  fi

  # Ubuntu 24.04 使用 DEB822 格式
  if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
    local sources_file="/etc/apt/sources.list.d/ubuntu.sources"
    if grep -q "${MIRROR_APT}" "$sources_file" 2>/dev/null; then
      log_dim "apt 镜像已配置，跳过。"
      return 0
    fi
    sudo cp "$sources_file" "${sources_file}.bak"
    sudo sed -i "s|http://archive.ubuntu.com|${MIRROR_APT}|g" "$sources_file"
    sudo sed -i "s|http://security.ubuntu.com|${MIRROR_APT}|g" "$sources_file"
  # Ubuntu 22.04 使用传统 sources.list
  elif [[ -f /etc/apt/sources.list ]]; then
    if grep -q "${MIRROR_APT}" /etc/apt/sources.list 2>/dev/null; then
      log_dim "apt 镜像已配置，跳过。"
      return 0
    fi
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    sudo sed -i "s|http://archive.ubuntu.com|${MIRROR_APT}|g" /etc/apt/sources.list
    sudo sed -i "s|http://security.ubuntu.com|${MIRROR_APT}|g" /etc/apt/sources.list
  fi

  log_success "apt 镜像已配置: $MIRROR_APT"
}

# ─── 配置 npm 镜像 ────────────────────────────────────────────────────────────
_setup_npm_mirror() {
  [[ -z "$MIRROR_NPM" ]] && return 0
  # npm 可能还没安装，先记录配置，node.sh 安装后再设置
  # 写入 ~/.npmrc 文件（npm 启动时自动读取）
  local npmrc="${HOME}/.npmrc"

  if grep -q "registry=" "$npmrc" 2>/dev/null; then
    if grep -q "$MIRROR_NPM" "$npmrc" 2>/dev/null; then
      log_dim "npm 镜像已配置，跳过。"
      return 0
    fi
  fi

  log_info "配置 npm 镜像源..."
  if ! _probe_mirror "$MIRROR_NPM" "npm"; then
    return 0
  fi

  # 写入或更新 .npmrc
  if [[ -f "$npmrc" ]] && grep -q "^registry=" "$npmrc" 2>/dev/null; then
    sed -i "s|^registry=.*|registry=${MIRROR_NPM}|" "$npmrc"
  else
    echo "registry=${MIRROR_NPM}" >> "$npmrc"
  fi

  log_success "npm 镜像已配置: $MIRROR_NPM"
}

# ─── 配置 PyPI / uv 镜像 ─────────────────────────────────────────────────────
_setup_pypi_mirror() {
  [[ -z "$MIRROR_PYPI" ]] && return 0
  log_info "配置 PyPI/uv 镜像源..."

  if ! _probe_mirror "$MIRROR_PYPI" "pypi"; then
    return 0
  fi

  # uv 配置
  local uv_config_dir="${HOME}/.config/uv"
  local uv_config_file="${uv_config_dir}/uv.toml"
  mkdir -p "$uv_config_dir"

  if [[ -f "$uv_config_file" ]] && grep -q "$MIRROR_PYPI" "$uv_config_file" 2>/dev/null; then
    log_dim "uv PyPI 镜像已配置，跳过。"
  else
    # 保留已有配置，仅追加/替换 index 配置
    if [[ -f "$uv_config_file" ]] && grep -q '^\[\[index\]\]' "$uv_config_file" 2>/dev/null; then
      # 已有 index 配置，用 sed 替换 url 行
      sed -i '/^\[\[index\]\]/,/^$/{s|^url = .*|url = "'"${MIRROR_PYPI}"'"|;}' "$uv_config_file"
    elif [[ -f "$uv_config_file" ]]; then
      # 已有文件但无 index 配置，追加
      cat >> "$uv_config_file" <<EOF

[[index]]
url = "${MIRROR_PYPI}"
default = true
EOF
    else
      cat > "$uv_config_file" <<EOF
[[index]]
url = "${MIRROR_PYPI}"
default = true
EOF
    fi
    log_success "uv 镜像已配置: $MIRROR_PYPI"
  fi

  # pip 配置（兼容未使用 uv 的场景）
  local pip_config_dir="${HOME}/.config/pip"
  local pip_config_file="${pip_config_dir}/pip.conf"
  mkdir -p "$pip_config_dir"

  if [[ -f "$pip_config_file" ]] && grep -q "$MIRROR_PYPI" "$pip_config_file" 2>/dev/null; then
    log_dim "pip PyPI 镜像已配置，跳过。"
  else
    # 保留已有配置，仅更新 [global] 中的 index-url
    if [[ -f "$pip_config_file" ]] && grep -q '^\[global\]' "$pip_config_file" 2>/dev/null; then
      sed -i "s|^index-url = .*|index-url = ${MIRROR_PYPI}|" "$pip_config_file"
      sed -i "s|^trusted-host = .*|trusted-host = ${MIRROR_PYPI_TRUSTED_HOST}|" "$pip_config_file"
    elif [[ -f "$pip_config_file" ]]; then
      cat >> "$pip_config_file" <<EOF

[global]
index-url = ${MIRROR_PYPI}
trusted-host = ${MIRROR_PYPI_TRUSTED_HOST}
EOF
    else
      cat > "$pip_config_file" <<EOF
[global]
index-url = ${MIRROR_PYPI}
trusted-host = ${MIRROR_PYPI_TRUSTED_HOST}
EOF
    fi
    log_success "pip 镜像已配置: $MIRROR_PYPI"
  fi
}

# ─── 主安装函数 ────────────────────────────────────────────────────────────────
install_mirror() {
  log_step "配置镜像源"

  if [[ "$REGION" == "overseas" ]]; then
    log_info "海外区域，使用官方源，跳过镜像配置。"
    return 0
  fi

  _setup_apt_mirror
  _setup_npm_mirror
  _setup_pypi_mirror
  # Docker 镜像在 docker.sh 中配置（因为需要 Docker 安装后才能写 daemon.json）

  log_success "镜像源配置完成。"
}

# ─── 独立运行 ──────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  source "$BOOTSTRAP_DIR/lib/config.sh"
  config_init "$BOOTSTRAP_DIR"
  INIT_START=$(date +%s)
  trap 'echo ""; echo "[mirror.sh] 耗时: $(show_duration $INIT_START)"' EXIT
  check_ubuntu || exit 1

  # 独立运行时交互询问区域
  resolve_region "" "false"
  install_mirror
fi
