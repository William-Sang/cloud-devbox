#!/usr/bin/env bash
set -euo pipefail

# 记录脚本开始时间
SCRIPT_START_TIME=$(date +%s)
SCRIPT_NAME=$(basename "$0")

# 在脚本退出时显示运行时长
cleanup_and_show_duration() {
  local exit_code=$?
  local end_time=$(date +%s)
  local duration=$((end_time - SCRIPT_START_TIME))
  local minutes=$((duration / 60))
  local seconds=$((duration % 60))
  
  echo ""
  if [ $minutes -gt 0 ]; then
    echo "[$SCRIPT_NAME] 运行时长: ${minutes}m ${seconds}s"
  else
    echo "[$SCRIPT_NAME] 运行时长: ${seconds}s"
  fi
  
  exit $exit_code
}

trap cleanup_and_show_duration EXIT

# SSH 公钥注入验证脚本

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
fi

GCP_PROJECT_ID=${GCP_PROJECT_ID:-}
GCP_ZONE=${GCP_ZONE:-asia-northeast1-a}
SSH_USERNAME=${SSH_USERNAME:-dev}

PROJECT_FLAGS=()
if [[ -n "$GCP_PROJECT_ID" ]]; then
  PROJECT_FLAGS+=(--project "$GCP_PROJECT_ID")
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           SSH 公钥注入验证工具                                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 检查 gcloud 是否安装
if ! command -v gcloud &> /dev/null; then
  echo "❌ gcloud CLI 未安装"
  echo ""
  echo "请先安装 gcloud："
  echo "  curl https://sdk.cloud.google.com | bash"
  echo "  exec -l \$SHELL"
  echo "  gcloud init"
  exit 1
fi

echo "✓ gcloud CLI 已安装"
echo ""

# 获取实例名
if [[ -f "$ROOT_DIR/.state/last_instance_name" ]]; then
  INSTANCE_NAME=$(cat "$ROOT_DIR/.state/last_instance_name")
  echo "实例名: $INSTANCE_NAME"
else
  echo "❌ 未找到实例记录"
  echo "请先运行: bash scripts/start-dev.sh"
  exit 1
fi

# 检查实例是否存在
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "检查虚拟机状态..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if ! gcloud "${PROJECT_FLAGS[@]}" compute instances describe "$INSTANCE_NAME" --zone "$GCP_ZONE" &> /dev/null; then
  echo "❌ 虚拟机不存在或已删除: $INSTANCE_NAME"
  echo ""
  echo "请运行: bash scripts/start-dev.sh"
  exit 1
fi

STATUS=$(gcloud "${PROJECT_FLAGS[@]}" compute instances describe "$INSTANCE_NAME" \
  --zone "$GCP_ZONE" --format='get(status)')

echo "✓ 虚拟机存在"
echo "  状态: $STATUS"

EXTERNAL_IP=$(gcloud "${PROJECT_FLAGS[@]}" compute instances describe "$INSTANCE_NAME" \
  --zone "$GCP_ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
echo "  外网 IP: $EXTERNAL_IP"

# 检查 SSH 密钥是否注入
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "检查 SSH 公钥注入..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

SSH_KEYS=$(gcloud "${PROJECT_FLAGS[@]}" compute instances describe "$INSTANCE_NAME" \
  --zone "$GCP_ZONE" --format="value(metadata.items.ssh-keys)" 2>/dev/null || echo "")

if [[ -z "$SSH_KEYS" ]]; then
  echo "❌ 虚拟机 metadata 中未找到 SSH 公钥"
  echo ""
  echo "可能原因："
  echo "  1. 虚拟机是在配置 SSH 前创建的"
  echo "  2. 启动脚本未正确执行"
  echo ""
  echo "解决方案："
  echo "  1. 删除当前虚拟机: bash scripts/destroy-dev.sh"
  echo "  2. 重新启动: bash scripts/start-dev.sh"
  exit 1
fi

echo "✓ 找到 SSH 公钥配置"
echo ""
echo "注入的 SSH 密钥："
echo "$SSH_KEYS" | while IFS= read -r line; do
  echo "  $line"
done

# 检查是否包含预期的用户名
if echo "$SSH_KEYS" | grep -q "^${SSH_USERNAME}:"; then
  echo ""
  echo "✅ 公钥已成功注入，用户名: $SSH_USERNAME"
else
  echo ""
  echo "⚠️  未找到用户 '$SSH_USERNAME' 的公钥"
  echo "找到的用户："
  echo "$SSH_KEYS" | cut -d':' -f1 | while IFS= read -r user; do
    echo "  - $user"
  done
fi

# 测试 SSH 连接
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "测试 SSH 连接..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ "$STATUS" != "RUNNING" ]]; then
  echo "⚠️  虚拟机未运行，无法测试连接"
  echo "请先启动虚拟机"
  exit 0
fi

SSH_KEY_PATH="$ROOT_DIR/ssh/gcp_dev"
if [[ ! -f "$SSH_KEY_PATH" ]]; then
  echo "❌ SSH 私钥不存在: $SSH_KEY_PATH"
  echo "请运行: bash scripts/setup-ssh-key.sh"
  exit 1
fi

echo "使用以下命令测试连接："
echo ""
echo "  ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USERNAME@$EXTERNAL_IP"
echo ""
echo "或配置 ~/.ssh/config 后使用: ssh gcp-dev"
echo ""

read -p "是否立即测试 SSH 连接？(y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo ""
  echo "正在测试连接..."
  if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       -o ConnectTimeout=10 "$SSH_USERNAME@$EXTERNAL_IP" "echo '✅ SSH 连接成功！'; hostname; whoami"; then
    echo ""
    echo "✅ SSH 公钥验证成功！"
  else
    echo ""
    echo "❌ SSH 连接失败"
    echo ""
    echo "可能原因："
    echo "  1. 虚拟机尚未完全启动（等待 1-2 分钟）"
    echo "  2. 防火墙规则未生效"
    echo "  3. 公钥未正确注入"
    echo ""
    echo "故障排查："
    echo "  1. 检查防火墙: gcloud compute firewall-rules list --filter='name=allow-ssh'"
    echo "  2. 使用 gcloud SSH 测试: gcloud compute ssh $INSTANCE_NAME --zone=$GCP_ZONE"
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "验证完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

