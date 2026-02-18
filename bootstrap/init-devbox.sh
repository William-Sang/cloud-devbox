#!/usr/bin/env bash
# init-devbox.sh — Ubuntu 全栈开发环境初始化 CLI
# 用法:
#   init-devbox apply [--region cn|overseas] [--all] [--module base,node,...] [--yes] [--non-interactive]
#   init-devbox doctor
#   init-devbox verify [--report-json <path>]
set -euo pipefail

SCRIPT_START_TIME=$(date +%s)
SCRIPT_NAME=$(basename "$0")
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── 加载基础库 ────────────────────────────────────────────────────────────────
# shellcheck source=lib/common.sh
source "$BOOTSTRAP_DIR/lib/common.sh"
# shellcheck source=lib/config.sh
source "$BOOTSTRAP_DIR/lib/config.sh"
# shellcheck source=lib/region.sh
source "$BOOTSTRAP_DIR/lib/region.sh"
# shellcheck source=lib/proxy.sh
source "$BOOTSTRAP_DIR/lib/proxy.sh"

# ─── EXIT trap（仅在实际执行子命令时打印耗时）──────────────────────────────────
_SHOW_DURATION=false
trap '[[ "$_SHOW_DURATION" == true ]] && echo "" && echo "[${SCRIPT_NAME}] 总耗时: $(show_duration ${SCRIPT_START_TIME})"' EXIT

# ─── 模块定义 ──────────────────────────────────────────────────────────────────
MODULE_ORDER=(proxy mirror base docker node python ai-tools shell-config)

declare -A MODULE_DESC=(
  [proxy]="代理配置（环境变量 + git + Docker 守护进程代理）"
  [mirror]="镜像源配置（根据区域自动设置 apt/npm/pypi 源）"
  [base]="基础系统工具 (git, curl, vim, tmux, ripgrep, jq 等)"
  [docker]="Docker Engine + docker-compose 插件"
  [node]="Node.js 生态 (fnm + Node LTS + pnpm + bun)"
  [python]="Python 生态 (uv + Python 3.12 + 3.13)"
  [ai-tools]="AI 编码工具 (Claude Code, OpenCode, Codex, Qoder, Gemini)"
  [shell-config]="Shell 配置 (别名, PS1 提示符, git 默认, 补全)"
)

declare -A MODULE_DEFAULT=(
  [proxy]="off"
  [mirror]="on"
  [base]="on"
  [docker]="off"
  [node]="on"
  [python]="on"
  [ai-tools]="off"
  [shell-config]="off"
)

# ─── 模块名到函数名映射 ───────────────────────────────────────────────────────
_module_func_name() {
  echo "install_${1//-/_}"
}

# ─── 使用帮助 ──────────────────────────────────────────────────────────────────
show_usage() {
  cat <<'EOF'
init-devbox — Ubuntu 全栈开发环境初始化工具

用法:
  init-devbox apply [选项]       安装开发环境
  init-devbox doctor             预检系统状态
  init-devbox verify [选项]      验证安装结果

apply 选项:
  --region cn|overseas    设置区域（cn=中国镜像, overseas=官方源）
  --proxy <url>           设置代理（http://host:port 或 socks5://host:port）
  --all                   安装所有模块
  --module m1,m2,...      指定安装的模块（逗号分隔）
  --yes                   跳过确认提示
  --non-interactive       非交互模式（CI/自动化）
  --config <file>         指定配置文件路径

verify 选项:
  --report-json <path>    导出 JSON 验证报告

可用模块:
  proxy         代理配置
  mirror        镜像源配置
  base          基础系统工具
  docker        Docker Engine
  node          Node.js 生态
  python        Python 生态
  ai-tools      AI 编码工具
  shell-config  Shell 配置

示例:
  # 交互式安装
  bash init-devbox.sh apply

  # 中国区域全量安装
  bash init-devbox.sh apply --region cn --all --yes

  # 仅安装基础 + Node + Python
  bash init-devbox.sh apply --module base,node,python --yes

  # 远程一键安装
  curl -fsSL https://raw.githubusercontent.com/William-Sang/cloud-devbox/main/bootstrap/install.sh | bash
EOF
}

