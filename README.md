<div align="center">

# cloud-devbox

用 Google Cloud 一键启动/销毁的云端开发机模板。支持固定 IP、Spot 节省成本、自定义镜像、永久磁盘挂载到 `/workspace`，适配 Cursor / VSCode Remote。

</div>

---

## ✨ 功能特性

- 固定公网 IP，远程连接稳定
- Spot 抢占式实例，低成本（典型 ~$0.05/小时）
- 自定义镜像，环境一致，30s 级启动
- 永久数据盘，代码与配置保留在 `/workspace`
- 脚本化一键启动、自动定时删除，避免遗留账单
- **统一用户配置**：从镜像构建到 Cursor 登录使用同一用户（通过 .env 配置）

## TODO
1. 输出脚本运行时长
2. ~~解决默认 /workspace 没有权限的问题~~ ✅ 已解决（所有流程使用 .env 配置的统一用户）
3. ~~可以自定义添加 ssh pub key 用于虚拟机登录~~ ✅ 已支持（通过 .env 配置）
4. 如何解决每次需要删除 机器指纹的问题（机器每次都会重新创建）
5. ~~如何解决 windows cursor 读取不到 wls 下的 ssh key 的问题~~ ✅ 已解决（提供同步脚本）
6. 自定义镜像是否可以，默认安装 cursor server
7. ~~密钥管理优化【不内置在 镜像 中】~~ ✅ 已优化（通过 metadata 传递）

---

## 📦 目录结构

```
.
├── scripts/
│   ├── setup-network.sh        # 申请静态 IP、创建防火墙
│   ├── setup-ssh-key.sh        # SSH 密钥生成工具
│   ├── sync-ssh-to-windows.sh  # 同步密钥到 Windows
│   ├── start-dev.sh            # 启动 Spot 开发机并挂载数据盘
│   ├── destroy-dev.sh          # 销毁临时实例
│   ├── verify-ssh-key.sh       # 验证 SSH 公钥注入
│   ├── build-image.sh          # 构建/更新自定义镜像
│   └── builder-setup.sh        # Builder 自动化配置脚本
├── ssh/
│   ├── config.example          # SSH 配置模板
│   ├── gcp_dev                 # SSH 私钥（gitignore）
│   └── gcp_dev.pub             # SSH 公钥（gitignore）
├── docs/
│   ├── BUILDER_GUIDE.md        # Builder 自动化配置指南
│   ├── SSH_KEY_MANAGEMENT.md   # SSH 密钥管理方案
│   └── QUICK_REFERENCE.md      # 快速参考手册
├── .env.example                # 环境变量模板
└── README.md
```

---

## ✅ 前置条件

- 已开启 GCP 计费并创建项目
- 已安装并初始化 `gcloud`（登录并选择项目）
- 账号具备 `Compute Admin` 权限或等价权限

> 💡 **Windows + WSL 用户**: 如果在 Windows 中使用 Cursor/VSCode，可使用 `bash scripts/sync-ssh-to-windows.sh` 同步密钥

---

## 📥 安装依赖

### 安装 Google Cloud SDK (gcloud)

**Linux / WSL:**

```bash
# 下载并安装
curl https://sdk.cloud.google.com | bash

# 重启 shell 或执行
exec -l $SHELL

# 初始化并登录
gcloud auth login

```

**macOS:**

```bash
# 使用 Homebrew
brew install --cask google-cloud-sdk

# 初始化并登录
gcloud init
```

---

## ⚡ 快速开始

1. 克隆并配置环境变量

```bash
git clone https://github.com/yourname/cloud-devbox.git
cd cloud-devbox
cp env.example .env
# 编辑 .env，至少填写：GCP_PROJECT_ID、GCP_REGION、GCP_ZONE
```

2. （推荐）配置 SSH 密钥，方便直接登录

```bash
# 使用辅助脚本生成密钥（推荐，会自动生成到 ssh/ 目录）
bash scripts/setup-ssh-key.sh

# 或手动生成到项目目录
ssh-keygen -t ed25519 -f ./ssh/gcp_dev -C "dev"

# 然后在 .env 中添加：
# SSH_USERNAME=dev
# SSH_PUBLIC_KEY_FILE=./ssh/gcp_dev.pub
```

3. 一次性初始化网络（静态 IP 与 SSH 防火墙）

```bash
bash scripts/setup-network.sh
```

4.（可选）制作自定义镜像（更快启动，更一致环境）

