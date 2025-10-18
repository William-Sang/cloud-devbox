#!/usr/bin/env bash
set -euo pipefail

# 帮助生成 SSH 密钥对的辅助脚本

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SSH_KEY_PATH=${1:-$ROOT_DIR/ssh/gcp_dev}
SSH_USERNAME=${2:-dev}

echo "=== GCP 开发机 SSH 密钥生成工具 ==="
echo ""
echo "默认生成位置: $SSH_KEY_PATH"
echo "默认用户名: $SSH_USERNAME"
echo ""

# 展开路径（如果用户传入了 ~ 路径）
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

# 确保 ssh 目录存在
mkdir -p "$(dirname "$SSH_KEY_PATH")"

# 检查密钥是否已存在
if [[ -f "$SSH_KEY_PATH" ]]; then
  echo "⚠️  SSH 密钥已存在: $SSH_KEY_PATH"
  read -p "是否覆盖？(y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消操作"
    exit 0
  fi
fi

# 生成密钥
echo "生成 SSH 密钥对..."
ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -C "$SSH_USERNAME" -N ""

echo ""
echo "✓ SSH 密钥生成成功！"
echo ""
echo "私钥: $SSH_KEY_PATH"
echo "公钥: ${SSH_KEY_PATH}.pub"
echo ""

# 设置正确的权限
chmod 600 "$SSH_KEY_PATH"
chmod 644 "${SSH_KEY_PATH}.pub"
echo "✓ 密钥权限已设置 (私钥: 600, 公钥: 644)"
echo ""

# 计算相对路径（如果在项目目录内）
if [[ "$SSH_KEY_PATH" == "$ROOT_DIR"* ]]; then
  RELATIVE_PRIVATE_KEY="${SSH_KEY_PATH#$ROOT_DIR/}"
  RELATIVE_PUBLIC_KEY="${SSH_KEY_PATH#$ROOT_DIR/}.pub"
else
  RELATIVE_PRIVATE_KEY="$SSH_KEY_PATH"
  RELATIVE_PUBLIC_KEY="${SSH_KEY_PATH}.pub"
fi

echo "下一步："
echo "1. 编辑 .env 文件，添加以下配置："
echo ""
echo "   SSH_USERNAME=$SSH_USERNAME"
echo "   SSH_PUBLIC_KEY_FILE=./$RELATIVE_PUBLIC_KEY"
echo ""
echo "2. 运行 bash scripts/start-dev.sh 启动虚拟机"
echo ""
echo "3. 配置 ~/.ssh/config："
echo ""
echo "   Host gcp-dev"
echo "     HostName <虚拟机外网IP>"
echo "     User $SSH_USERNAME"
echo "     IdentityFile $ROOT_DIR/$RELATIVE_PRIVATE_KEY"
echo "     ServerAliveInterval 60"
echo ""
echo "4. 连接: ssh gcp-dev"
echo ""
echo "注意: 密钥文件已在 .gitignore 中排除，不会被提交到 Git"
echo ""

