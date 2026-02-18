# 快速参考手册

## 📝 常用命令速查

### 初次设置

```bash
# 1. 生成 SSH 密钥
bash scripts/setup-ssh-key.sh

# 2. (Windows 用户) 同步密钥
bash scripts/sync-ssh-to-windows.sh

# 3. 初始化网络
bash scripts/setup-network.sh
```

### 创建自定义镜像

```bash
# 创建 builder 实例
bash scripts/build-image.sh create-builder

# SSH 登录并执行配置脚本（等待 30 秒让实例启动）
gcloud compute ssh dev-builder --zone=asia-northeast1-a
sudo bash ~/builder-setup.sh

# 配置完成后关机
sudo poweroff

# 创建镜像（必须等实例完全停止）
bash scripts/build-image.sh create-image

# 清理
bash scripts/build-image.sh delete-builder
```

### 日常使用

```bash
# 启动开发机
bash scripts/start-dev.sh

# 连接（Linux/macOS/WSL）
ssh gcp-dev

# 用完删除
bash scripts/destroy-dev.sh
```

### 实例管理

```bash
# 查看所有实例
gcloud compute instances list

# 停止实例
gcloud compute instances stop dev-instance --zone=asia-northeast1-a

# 启动已停止的实例
gcloud compute instances start dev-instance --zone=asia-northeast1-a

# 删除实例
gcloud compute instances delete dev-instance --zone=asia-northeast1-a
```

### 查看日志

```bash
# 查看 builder 配置进度
gcloud compute instances get-serial-port-output dev-builder \
  --zone=asia-northeast1-a

# 实时查看日志
gcloud compute instances tail-serial-port-output dev-builder \
  --zone=asia-northeast1-a
```

---

## 🔧 配置文件说明

### `.env` 必填项

```bash
GCP_PROJECT_ID=your-project-id
GCP_REGION=asia-northeast1
GCP_ZONE=asia-northeast1-a
```

### `.env` SSH 配置（推荐）

```bash
SSH_USERNAME=dev
SSH_PUBLIC_KEY_FILE=./ssh/gcp_dev.pub
```

### `.env` 自定义镜像（可选）

```bash
IMAGE_FAMILY=dev-gold
IMAGE_PROJECT=your-project-id
```

---

## 📂 重要文件路径

```
项目目录/
├── scripts/builder-setup.sh    ← 自定义安装内容
├── ssh/gcp_dev                 ← SSH 私钥
├── ssh/gcp_dev.pub             ← SSH 公钥
└── .env                        ← 环境配置
```

---

## 🐛 常见问题快速解决

### 无法连接 SSH

```bash
# 验证公钥是否注入
bash scripts/verify-ssh-key.sh

# 查看实例外网 IP
gcloud compute instances describe dev-instance \
  --zone=asia-northeast1-a \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
```

### Builder 配置失败

```bash
# 查看错误日志
gcloud compute ssh dev-builder --zone=asia-northeast1-a
sudo journalctl -u google-startup-scripts.service
```

### 磁盘未挂载

```bash
# SSH 进入实例手动挂载
sudo mkdir -p /workspace
sudo mount /dev/sdb /workspace
```

---

## 💡 快速提示

| 场景 | 命令 |
|------|------|
| 生成 SSH 密钥 | `bash scripts/setup-ssh-key.sh` |
| 同步到 Windows | `bash scripts/sync-ssh-to-windows.sh` |
| 启动开发机 | `bash scripts/start-dev.sh` |
| 删除开发机 | `bash scripts/destroy-dev.sh` |
| 创建 builder | `bash scripts/build-image.sh create-builder` |
| 创建镜像 | `bash scripts/build-image.sh create-image` |
| SSH 连接 | `ssh gcp-dev` |
| 验证 SSH | `bash scripts/verify-ssh-key.sh` |

---

## 📚 完整文档链接

- [README.md](../README.md) - 项目主文档
- [BUILDER_GUIDE.md](BUILDER_GUIDE.md) - Builder 详细指南
- [SSH_KEY_MANAGEMENT.md](SSH_KEY_MANAGEMENT.md) - SSH 密钥管理方案

---

**提示**: 将此文档收藏，随时查阅常用命令！

