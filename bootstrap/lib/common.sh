#!/usr/bin/env bash
# lib/common.sh — 共享基础库
# 被其他脚本 source，不直接执行。

# 防止重复加载
[[ -n "${_COMMON_LOADED:-}" ]] && return 0
_COMMON_LOADED=1

# ─── 颜色设置 ──────────────────────────────────────────────────────────────────
# 尊重 NO_COLOR 环境变量和非 TTY 环境
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  _C_BLUE='\033[0;34m'
  _C_GREEN='\033[0;32m'
  _C_YELLOW='\033[1;33m'
  _C_RED='\033[0;31m'
  _C_BOLD='\033[1m'
  _C_DIM='\033[2m'
  _C_RESET='\033[0m'
else
  _C_BLUE='' _C_GREEN='' _C_YELLOW='' _C_RED=''
  _C_BOLD='' _C_DIM='' _C_RESET=''
fi

# ─── 日志函数 ──────────────────────────────────────────────────────────────────
log_info()    { echo -e "${_C_BLUE}[INFO]${_C_RESET}    $*"; }
log_success() { echo -e "${_C_GREEN}[OK]${_C_RESET}      $*"; }
log_warn()    { echo -e "${_C_YELLOW}[WARN]${_C_RESET}    $*"; }
log_error()   { echo -e "${_C_RED}[ERROR]${_C_RESET}   $*" >&2; }
log_step()    { echo -e "\n${_C_BOLD}==> $*${_C_RESET}"; }
log_dim()     { echo -e "${_C_DIM}    $*${_C_RESET}"; }

# ─── 命令存在检查 ──────────────────────────────────────────────────────────────
# 用法: check_command docker
check_command() {
  command -v "$1" &>/dev/null
}

# ─── Ubuntu 检测 ───────────────────────────────────────────────────────────────
# 设置全局变量 UBUNTU_VERSION_ID 和 UBUNTU_CODENAME
# 返回 0=Ubuntu, 1=非 Ubuntu
check_ubuntu() {
  if [[ ! -f /etc/os-release ]]; then
    log_error "找不到 /etc/os-release，此脚本仅支持 Ubuntu。"
    return 1
  fi

  # 读取 /etc/os-release 一次，避免多次子 shell
  local os_id os_version os_codename
  eval "$(. /etc/os-release && printf 'os_id=%s\nos_version=%s\nos_codename=%s\n' "$ID" "$VERSION_ID" "$VERSION_CODENAME")"

  if [[ "$os_id" != "ubuntu" ]]; then
    log_error "此脚本仅支持 Ubuntu，当前系统: $os_id"
    return 1
  fi

  UBUNTU_VERSION_ID="$os_version"
  UBUNTU_CODENAME="$os_codename"

  case "$os_version" in
    22.04|24.04)
      log_info "检测到 Ubuntu $os_version ($os_codename)"
      ;;
    *)
      log_warn "未经测试的 Ubuntu 版本: $os_version，继续执行..."
      ;;
  esac
  return 0
}

# ─── Sudo 权限检查 ─────────────────────────────────────────────────────────────
# 确保当前用户可以执行 sudo 命令
ensure_sudo() {
  if [[ $EUID -eq 0 ]]; then
    # 直接以 root 运行时，修正 HOME 指向原用户
    if [[ -n "${SUDO_USER:-}" ]]; then
      ACTUAL_USER="$SUDO_USER"
      ACTUAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
      export HOME="$ACTUAL_HOME"
    else
      ACTUAL_USER="root"
      ACTUAL_HOME="$HOME"
      log_warn "直接以 root 运行。用户级工具（fnm, uv, bun）将安装到 /root。"
      log_warn "建议以普通用户 + sudo 方式运行。"
    fi
    return 0
  fi

  ACTUAL_USER="$USER"
  ACTUAL_HOME="$HOME"

  if sudo -n true 2>/dev/null; then
    log_info "sudo 权限已确认。"
    return 0
  fi

  log_info "需要 sudo 权限，可能会提示输入密码。"
  if ! sudo true; then
    log_error "无法获取 sudo 权限。请以 sudo 或 root 身份运行。"
    return 1
  fi
  return 0
}

