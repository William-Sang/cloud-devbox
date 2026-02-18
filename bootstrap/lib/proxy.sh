#!/usr/bin/env bash
# lib/proxy.sh — 代理解析与环境变量导出
# 被 init-devbox.sh source，在任何网络操作之前调用。

[[ -n "${_PROXY_LOADED:-}" ]] && return 0
_PROXY_LOADED=1

# 全局代理状态（由 resolve_proxy 设置）
PROXY_URL=""
PROXY_NO_PROXY=""

# ─── 解析并导出代理 ──────────────────────────────────────────────────────────
# 用法: resolve_proxy "$CLI_PROXY"
# 优先级: CLI --proxy > config.toml [proxy].url > 已有环境变量 $HTTP_PROXY
# 副作用: export HTTP_PROXY, HTTPS_PROXY, ALL_PROXY, NO_PROXY（及小写版本）
resolve_proxy() {
  local cli_proxy="${1:-}"

  # 1. CLI 参数
  if [[ -n "$cli_proxy" ]]; then
    PROXY_URL="$cli_proxy"
  fi

  # 2. config.toml
  if [[ -z "$PROXY_URL" ]]; then
    PROXY_URL=$(config_get "proxy.url" "")
  fi

  # 3. 已有环境变量
  if [[ -z "$PROXY_URL" ]]; then
    PROXY_URL="${HTTP_PROXY:-${http_proxy:-}}"
  fi

  # 未配置代理，直接返回
  if [[ -z "$PROXY_URL" ]]; then
    return 0
  fi

  # 校验 scheme
  case "$PROXY_URL" in
    http://*|https://*|socks5://*|socks5h://*)
      ;;
    *)
      log_warn "代理地址格式不支持: $PROXY_URL（支持 http://, socks5://, socks5h://）"
      PROXY_URL=""
      return 0
      ;;
  esac

  # 读取 no_proxy
  PROXY_NO_PROXY=$(config_get "proxy.no_proxy" "localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16")

  # 导出环境变量（大小写各一份，兼容不同工具）
  export HTTP_PROXY="$PROXY_URL"
  export HTTPS_PROXY="$PROXY_URL"
  export ALL_PROXY="$PROXY_URL"
  export NO_PROXY="$PROXY_NO_PROXY"
  export http_proxy="$PROXY_URL"
  export https_proxy="$PROXY_URL"
  export all_proxy="$PROXY_URL"
  export no_proxy="$PROXY_NO_PROXY"

  log_info "代理已启用: $PROXY_URL"
  log_dim "NO_PROXY: $PROXY_NO_PROXY"
}