# ─── 参数解析 ──────────────────────────────────────────────────────────────────
SUBCOMMAND=""
INSTALL_ALL=false
NON_INTERACTIVE=false
AUTO_YES=false
CLI_REGION=""
CLI_MODULES=""
CLI_PROXY=""
CONFIG_FILE=""
REPORT_JSON=""

parse_args() {
  if [[ $# -eq 0 ]]; then
    show_usage
    exit 0
  fi

  SUBCOMMAND="$1"
  shift

  local next_is=""
  for arg in "$@"; do
    if [[ -n "$next_is" ]]; then
      if [[ "$arg" == --* ]]; then
        log_error "--$next_is 参数缺少值"
        exit 1
      fi
      case "$next_is" in
        region)  CLI_REGION="$arg" ;;
        module)  CLI_MODULES="$arg" ;;
        proxy)   CLI_PROXY="$arg" ;;
        config)  CONFIG_FILE="$arg" ;;
        report)  REPORT_JSON="$arg" ;;
      esac
      next_is=""
      continue
    fi

    case "$arg" in
      --all)             INSTALL_ALL=true ;;
      --non-interactive) NON_INTERACTIVE=true; AUTO_YES=true ;;
      --yes|-y)          AUTO_YES=true ;;
      --region=*)        CLI_REGION="${arg#--region=}" ;;
      --region)          next_is="region" ;;
      --module=*)        CLI_MODULES="${arg#--module=}" ;;
      --module)          next_is="module" ;;
      --proxy=*)         CLI_PROXY="${arg#--proxy=}" ;;
      --proxy)           next_is="proxy" ;;
      --config=*)        CONFIG_FILE="${arg#--config=}" ;;
      --config)          next_is="config" ;;
      --report-json=*)   REPORT_JSON="${arg#--report-json=}" ;;
      --report-json)     next_is="report" ;;
      -h|--help)         show_usage; exit 0 ;;
      *)
        log_error "未知参数: $arg"
        show_usage
        exit 1
        ;;
    esac
  done

  # 检查是否有未消费的参数值
  if [[ -n "$next_is" ]]; then
    log_error "--$next_is 参数缺少值"
    exit 1
  fi

  # 校验 --region 值
  if [[ -n "$CLI_REGION" && "$CLI_REGION" != "cn" && "$CLI_REGION" != "overseas" ]]; then
    log_error "无效区域: $CLI_REGION（可选: cn, overseas）"
    exit 1
  fi
}

