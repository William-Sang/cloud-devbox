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
- **持久系统盘**：apt 安装的软件在实例重建后保留（默认开启）
- 脚本化一键启动、自动定时删除，避免遗留账单
- **统一用户配置**：从镜像构建到 Cursor 登录使用同一用户（通过 .env 配置）

## TODO
1. ~~输出脚本运行时长~~ ✅ 已完成（所有脚本均已添加运行时长显示）
2. ~~解决默认 /workspace 没有权限的问题~~ ✅ 已解决（所有流程使用 .env 配置的统一用户）
3. ~~可以自定义添加 ssh pub key 用于虚拟机登录~~ ✅ 已支持（通过 .env 配置）
4. ~~如何解决每次需要删除 机器指纹的问题（机器每次都会重新创建）~~ ✅ 已解决（在 SSH config 中启用 StrictHostKeyChecking no 和 UserKnownHostsFile /dev/null）
5. ~~如何解决 windows cursor 读取不到 wls 下的 ssh key 的问题~~ ✅ 已解决（提供同步脚本）
6. ~~密钥管理优化【不内置在 镜像 中】~~ ✅ 已优化（通过 metadata 传递）

---

## 📦 目录结构

```
.
├── scripts/
│   ├── build-image.sh          # 构建/更新自定义镜像
│   ├── builder-setup.sh        # Builder 自动化配置脚本
│   ├── destroy-dev.sh          # 销毁临时实例
│   ├── setup-network.sh        # 申请静态 IP、创建防火墙
│   ├── setup-ssh-key.sh        # SSH 密钥生成工具
│   ├── start-dev.sh            # 启动 Spot 开发机并挂载数据盘
│   ├── sync-ssh-to-windows.sh  # 同步密钥到 Windows
│   └── verify-ssh-key.sh       # 验证 SSH 公钥注入
├── ssh/
│   ├── config.example          # SSH 配置模板
│   ├── gcp_dev                 # SSH 私钥（gitignore）
│   └── gcp_dev.pub             # SSH 公钥（gitignore）
├── docs/
│   ├── BUILDER_GUIDE.md        # Builder 自动化配置指南
│   ├── BUILDER_WORKFLOW.md     # Builder 工作流程详解
│   ├── QUICK_REFERENCE.md      # 快速参考手册
│   └── SSH_KEY_MANAGEMENT.md   # SSH 密钥管理方案
├── .state/                     # 运行时状态文件（自动生成，gitignore）
│   ├── last_instance_name      # 最后创建的实例名称
│   └── startup-script.sh       # 临时启动脚本
├── bootstrap/                  # init-devbox: 独立开发环境安装器
│   ├── init-devbox.sh          # CLI 入口 (apply/doctor/verify)
│   ├── install.sh              # curl|bash 远程安装入口
│   ├── config.default.toml     # 默认配置
│   ├── USAGE.md                # 使用文档
│   ├── lib/                    # 基础库 (common, config, region, proxy)
│   └── modules/                # 可插拔模块 (base, docker, node, python, ai-tools 等)
├── env.example                 # 环境变量模板
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
- `DISK_NAME` / `DISK_SIZE_GB` / `DISK_TYPE`：数据盘配置（挂载到 `/workspace`）
- **持久系统盘配置（默认开启）**：
  - `PERSIST_BOOT_DISK`：是否启用持久系统盘（默认 `true`）
  - `BOOT_DISK_NAME`：系统盘名称（默认 `dev-boot`）
  - `BOOT_DISK_SIZE_GB`：系统盘大小（默认 `20`）
  - `BOOT_DISK_TYPE`：系统盘类型（默认 `pd-balanced`）
  - 开启后，`apt install` 安装的软件在实例重建后仍然保留
  - 首次启动时从镜像创建系统盘，之后复用同一块盘
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
  - 默认只删除实例，保留持久系统盘和数据盘
  - 使用 `--purge-boot` 参数可同时删除持久系统盘
  - 使用 `--help` 查看完整用法
- `scripts/build-image.sh`：**自定义镜像构建工具**
  - `create-builder`：创建构建机并通过 metadata 传入配置脚本
  - `create-image`：从构建机磁盘创建镜像（并加入镜像族）
  - `delete-builder`：删除构建机实例
  - 脚本通过 metadata 传入并自动保存到 `~/builder-setup.sh`（方便调试）
- `scripts/builder-setup.sh`：**Builder 配置脚本**
  - 委托 `bootstrap/init-devbox.sh` 安装全部开发工具
  - 安装 fnm (Node.js LTS) + uv (Python 3.12/3.13) + Docker + Git + Vim (amix/vimrc)
  - 配置 SSH 密钥、创建 /workspace 目录
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
  - 如果自定义镜像不存在或未配置，自动使用默认镜像（Ubuntu 24.04）
  - 可以通过 `DEFAULT_IMAGE_FAMILY` 和 `DEFAULT_IMAGE_PROJECT` 自定义默认镜像

- **启动失败且提示镜像不存在**：
  - 这个问题现在会自动解决，脚本会回退到默认镜像
  - 如果仍然失败，检查 `DEFAULT_IMAGE_FAMILY` 和 `DEFAULT_IMAGE_PROJECT` 配置

- **metadata 参数错误**：
  - 已修复：现在使用 `--metadata-from-file` 代替直接传递启动脚本，避免特殊字符解析问题

### 磁盘问题

- **磁盘未挂载**：
  - 检查 `.env` 中 `MOUNT_DEVICE` 是否正确（默认使用 `/dev/disk/by-id/google-<DISK_NAME>` 稳定路径）
  - 新磁盘会自动格式化为 ext4，无需手动操作

### 持久系统盘

- **工作原理**：
  - 默认开启（`PERSIST_BOOT_DISK=true`）
  - 首次启动时，从镜像创建一块名为 `dev-boot` 的持久磁盘作为系统盘
  - 之后每次启动都复用这块系统盘，而不是从镜像重新创建
  - 你在系统里 `apt install` 安装的软件、修改的配置都会保留

- **费用影响**：
  - 持久系统盘会持续产生存储费用（约 $0.10/GB/月 for pd-balanced）
  - 默认 20GB 系统盘约 $2/月
  - 如果不需要，可以设置 `PERSIST_BOOT_DISK=false` 关闭

- **重置系统盘**：
  - 如果系统盘出问题或想重新从镜像创建：
    ```bash
    # 删除实例和系统盘
    bash scripts/destroy-dev.sh --purge-boot
    # 重新启动（会从镜像创建新系统盘）
    bash scripts/start-dev.sh
    ```

- **并发限制**：
  - 同一块系统盘不能同时挂载到多台 VM
  - 如果需要并发多台开发机，请为每台配置不同的 `BOOT_DISK_NAME`

- **Spot 抢占风险**：
  - Spot 实例可能被随时抢占，抢占时有极小概率数据未完全落盘
  - 关键数据仍建议放在 `/workspace` 数据盘

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

- **机器指纹问题（每次创建新实例需要删除 known_hosts）**：
  - ✅ 已解决：在 SSH config 中启用 `StrictHostKeyChecking no` 和 `UserKnownHostsFile /dev/null`
  - 由于每次创建的实例主机密钥会变化，这些选项可避免手动删除 `~/.ssh/known_hosts`
  - `start-dev.sh` 输出的配置建议已包含这些选项
  - 详见 `ssh/config.example` 中的配置模板

- **使用 gcloud SSH（无需配置密钥）**：
  ```bash
  gcloud compute ssh <实例名> --zone=asia-northeast1-a
  ```

---

## 许可证

MIT
