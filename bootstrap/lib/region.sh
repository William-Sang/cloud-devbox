#!/usr/bin/env bash
# lib/region.sh — 区域检测与镜像源预设
# 被其他脚本 source，不直接执行。

[[ -n "${_REGION_LOADED:-}" ]] && return 0
_REGION_LOADED=1

# ─── 全局镜像变量（由 apply_*_mirrors 函数设置）──────────────────────────────
MIRROR_APT=""
MIRROR_NPM=""
MIRROR_PYPI=""
MIRROR_PYPI_TRUSTED_HOST=""
MIRROR_DOCKER_CE=""
MIRROR_DOCKER_HUB=""
MIRROR_GITHUB_PROXY=""
MIRROR_FNM_NODE_DIST=""

# 当前区域
REGION=""

# 区域缓存文件
_REGION_CACHE_DIR="${HOME}/.config/init-devbox"
_REGION_CACHE_FILE="${_REGION_CACHE_DIR}/region"

# ─── 设置中国镜像 ──────────────────────────────────────────────────────────────
apply_cn_mirrors() {
  MIRROR_APT="https://mirrors.aliyun.com"
  MIRROR_NPM="https://registry.npmmirror.com"
  MIRROR_PYPI="https://mirrors.aliyun.com/pypi/simple/"
  MIRROR_PYPI_TRUSTED_HOST="mirrors.aliyun.com"
  MIRROR_DOCKER_CE="https://mirrors.aliyun.com/docker-ce"
  MIRROR_DOCKER_HUB="https://docker.m.daocloud.io,https://docker-0.unsee.tech,https://mirror.iscas.ac.cn"
  MIRROR_GITHUB_PROXY="https://ghfast.top/"
  MIRROR_FNM_NODE_DIST="https://npmmirror.com/mirrors/node"
  log_info "区域: 中国大陆 — 使用国内镜像加速"
}

# ─── 设置海外源（官方默认）─────────────────────────────────────────────────────
apply_overseas_mirrors() {
  MIRROR_APT=""
  MIRROR_NPM=""
  MIRROR_PYPI=""
  MIRROR_PYPI_TRUSTED_HOST=""
  MIRROR_DOCKER_CE=""
  MIRROR_DOCKER_HUB=""
  MIRROR_GITHUB_PROXY=""
  MIRROR_FNM_NODE_DIST=""
  log_info "区域: 海外 — 使用官方源"
}

# ─── 读取区域缓存 ─────────────────────────────────────────────────────────────
_read_region_cache() {
  if [[ -f "$_REGION_CACHE_FILE" ]]; then
    local cached
    cached=$(cat "$_REGION_CACHE_FILE")
    # 去除空白并验证
    cached="${cached//[[:space:]]/}"
    case "$cached" in
      cn|overseas) echo "$cached" ;;
      # 无效缓存值，忽略
    esac
  fi
}

# ─── 写入区域缓存 ─────────────────────────────────────────────────────────────
_write_region_cache() {
  local value="$1"
  # 仅允许合法的区域值
  case "$value" in
    cn|overseas) ;;
    *) value="overseas" ;;
  esac
  mkdir -p "$_REGION_CACHE_DIR"
  # 原子写入：先写临时文件再 mv，防止中断产生空文件
  local tmp_file="${_REGION_CACHE_FILE}.tmp"
  echo "$value" > "$tmp_file"
  mv "$tmp_file" "$_REGION_CACHE_FILE"
}

# ─── 交互式询问区域 ───────────────────────────────────────────────────────────
_ask_region() {
  echo ""
  echo "请选择您的网络区域 / Select your region:"
  echo "  1) 中国大陆 (China)    — 使用国内镜像加速"
  echo "  2) 海外 (Overseas)     — 使用官方源（默认）"
  echo ""
  local choice
  read -r -p "请输入 [1/2] (默认 2): " choice
  # 通过全局变量返回，避免在 $() 子 shell 中调用时 read 无法读取终端输入
  case "$choice" in
    1) _ASK_REGION_RESULT="cn" ;;
    *) _ASK_REGION_RESULT="overseas" ;;
  esac
}

# ─── 解析区域（核心函数）──────────────────────────────────────────────────────
# 优先级：--region 参数 > config.toml > 缓存文件 > 交互询问
# 参数: $1 = 命令行传入的 region 值（可为空）
#       $2 = 是否非交互模式 ("true"/"false")
resolve_region() {
  local cli_region="${1:-}"
  local non_interactive="${2:-false}"

  # 1. 命令行参数
  if [[ -n "$cli_region" ]]; then
    REGION="$cli_region"
    _write_region_cache "$REGION"
  fi

  # 2. 配置文件
  if [[ -z "$REGION" ]]; then
    local config_region
    config_region=$(config_get "region.value" "")
    if [[ -n "$config_region" ]]; then
      REGION="$config_region"
    fi
  fi

  # 3. 缓存文件
  if [[ -z "$REGION" ]]; then
    local cached
    cached=$(_read_region_cache)
    if [[ -n "$cached" ]]; then
      REGION="$cached"
    fi
  fi

  # 4. 交互询问（或非交互默认 overseas）
  if [[ -z "$REGION" ]]; then
    if [[ "$non_interactive" == "true" ]] || [[ ! -t 0 ]]; then
      REGION="overseas"
    else
      _ask_region
      REGION="$_ASK_REGION_RESULT"
      _write_region_cache "$REGION"
    fi
  fi

  # 应用镜像配置
  case "$REGION" in
    cn)       apply_cn_mirrors ;;
    overseas) apply_overseas_mirrors ;;
    *)
      log_warn "未知区域: $REGION，使用海外默认源。"
      REGION="overseas"
      apply_overseas_mirrors
      ;;
  esac

  # 允许配置文件手动覆盖个别镜像
  local override
  override=$(config_get "mirrors.apt" "")
  [[ -n "$override" ]] && MIRROR_APT="$override"
  override=$(config_get "mirrors.npm" "")
  [[ -n "$override" ]] && MIRROR_NPM="$override"
  override=$(config_get "mirrors.pypi" "")
  [[ -n "$override" ]] && MIRROR_PYPI="$override"
  override=$(config_get "mirrors.docker_ce" "")
  [[ -n "$override" ]] && MIRROR_DOCKER_CE="$override"
  override=$(config_get "mirrors.docker_hub" "")
  [[ -n "$override" ]] && MIRROR_DOCKER_HUB="$override"
  override=$(config_get "mirrors.github_proxy" "")
  [[ -n "$override" ]] && MIRROR_GITHUB_PROXY="$override"
  override=$(config_get "mirrors.fnm_node_dist" "")
  [[ -n "$override" ]] && MIRROR_FNM_NODE_DIST="$override"

  return 0
}

# ─── 获取 GitHub 下载 URL（自动加代理前缀）────────────────────────────────────
# 用法: github_url "https://github.com/user/repo/releases/download/v1/file"
github_url() {
  local url="$1"
  if [[ -n "$MIRROR_GITHUB_PROXY" ]]; then
    # 确保代理 URL 以 / 结尾
    local proxy="${MIRROR_GITHUB_PROXY%/}/"
    echo "${proxy}${url}"
  else
    echo "$url"
  fi
}