# ─── 交互式模块选择菜单 ───────────────────────────────────────────────────────
show_interactive_menu() {
  # 初始化选择状态
  local -a selections=()
  for mod in "${MODULE_ORDER[@]}"; do
    selections+=("${MODULE_DEFAULT[$mod]}")
  done

  while true; do
    echo ""
    echo "选择要安装的模块 (输入数字切换, a=全选, n=全不选, 回车确认):"
    echo ""
    local i=0
    for mod in "${MODULE_ORDER[@]}"; do
      local status="${selections[$i]}"
      local marker="[ ]"
      [[ "$status" == "on" ]] && marker="[x]"
      printf "  %d) %s %-14s %s\n" "$((i+1))" "$marker" "$mod" "${MODULE_DESC[$mod]}"
      i=$((i + 1))
    done
    echo ""
    read -r -p "选择 (或回车继续): " choice

    case "$choice" in
      "")  break ;;
      a|A) for j in "${!selections[@]}"; do selections[$j]="on"; done ;;
      n|N) for j in "${!selections[@]}"; do selections[$j]="off"; done ;;
      [1-9]*)
        local idx=$((choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#MODULE_ORDER[@]} ]]; then
          if [[ "${selections[$idx]}" == "on" ]]; then
            selections[$idx]="off"
          else
            selections[$idx]="on"
          fi
        fi
        ;;
    esac
  done

  # 收集选中的模块
  local result=()
  local i=0
  for mod in "${MODULE_ORDER[@]}"; do
    [[ "${selections[$i]}" == "on" ]] && result+=("$mod")
    i=$((i + 1))
  done
  # 通过全局变量返回结果，避免在 $() 子 shell 中运行导致 read 无法读取终端输入
  _MENU_RESULT="${result[*]}"
}

# ─── 确定要安装的模块 ─────────────────────────────────────────────────────────
resolve_modules() {
  local selected_modules=()

  if [[ "$INSTALL_ALL" == true ]]; then
    selected_modules=("${MODULE_ORDER[@]}")
  elif [[ -n "$CLI_MODULES" ]]; then
    # 解析逗号分隔的模块列表
    IFS=',' read -ra selected_modules <<< "$CLI_MODULES"
    # 验证模块名
    for mod in "${selected_modules[@]}"; do
      if [[ -z "${MODULE_DESC[$mod]:-}" ]]; then
        log_error "未知模块: $mod"
        log_error "可用模块: ${MODULE_ORDER[*]}"
        exit 1
      fi
    done
  elif [[ "$NON_INTERACTIVE" == true ]]; then
    # 非交互模式使用默认值
    for mod in "${MODULE_ORDER[@]}"; do
      [[ "${MODULE_DEFAULT[$mod]}" == "on" ]] && selected_modules+=("$mod")
    done
  else
    # 交互式菜单（直接调用，不在 $() 子 shell 中，确保 read 能访问终端）
    show_interactive_menu
    read -ra selected_modules <<< "$_MENU_RESULT"
  fi

  # 依赖强制: ai-tools 需要 node
  if [[ " ${selected_modules[*]} " == *" ai-tools "* ]]; then
    if [[ " ${selected_modules[*]} " != *" node "* ]] && ! check_command node; then
      log_warn "ai-tools 需要 Node.js，自动添加 node 模块。"
      selected_modules=("node" "${selected_modules[@]}")
    fi
  fi

  # 通过全局变量返回，避免 $() 子 shell 导致内部交互式 read 失败
  _RESOLVED_MODULES="${selected_modules[*]}"
}

# ─── 执行模块安装 ─────────────────────────────────────────────────────────────
run_modules() {
  local modules=("$@")
  local -a results=()
  local total=${#modules[@]}
  local current=0

  for mod in "${MODULE_ORDER[@]}"; do
    if [[ " ${modules[*]} " == *" ${mod} "* ]]; then
      current=$((current + 1))
      local mod_start
      mod_start=$(date +%s)

      echo ""
      print_separator
      log_info "[$current/$total] 模块: $mod"

      # source 模块文件并调用安装函数
      local mod_file="$BOOTSTRAP_DIR/modules/${mod}.sh"
      if [[ ! -f "$mod_file" ]]; then
        log_error "模块文件不存在: $mod_file"
        results+=("${mod}|FAIL|0s")
        continue
      fi

      # shellcheck disable=SC1090
      source "$mod_file"

      local func_name
      func_name=$(_module_func_name "$mod")

      if "$func_name" 2>&1; then
        local dur
        dur=$(show_duration "$mod_start")
        results+=("${mod}|OK|${dur}")
      else
        local dur
        dur=$(show_duration "$mod_start")
        results+=("${mod}|FAIL|${dur}")
      fi
    fi
  done

  # ── 打印汇总 ────────────────────────────────────────────────────────────────
  echo ""
  echo ""
  print_separator
  echo -e "${_C_BOLD}安装结果汇总${_C_RESET}"
  print_separator
  printf "  %-14s %-8s %s\n" "模块" "状态" "耗时"
  print_separator

  local ok_count=0 fail_count=0
  for result in "${results[@]}"; do
    local mod="${result%%|*}"
    local rest="${result#*|}"
    local status="${rest%%|*}"
    local dur="${rest#*|}"

    if [[ "$status" == "OK" ]]; then
      printf "  %-14s ${_C_GREEN}%-8s${_C_RESET} %s\n" "$mod" "OK" "$dur"
      ok_count=$((ok_count + 1))
    else
      printf "  %-14s ${_C_RED}%-8s${_C_RESET} %s\n" "$mod" "FAIL" "$dur"
      fail_count=$((fail_count + 1))
    fi
  done

  print_separator
  log_info "区域: $REGION | 成功: $ok_count | 失败: $fail_count"

  if [[ $fail_count -gt 0 ]]; then
    log_warn "部分模块安装失败，可单独重试。"
  fi

  echo ""
  log_info "请重启 shell 或运行: source ~/.bashrc"
}

# ─── 子命令: apply ─────────────────────────────────────────────────────────────
cmd_apply() {
  _SHOW_DURATION=true
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║       init-devbox — Ubuntu 全栈开发环境初始化工具       ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  # 日志记录
  setup_logging
  log_info "日志文件: $LOG_FILE"

  # 预检
  check_ubuntu || exit 1
  ensure_sudo  || exit 1

  # 初始化配置
  config_init "$BOOTSTRAP_DIR" "$CONFIG_FILE"

  # 代理（必须在任何网络操作之前）
  resolve_proxy "$CLI_PROXY"

  # 确定区域
  local non_interactive_flag="false"
  [[ "$NON_INTERACTIVE" == true ]] && non_interactive_flag="true"
  resolve_region "$CLI_REGION" "$non_interactive_flag"

  # 确定模块（直接调用，不在 $() 中，确保交互式菜单能正常读取终端输入）
  resolve_modules
  local selected="$_RESOLVED_MODULES"

  if [[ -z "$selected" ]]; then
    log_warn "未选择任何模块，退出。"
    exit 0
  fi

  local -a modules
  read -ra modules <<< "$selected"

  # 确认
  echo ""
  log_info "将安装以下模块: ${modules[*]}"
  if [[ "$AUTO_YES" != true ]]; then
    read -r -p "继续？[Y/n] " confirm
    case "$confirm" in
      [nN]*) log_info "已取消。"; exit 0 ;;
    esac
  fi

  # 执行
  run_modules "${modules[@]}"

  # 自动运行验证（传入已安装模块列表，使验证结果与选择一致）
  # run_verify 在有失败项时返回非零，不应触发 set -e 退出
  echo ""
  source "$BOOTSTRAP_DIR/modules/verify.sh"
  run_verify "$REPORT_JSON" "${modules[*]}" || true

  # 日志提示
  echo ""
  log_info "完整日志已保存: $LOG_FILE"
}

# ─── 子命令: doctor ────────────────────────────────────────────────────────────
cmd_doctor() {
  _SHOW_DURATION=true
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║               init-devbox doctor — 系统预检             ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  config_init "$BOOTSTRAP_DIR" "$CONFIG_FILE"

  # 尝试读取缓存区域（通过验证的读取函数）
  local cached_region
  cached_region=$(_read_region_cache)
  if [[ -n "$cached_region" ]]; then
    REGION="$cached_region"
  fi

  source "$BOOTSTRAP_DIR/modules/preflight.sh"
  # run_preflight 在有失败项时返回非零，不应触发 set -e 退出
  run_preflight || true
}

# ─── 子命令: verify ────────────────────────────────────────────────────────────
cmd_verify() {
  _SHOW_DURATION=true
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║             init-devbox verify — 安装验证               ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  config_init "$BOOTSTRAP_DIR" "$CONFIG_FILE"

  # 读取缓存区域（通过验证的读取函数）
  local cached_region
  cached_region=$(_read_region_cache)
  if [[ -n "$cached_region" ]]; then
    REGION="$cached_region"
  fi
  check_ubuntu 2>/dev/null || true

  source "$BOOTSTRAP_DIR/modules/verify.sh"
  run_verify "$REPORT_JSON" || true
}

# ─── 主入口 ────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  case "$SUBCOMMAND" in
    apply)   cmd_apply ;;
    doctor)  cmd_doctor ;;
    verify)  cmd_verify ;;
    help|-h|--help) show_usage ;;
    *)
      log_error "未知子命令: $SUBCOMMAND"
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