```bash
# 方式 A：手动执行（推荐）
bash scripts/build-image.sh create-builder    # 创建 builder 实例
# 等待 30 秒让实例启动后，SSH 登录执行配置
gcloud compute ssh dev-builder                # SSH 登录
sudo bash ~/builder-setup.sh                  # 执行配置脚本（实时查看输出）
# 等待 5-10 分钟配置完成
gcloud compute instances stop dev-builder --zone=asia-northeast1-a
bash scripts/build-image.sh create-image      # 创建镜像

# 方式 B：手动执行（方便调试）
bash scripts/build-image.sh create-builder    # 创建 builder 实例
gcloud compute ssh dev-builder                # SSH 登录
sudo bash ~/builder-setup.sh                  # 执行配置脚本（实时查看输出）
sudo poweroff                                 # 配置完成后关机
bash scripts/build-image.sh create-image      # 创建镜像

# 方式 C：自定义配置
# 1. 编辑 scripts/builder-setup.sh 添加您需要的工具
# 2. bash scripts/build-image.sh create-builder
# 3. gcloud compute ssh dev-builder
# 4. sudo bash ~/builder-setup.sh（或分步执行脚本内容调试）
# 5. sudo poweroff
# 6. bash scripts/build-image.sh create-image

# 详见 docs/BUILDER_GUIDE.md
```

5. 启动临时开发机（Spot）

```bash
bash scripts/start-dev.sh
# 如果配置了 SSH 密钥，脚本会自动输出 SSH 配置信息
```

6. 配置并连接 Cursor / VSCode Remote SSH

```bash
# Linux/macOS: 将脚本输出的配置追加到 ~/.ssh/config
ssh gcp-dev

# Windows + WSL: 需要先同步密钥到 Windows
bash scripts/sync-ssh-to-windows.sh
# 然后在 Cursor 中使用 Remote-SSH 连接

# 或使用 gcloud（无需配置 SSH 密钥）
gcloud compute ssh <实例名> --zone=asia-northeast1-a
```

7. 用完销毁（避免账单）

```bash
bash scripts/destroy-dev.sh
```

---

## 🔧 配置项（.env）

关键变量（均已在 `.env.example` 中提供默认值或示例）：

- `GCP_PROJECT_ID`：GCP 项目 ID
- `GCP_REGION` / `GCP_ZONE`：区域与可用区
- `ADDRESS_NAME`：静态 IP 名称
- `DISK_NAME` / `DISK_SIZE_GB` / `DISK_TYPE`：永久盘配置
- **镜像配置（智能选择）**：
  - `IMAGE_FAMILY` / `IMAGE_PROJECT`：自定义镜像（可选）
  - `DEFAULT_IMAGE_FAMILY` / `DEFAULT_IMAGE_PROJECT`：默认镜像（回退）
  - 脚本会自动检测自定义镜像是否存在，不存在则使用默认镜像
- **SSH 配置（推荐配置）**：
  - `SSH_USERNAME`：SSH 登录用户名（默认为 `dev`）
    - **重要**：此用户将用于整个流程（构建镜像、安装软件、Cursor 登录）
    - 在构建镜像时会自动创建该用户并配置 sudo 权限（免密）
    - 所有软件（Docker、Node.js、Python、Git）都会为该用户安装配置
    - `/workspace` 目录自动设置为该用户所有
  - `SSH_PUBLIC_KEY_FILE`：SSH 公钥文件路径（推荐 `./ssh/gcp_dev.pub`）
  - 配置后可直接通过 SSH 密钥登录，无需密码
  - 密钥文件会自动被 `.gitignore` 排除，不会提交到 Git
- `SPOT_MACHINE_TYPE` / `MAX_RUN_DURATION` / `TERMINATION_ACTION`：Spot 实例与自动删除策略
- `MOUNT_POINT` / `MOUNT_DEVICE`：数据盘挂载点与设备名
- `NETWORK_TAGS` / `SOURCE_RANGES_SSH`：网络标签与 SSH 来源网段
- `LABEL_KEY`/`LABEL_VALUE`：用于标记并批量销毁临时实例

---

## 🧪 脚本说明

- `scripts/setup-network.sh`：创建静态 IP 与 `allow-ssh` 防火墙（幂等）
- `scripts/setup-ssh-key.sh`：**SSH 密钥生成辅助工具**
  - 交互式生成 SSH 密钥对（默认保存到 `ssh/` 目录）
  - 自动设置正确的文件权限
  - 自动输出 `.env` 配置建议
  - 提供完整的使用指引