# ─── 幂等 .bashrc 写入 ────────────────────────────────────────────────────────
# 用法: add_to_bashrc "MARKER_TAG" "line1" "line2" ...
# 使用 BEGIN/END 标记块，重复运行不会重复添加
add_to_bashrc() {
  local marker="$1"
  shift
  local target_file="${HOME}/.bashrc"
  local begin_marker="# BEGIN_INIT_${marker}"
  local end_marker="# END_INIT_${marker}"

  # 已存在则跳过
  if grep -qF "$begin_marker" "$target_file" 2>/dev/null; then
    log_dim "${marker} 配置已存在于 .bashrc，跳过。"
    return 0
  fi

  # 确保文件存在
  [[ -f "$target_file" ]] || touch "$target_file"

  # 追加标记块
  {
    echo ""
    echo "$begin_marker"
    for line in "$@"; do
      echo "$line"
    done
    echo "$end_marker"
  } >> "$target_file"

  log_dim "已添加 ${marker} 配置到 .bashrc"
}

# ─── 时长显示 ──────────────────────────────────────────────────────────────────
# 用法: show_duration <start_epoch_seconds>
show_duration() {
  local start_time="$1"
  local end_time duration minutes seconds
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  minutes=$((duration / 60))
  seconds=$((duration % 60))
  if [[ $minutes -gt 0 ]]; then
    echo "${minutes}m ${seconds}s"
  else
    echo "${seconds}s"
  fi
}

# ─── 分割线 ────────────────────────────────────────────────────────────────────
print_separator() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ─── 网络连通性检测 ────────────────────────────────────────────────────────────
# 用法: check_url "https://example.com" [timeout_seconds]
check_url() {
  local url="$1"
  local timeout="${2:-5}"
  curl --connect-timeout "$timeout" -fsSL -o /dev/null "$url" 2>/dev/null
}

# ─── 带重试的文件下载 ────────────────────────────────────────────────────────
# 用法: curl_download <url> <output_file> [max_retries]
# 返回: 0=成功, 1=所有重试均失败
curl_download() {
  local url="$1"
  local output="$2"
  local max_retries="${3:-3}"
  local attempt=1
  local wait_sec=2

  while [[ $attempt -le $max_retries ]]; do
    if curl -fsSL "$url" -o "$output" 2>/dev/null; then
      return 0
    fi
    if [[ $attempt -lt $max_retries ]]; then
      log_warn "下载失败 (${attempt}/${max_retries})，${wait_sec}s 后重试..."
      sleep "$wait_sec"
      wait_sec=$((wait_sec * 2))
    fi
    attempt=$((attempt + 1))
  done

  log_error "下载失败（已重试 ${max_retries} 次）: $url"
  return 1
}

# ─── GitHub 文件下载（直连 + 代理回退）─────────────────────────────────────────
# 用法: github_download <github_url> <output_file>
# 先尝试官方直连；若失败且配置了 MIRROR_GITHUB_PROXY，则回退到代理下载。
github_download() {
  local url="$1"
  local output="$2"

  # 先尝试官方直连
  if curl_download "$url" "$output"; then
    return 0
  fi

  # 有代理则回退到代理
  if [[ -n "${MIRROR_GITHUB_PROXY:-}" ]]; then
    local proxy="${MIRROR_GITHUB_PROXY%/}/"
    log_warn "直连失败，尝试 GitHub 镜像: ${proxy}"
    curl_download "${proxy}${url}" "$output"
    return $?
  fi

  return 1
}

# ─── 带重试的下载 + 管道执行 ──────────────────────────────────────────────────
# 用法: curl_pipe <url> <command...>
#   例: curl_pipe "https://example.com/install.sh" bash
#   例: curl_pipe "https://example.com/gpg" sudo gpg --dearmor -o /path/to/file
# 先下载到临时文件（带重试），再将内容管道到指定命令。
curl_pipe() {
  local url="$1"
  shift
  local tmp_file
  tmp_file=$(mktemp)

  if ! curl_download "$url" "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi

  "$@" < "$tmp_file"
  local rc=$?
  rm -f "$tmp_file"
  return $rc
}

# ─── 日志文件设置 ────────────────────────────────────────────────────────────
# 用法: setup_logging
# 在 cmd_apply() 开头调用。所有后续输出同时写入终端和日志文件。
LOG_FILE=""

setup_logging() {
  local log_dir="${HOME}/.config/init-devbox/logs"
  mkdir -p "$log_dir"

  LOG_FILE="${log_dir}/install-$(date '+%Y%m%d-%H%M%S').log"

  # stdout + stderr 同时写入终端和日志文件
  exec > >(tee -a "$LOG_FILE") 2>&1

  # 清理旧日志：保留最近 5 个
  local -a old_logs
  mapfile -t old_logs < <(ls -1t "$log_dir"/install-*.log 2>/dev/null | tail -n +6)
  if [[ ${#old_logs[@]} -gt 0 ]]; then
    rm -f "${old_logs[@]}"
  fi
}
