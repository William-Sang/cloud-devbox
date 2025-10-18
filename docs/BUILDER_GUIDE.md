# Builder 自动化配置指南

## 🎯 功能说明

现在创建 builder 实例时会自动执行配置脚本，无需手动 SSH 进入安装依赖。

## 🚀 快速开始

### 1. 创建 Builder（自动配置）

```bash
bash scripts/build-image.sh create-builder
```

脚本会自动：
- ✓ 创建 builder 实例
- ✓ 执行 `scripts/builder-setup.sh` 配置脚本
- ✓ 安装 Docker, Node.js, Python 等工具
- ✓ 配置开发环境

**配置时间**：约 3-5 分钟

### 2. 查看配置进度

```bash
# 方法 1：查看串行端口输出（推荐）
gcloud compute instances get-serial-port-output dev-builder --zone asia-northeast1-a

# 方法 2：SSH 进入查看
gcloud compute ssh dev-builder --zone asia-northeast1-a

# 方法 3：查看实例状态
gcloud compute instances describe dev-builder --zone asia-northeast1-a
```

### 3. 等待配置完成

配置完成后，可以：

**选项 A：直接关机并创建镜像**
```bash
# SSH 进入 builder
gcloud compute ssh dev-builder --zone asia-northeast1-a

# 关机
sudo poweroff
```

**选项 B：添加额外配置后再关机**
```bash
# SSH 进入 builder
gcloud compute ssh dev-builder --zone asia-northeast1-a

# 安装额外工具
# ...

# 完成后关机
sudo poweroff
```

### 4. 创建镜像

```bash
# 等待实例完全停止后
bash scripts/build-image.sh create-image
```

### 5. 清理

```bash
bash scripts/build-image.sh delete-builder
```

## 🛠️ 自定义配置

### 默认安装内容

`scripts/builder-setup.sh` 默认安装：

- **系统工具**：curl, wget, git, vim, tmux, htop, build-essential
- **Docker**：Docker Engine + Docker Compose
- **Node.js**：最新 LTS 版本 + npm
- **Python**：Python 3 + pip + venv
- **工作目录**：/workspace

### 添加自定义配置

编辑 `scripts/builder-setup.sh`，在 "自定义安装内容" 部分添加：

```bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 自定义安装内容
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 示例：安装 Go
echo "安装 Go..."
wget -q https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile

# 示例：安装 Rust
echo "安装 Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# 示例：安装 Cursor Server（推荐）
echo "安装 Cursor Server..."
# 添加安装命令...

# 您的自定义内容...
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

#### 安装特定 Python 包

```bash
echo "安装 Python 包..."
pip3 install --quiet \
  requests \
  pandas \
  numpy \
  flask \
  fastapi \
  uvicorn
```

#### 配置 Docker Compose 项目

```bash
echo "准备 Docker 项目..."
cd /workspace
git clone https://github.com/your/project.git
cd project
docker-compose pull
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
# 1. 自定义配置脚本
vim scripts/builder-setup.sh

# 2. 创建并自动配置 builder
bash scripts/build-image.sh create-builder

# 3. 查看配置进度（可选）
gcloud compute instances get-serial-port-output dev-builder \
  --zone asia-northeast1-a

# 4. 等待 3-5 分钟后，SSH 进入验证（可选）
gcloud compute ssh dev-builder --zone asia-northeast1-a

# 5. 验证安装
docker --version
node --version
python3 --version

# 6. 如需额外配置，现在操作；否则关机
sudo poweroff

# 7. 创建镜像
bash scripts/build-image.sh create-image

# 8. 清理 builder
bash scripts/build-image.sh delete-builder

# 9. 使用新镜像启动开发机
# 确保 .env 中配置了正确的 IMAGE_FAMILY
bash scripts/start-dev.sh
```

## 🔍 故障排查

### 查看配置脚本执行日志

```bash
# 实时查看串行端口输出
gcloud compute instances tail-serial-port-output dev-builder \
  --zone asia-northeast1-a

# 或 SSH 进入查看系统日志
gcloud compute ssh dev-builder --zone asia-northeast1-a
sudo journalctl -u google-startup-scripts.service
```

### 配置脚本失败

如果配置脚本执行失败：

1. **查看错误日志**：
   ```bash
   gcloud compute ssh dev-builder --zone asia-northeast1-a
   sudo cat /var/log/syslog | grep startup-script
   ```

2. **手动重新执行**：
   ```bash
   sudo bash /var/run/google.startup.script
   ```

3. **调试配置脚本**：
   - 在 `builder-setup.sh` 中添加 `set -x` 查看详细执行过程
   - 注释掉有问题的部分，逐步调试

### 镜像创建失败

```bash
# 检查 builder 实例状态
gcloud compute instances describe dev-builder --zone asia-northeast1-a

# 确保实例已停止
gcloud compute instances stop dev-builder --zone asia-northeast1-a

# 重试创建镜像
bash scripts/build-image.sh create-image
```

## 💡 最佳实践

1. **版本控制**：将 `builder-setup.sh` 提交到 Git，团队共享配置

2. **模块化**：创建多个配置脚本，按需组合
   ```bash
   scripts/
   ├── builder-setup.sh           # 主脚本
   ├── builder-setup-docker.sh    # Docker 配置
   ├── builder-setup-nodejs.sh    # Node.js 配置
   └── builder-setup-python.sh    # Python 配置
   ```

3. **测试驱动**：在本地 Docker 容器中测试配置脚本
   ```bash
   docker run -it debian:12 bash
   # 复制并运行配置脚本
   ```

4. **定期更新**：定期更新配置脚本中的软件版本

5. **文档化**：在 `builder-setup.sh` 中添加注释说明自定义内容

## 🔐 安全提醒

- ✅ 不要在配置脚本中硬编码密码或密钥
- ✅ 使用环境变量或 GCP Secret Manager
- ✅ 创建镜像前清理敏感信息
- ✅ 定期更新基础镜像和依赖

## 📚 相关文档

- [build-image.sh](scripts/build-image.sh) - Builder 管理脚本
- [builder-setup.sh](scripts/builder-setup.sh) - 配置脚本模板
- [README.md](README.md) - 项目主文档

---

**最后更新**: 2024-10-18