- `scripts/sync-ssh-to-windows.sh`：**Windows 密钥同步工具**
  - 将 WSL 中的密钥复制到 Windows 用户目录
  - 适用于 Windows + Cursor/VSCode 用户
  - 自动生成 PowerShell 权限设置脚本
- `scripts/start-dev.sh`：
  - 确保永久盘存在（不存在则创建）
  - **智能镜像选择**：自动检测自定义镜像，不存在则回退到默认镜像
  - **SSH 密钥注入**：如果配置了公钥，自动添加到实例 metadata
  - 启动 Spot 实例，自动格式化并挂载数据盘到 `${MOUNT_POINT}`，设置自动删除
  - 首次使用会自动格式化新磁盘为 ext4 文件系统
  - 输出外网 IP 与 SSH 配置指引
- `scripts/destroy-dev.sh`：删除带有指定标签的运行中实例（默认 `devbox=yes`）
- `scripts/build-image.sh`：**自定义镜像构建工具**
  - `create-builder`：创建构建机并通过 metadata 传入配置脚本
  - `create-image`：从构建机磁盘创建镜像（并加入镜像族）
  - `delete-builder`：删除构建机实例
  - 脚本通过 metadata 传入并自动保存到 `~/builder-setup.sh`（方便调试）
- `scripts/builder-setup.sh`：**Builder 配置脚本**
  - 安装 mise（Node.js/Python 版本管理器）
  - 安装 Docker, Git, Vim (amix/vimrc)
  - 配置 Git 用户信息和 SSH 密钥
  - 可自定义添加任意依赖和配置
  - 详见 [docs/BUILDER_GUIDE.md](docs/BUILDER_GUIDE.md)

---

## 🔐 安全建议

- 将 `SOURCE_RANGES_SSH` 设置为你当前公网 IP 段，避免 0.0.0.0/0 暴露
- 推荐使用 IAP 隧道或 VPN 进一步收敛暴露面
- 定期 rotate SSH key，限制 `Network Tags` 的使用范围

---

## ❓ 常见问题

### 环境依赖问题

- **`gcloud: command not found`**：
  - 需要先安装 Google Cloud SDK，请参考上面的"📥 安装依赖"章节
  - 安装后记得执行 `gcloud init` 和 `gcloud auth login`

### 实例启动问题

- **镜像选择机制**：
  - ✅ 脚本支持智能镜像选择，无需手动修改配置
  - 如果配置了自定义镜像，脚本会先检测是否存在
  - 如果自定义镜像不存在或未配置，自动使用默认镜像（Debian 12）
  - 可以通过 `DEFAULT_IMAGE_FAMILY` 和 `DEFAULT_IMAGE_PROJECT` 自定义默认镜像

- **启动失败且提示镜像不存在**：
  - 这个问题现在会自动解决，脚本会回退到默认镜像
  - 如果仍然失败，检查 `DEFAULT_IMAGE_FAMILY` 和 `DEFAULT_IMAGE_PROJECT` 配置

- **metadata 参数错误**：
  - 已修复：现在使用 `--metadata-from-file` 代替直接传递启动脚本，避免特殊字符解析问题

### 磁盘问题

- **磁盘未挂载**：
  - 检查 `.env` 中 `MOUNT_DEVICE` 是否与实际一致（GCE 通常为 `/dev/sdb`）
  - 新磁盘会自动格式化为 ext4，无需手动操作

### 网络问题

- **防火墙未生效**：
  - 确认实例 `--tags` 与规则 `--target-tags` 一致
  - 检查是否先运行了 `setup-network.sh`

### SSH 连接问题

- **配置 SSH 密钥登录**：
  - 使用 `bash scripts/setup-ssh-key.sh` 快速生成密钥（保存到 `ssh/` 目录）
  - 在 `.env` 中配置 `SSH_USERNAME=dev` 和 `SSH_PUBLIC_KEY_FILE=./ssh/gcp_dev.pub`
  - 启动实例时会自动注入公钥到虚拟机
  - 密钥文件不会被 Git 追踪

- **SSH 连接被拒绝**：
  - 确认防火墙规则已创建：`bash scripts/setup-network.sh`
  - 检查 SSH 用户名是否正确
  - 使用 `gcloud compute ssh` 作为备选方案（自动管理密钥）

- **使用 gcloud SSH（无需配置密钥）**：
  ```bash
  gcloud compute ssh <实例名> --zone=asia-northeast1-a
  ```

---

## 许可证

MIT
