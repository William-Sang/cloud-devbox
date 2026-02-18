# Builder 配置指南

## 🎯 功能说明

`build-image.sh` 通过 metadata 将配置脚本传入 builder 实例，用户需要手动 SSH 登录后执行脚本。
这种方式方便实时查看输出和调试。

## 🚀 快速开始

### 1. 创建 Builder 实例

```bash
bash scripts/build-image.sh create-builder
```

脚本会自动：
- ✓ 创建 builder 实例
- ✓ 通过 metadata 传入 `scripts/builder-setup.sh`
- ✓ 将脚本保存到实例的 `~/builder-setup.sh`

### 2. SSH 登录并执行配置脚本

```bash
# 等待 30 秒让实例启动
gcloud compute ssh dev-builder --zone=asia-northeast1-a

# 执行配置脚本（实时查看输出）
sudo bash ~/builder-setup.sh
```

**配置时间**：约 5-10 分钟（取决于网络）

`builder-setup.sh` 会自动调用 `bootstrap/init-devbox.sh` 安装全部开发工具。

### 3. 关机并创建镜像

```bash
# 在 builder 实例中关机
sudo poweroff

# 回到本地，创建镜像（必须等实例完全停止）
bash scripts/build-image.sh create-image
```

### 4. 清理

```bash
bash scripts/build-image.sh delete-builder
```

## 🛠️ 自定义配置

### 默认安装内容

`scripts/builder-setup.sh` 委托 `bootstrap/init-devbox.sh` 安装：

- **系统工具**：curl, wget, git, vim, tmux, htop, build-essential, ripgrep, jq
- **Docker**：Docker Engine + Docker Compose 插件
- **Node.js**：fnm + Node.js LTS + pnpm + bun
- **Python**：uv + Python 3.12 + 3.13
- **AI 工具**：Claude Code, OpenCode, Codex, Qoder, Gemini CLI
- **Shell 配置**：别名, git-aware PS1, git 默认, 补全
- **其他**：Vim (amix/vimrc), Git 配置, SSH 密钥, /workspace 目录

### 添加自定义配置

在 builder 实例中执行 `builder-setup.sh` 后，可以手动安装额外工具：

```bash
# SSH 进入 builder
gcloud compute ssh dev-builder --zone asia-northeast1-a

# 执行基础配置
sudo bash ~/builder-setup.sh

# 安装额外工具
sudo apt-get install -y neovim
# ...

# 完成后关机
sudo poweroff
```

### 常见配置示例

#### 安装 Go

```bash
echo "安装 Go..."
GO_VERSION="1.21.5"
wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
rm go${GO_VERSION}.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
echo 'export GOPATH=$HOME/go' >> /etc/profile
```

#### 安装 Rust

```bash
echo "安装 Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env
```

#### 安装 Python 包

```bash
echo "安装 Python 包..."
uv tool install ruff
uv tool install black
# 或在项目虚拟环境中:
# uv pip install requests pandas numpy
```

#### 配置 vim/nvim

```bash
echo "配置 Neovim..."
apt-get install -y neovim

cat > ~/.vimrc <<'VIMEOF'
set number
set expandtab
set tabstop=2
set shiftwidth=2
syntax on
VIMEOF
```

## 📋 完整工作流程

```bash
# 1. (可选) 自定义 bootstrap 配置
vim bootstrap/config.default.toml

# 2. 创建 builder 实例
bash scripts/build-image.sh create-builder

# 3. 等待 30 秒后，SSH 登录并执行配置
gcloud compute ssh dev-builder --zone asia-northeast1-a
sudo bash ~/builder-setup.sh

# 4. 验证安装
docker --version
fnm --version
node --version
uv --version
python --version

# 5. 如需额外配置，现在操作；否则关机
sudo poweroff

# 6. 创建镜像（需等实例完全停止）
bash scripts/build-image.sh create-image

# 7. 清理 builder
bash scripts/build-image.sh delete-builder

# 8. 使用新镜像启动开发机
# 确保 .env 中配置了正确的 IMAGE_FAMILY
bash scripts/start-dev.sh
```

## 🔍 故障排查

### 配置脚本失败

如果配置脚本执行失败：

1. **查看错误信息**：脚本会实时输出到终端，查看最后的错误信息

2. **手动重新执行**：
   ```bash
   sudo bash ~/builder-setup.sh
   ```

3. **调试配置脚本**：
   ```bash
   # 使用 -x 查看详细执行过程
   sudo bash -x ~/builder-setup.sh
   ```

### 镜像创建失败

```bash
# 检查 builder 实例状态（必须为 TERMINATED 或 STOPPED）
gcloud compute instances describe dev-builder --zone asia-northeast1-a --format='get(status)'

# 如果实例还在运行，先停止
gcloud compute instances stop dev-builder --zone asia-northeast1-a

# 重试创建镜像
bash scripts/build-image.sh create-image
```

## 💡 最佳实践

1. **版本控制**：将 `builder-setup.sh` 和 `bootstrap/` 配置提交到 Git，团队共享配置

2. **测试驱动**：在本地 Docker 容器中测试 bootstrap：
   ```bash
   docker run -it ubuntu:24.04 bash
   # 安装 git, curl, 然后运行 bootstrap/init-devbox.sh
   ```

3. **定期更新**：定期重新构建镜像以获取安全更新

4. **文档化**：在 `bootstrap/config.toml` 中记录自定义配置

## 🔐 安全提醒

- ✅ 不要在配置脚本中硬编码密码或密钥
- ✅ 使用环境变量或 GCP Secret Manager
- ✅ 创建镜像前清理敏感信息
- ✅ 定期更新基础镜像和依赖

## 📚 相关文档

- [BUILDER_WORKFLOW.md](BUILDER_WORKFLOW.md) - Builder 工作流程详解
- [SSH_KEY_MANAGEMENT.md](SSH_KEY_MANAGEMENT.md) - SSH 密钥管理方案
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - 快速参考手册
- [bootstrap/USAGE.md](../bootstrap/USAGE.md) - Bootstrap 安装器使用文档

---

**最后更新**: 2026-02-18
