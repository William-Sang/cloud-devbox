#!/usr/bin/env bash
set -euo pipefail

# 将 WSL 中的 SSH 密钥同步到 Windows 用户目录

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        SSH 密钥同步工具 (WSL → Windows)                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 1. 检测 Windows 用户名
echo "[1/5] 检测 Windows 用户名..."
if WINDOWS_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' | tr -d '\n'); then
  if [[ -z "$WINDOWS_USER" ]]; then
    echo "❌ 无法自动检测 Windows 用户名"
    read -p "请手动输入 Windows 用户名: " WINDOWS_USER
  else
    echo "✓ 检测到 Windows 用户名: $WINDOWS_USER"
  fi
else
  echo "❌ 无法执行 cmd.exe"
  read -p "请手动输入 Windows 用户名: " WINDOWS_USER
fi

WINDOWS_SSH_DIR="/mnt/c/Users/${WINDOWS_USER}/.ssh"
WSL_SSH_DIR="$ROOT_DIR/ssh"

echo ""
echo "源目录 (WSL):     $WSL_SSH_DIR"
echo "目标目录 (Windows): $WINDOWS_SSH_DIR"
echo ""

# 2. 检查源密钥是否存在
echo "[2/5] 检查 WSL 密钥文件..."
if [[ ! -f "$WSL_SSH_DIR/gcp_dev" ]]; then
  echo "❌ 私钥不存在: $WSL_SSH_DIR/gcp_dev"
  echo ""
  echo "请先运行: bash scripts/setup-ssh-key.sh"
  exit 1
fi

if [[ ! -f "$WSL_SSH_DIR/gcp_dev.pub" ]]; then
  echo "❌ 公钥不存在: $WSL_SSH_DIR/gcp_dev.pub"
  exit 1
fi

echo "✓ 找到私钥: gcp_dev"
echo "✓ 找到公钥: gcp_dev.pub"

# 3. 创建 Windows .ssh 目录
echo ""
echo "[3/5] 创建 Windows .ssh 目录..."
if [[ ! -d "$WINDOWS_SSH_DIR" ]]; then
  mkdir -p "$WINDOWS_SSH_DIR"
  echo "✓ 已创建目录: $WINDOWS_SSH_DIR"
else
  echo "✓ 目录已存在: $WINDOWS_SSH_DIR"
fi

# 4. 检查是否已存在文件
echo ""
echo "[4/5] 检查目标文件..."
OVERWRITE=false
if [[ -f "$WINDOWS_SSH_DIR/gcp_dev" ]]; then
  echo "⚠️  目标文件已存在: gcp_dev"
  read -p "是否覆盖？(y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    OVERWRITE=true
  else
    echo "取消操作"
    exit 0
  fi
fi

# 5. 复制密钥文件
echo ""
echo "[5/5] 复制密钥文件..."
cp "$WSL_SSH_DIR/gcp_dev" "$WINDOWS_SSH_DIR/"
cp "$WSL_SSH_DIR/gcp_dev.pub" "$WINDOWS_SSH_DIR/"

echo "✓ 已复制: gcp_dev"
echo "✓ 已复制: gcp_dev.pub"

# 验证复制结果
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 密钥同步完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Windows 密钥位置："
echo "  私钥: C:\\Users\\${WINDOWS_USER}\\.ssh\\gcp_dev"
echo "  公钥: C:\\Users\\${WINDOWS_USER}\\.ssh\\gcp_dev.pub"
echo ""

# 6. 提供后续步骤
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 接下来需要在 Windows 中操作："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1️⃣  设置私钥文件权限（在 Windows PowerShell 中执行）："
echo ""
echo "    # 移除继承权限"
echo "    icacls \$env:USERPROFILE\\.ssh\\gcp_dev /inheritance:r"
echo ""
echo "    # 只允许当前用户读取"
echo "    icacls \$env:USERPROFILE\\.ssh\\gcp_dev /grant:r \"\$env:USERNAME\`:R\""
echo ""
echo "2️⃣  配置 SSH config (可选，创建 C:\\Users\\${WINDOWS_USER}\\.ssh\\config)："
echo ""
echo "    Host gcp-dev"
echo "      HostName <虚拟机外网IP>"
echo "      User dev"
echo "      IdentityFile C:\\Users\\${WINDOWS_USER}\\.ssh\\gcp_dev"
echo "      ServerAliveInterval 60"
echo ""
echo "3️⃣  在 Cursor 中使用 Remote-SSH："
echo ""
echo "    - 安装 Remote-SSH 扩展"
echo "    - 点击左下角 ><  图标"
echo "    - 选择 'Connect to Host'"
echo "    - 输入 gcp-dev 或虚拟机 IP"
echo ""
echo "4️⃣  或者直接使用 SSH 命令："
echo ""
echo "    ssh -i C:\\Users\\${WINDOWS_USER}\\.ssh\\gcp_dev dev@<虚拟机IP>"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 提示："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  • 密钥已复制到 Windows，可以在 Windows 环境直接使用"
echo "  • WSL 中的密钥保持不变，仍可在 WSL 中使用"
echo "  • 建议在 Windows 中设置权限后再使用"
echo "  • 可以删除 WSL 中的密钥，只保留 Windows 版本"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 生成 PowerShell 脚本
POWERSHELL_SCRIPT="/mnt/c/Users/${WINDOWS_USER}/set-ssh-permissions.ps1"
cat > "$POWERSHELL_SCRIPT" <<'EOF'
# SSH 密钥权限设置脚本
# 自动设置 gcp_dev 私钥的正确权限

Write-Host "=== SSH 密钥权限设置工具 ===" -ForegroundColor Cyan
Write-Host ""

$sshKey = "$env:USERPROFILE\.ssh\gcp_dev"

if (-not (Test-Path $sshKey)) {
    Write-Host "❌ 私钥文件不存在: $sshKey" -ForegroundColor Red
    exit 1
}

Write-Host "✓ 找到私钥文件: $sshKey" -ForegroundColor Green
Write-Host ""
Write-Host "正在设置权限..." -ForegroundColor Yellow

# 移除继承权限
icacls $sshKey /inheritance:r | Out-Null

# 只允许当前用户读取
icacls $sshKey /grant:r "$env:USERNAME`:R" | Out-Null

Write-Host "✓ 权限设置完成" -ForegroundColor Green
Write-Host ""
Write-Host "当前权限:" -ForegroundColor Cyan
icacls $sshKey
Write-Host ""
Write-Host "现在可以使用此密钥进行 SSH 连接了！" -ForegroundColor Green
EOF

echo "📝 已生成权限设置脚本（可选）："
echo "   C:\\Users\\${WINDOWS_USER}\\set-ssh-permissions.ps1"
echo ""
echo "   在 Windows PowerShell 中运行："
echo "   cd ~; .\\set-ssh-permissions.ps1"
echo ""

