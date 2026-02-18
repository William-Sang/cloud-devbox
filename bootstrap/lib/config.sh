#!/usr/bin/env bash
# lib/config.sh — 轻量级 TOML 配置解析（纯 bash）
# 被其他脚本 source，不直接执行。

[[ -n "${_CONFIG_LOADED:-}" ]] && return 0
_CONFIG_LOADED=1

# 配置存储（关联数组）
declare -gA _CONFIG=()

# ─── 加载 TOML 文件 ────────────────────────────────────────────────────────────
# 用法: config_load "/path/to/file.toml"
# 支持基本 TOML: [section], key = "value", key = true/false
config_load() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local current_section=""
  local line key value

  while IFS= read -r line || [[ -n "$line" ]]; do
    # 去除前后空白
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # 跳过空行和注释
    [[ -z "$line" || "$line" == \#* ]] && continue

    # 匹配 section: [name] 或 [name.sub]
    if [[ "$line" =~ ^\[([a-zA-Z0-9._-]+)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      continue
    fi

    # 匹配 key = value
    if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"

      # 处理数组值: ["a", "b"] → "a b"（空格分隔）
      # 数组在去注释/引号前处理，因为内部含 "," 和引号
      if [[ "$value" == \[*\] ]]; then
        value="${value#\[}"
        value="${value%\]}"
        value="${value//\"/}"
        value="${value//,/ }"
        # 压缩空白
        value=$(echo "$value" | tr -s ' ')
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
      else
        # 非数组值：先去行内注释，再去引号
        # 顺序重要：避免引号值与注释中的引号混淆
        if [[ "$value" =~ ^([^#]*)[[:space:]]+#.*$ ]]; then
          value="${BASH_REMATCH[1]}"
          value="${value%"${value##*[![:space:]]}"}"
        fi
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
      fi

      # 存入关联数组
      if [[ -n "$current_section" ]]; then
        _CONFIG["${current_section}.${key}"]="$value"
      else
        _CONFIG["$key"]="$value"
      fi
    fi
  done < "$file"
}

# ─── 读取配置值 ────────────────────────────────────────────────────────────────
# 用法: config_get "python.default" → "3.12"
#       config_get "python.default" "fallback_value"
config_get() {
  local key="$1"
  local default="${2:-}"
  echo "${_CONFIG[$key]:-$default}"
}

# ─── 检查配置值是否为 true ─────────────────────────────────────────────────────
# 用法: config_is_true "node.package_managers.pnpm"
config_is_true() {
  local val
  val=$(config_get "$1" "false")
  [[ "$val" == "true" || "$val" == "yes" || "$val" == "1" ]]
}

# ─── 初始化配置 ────────────────────────────────────────────────────────────────
# 先加载默认配置，再用用户自定义配置覆盖
# 用法: config_init "/path/to/bootstrap"
config_init() {
  local bootstrap_dir="$1"
  local config_file="${2:-}"

  # 加载默认配置
  config_load "$bootstrap_dir/config.default.toml"

  # 加载用户自定义配置（覆盖默认值）
  if [[ -n "$config_file" && -f "$config_file" ]]; then
    config_load "$config_file"
  elif [[ -f "$bootstrap_dir/config.toml" ]]; then
    config_load "$bootstrap_dir/config.toml"
  fi
}
