# init-devbox 使用指南

Ubuntu 全栈开发环境一键初始化工具，专为 vibe coding 设计。

## 快速开始

### 远程一键安装（推荐）

```bash
# 海外用户
curl -fsSL https://raw.githubusercontent.com/William-Sang/cloud-devbox/main/bootstrap/install.sh | bash

# 中国用户（国内镜像加速）
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/William-Sang/cloud-devbox/main/bootstrap/install.sh | bash -s -- --region cn

# 全量安装（非交互）
curl -fsSL https://raw.githubusercontent.com/William-Sang/cloud-devbox/main/bootstrap/install.sh | bash -s -- --region overseas --all --yes
```

### 本地安装

```bash
git clone https://github.com/William-Sang/cloud-devbox.git
cd cloud-devbox

# 交互式安装（会询问区域和模块选择）
bash bootstrap/init-devbox.sh apply

# 全量安装
bash bootstrap/init-devbox.sh apply --all --yes

# 仅安装基础 + Node + Python
bash bootstrap/init-devbox.sh apply --module base,node,python --yes
```

## 区域选择

首次运行时会询问网络区域，选择后自动缓存，后续运行不再询问。

| | 中国大陆 (`cn`) | 海外 (`overseas`) |
|---|---|---|
| **apt** | mirrors.aliyun.com | archive.ubuntu.com |
| **npm** | registry.npmmirror.com | registry.npmjs.org |
| **PyPI** | mirrors.aliyun.com/pypi | pypi.org |
| **Docker CE** | mirrors.aliyun.com/docker-ce | download.docker.com |
| **Docker Hub** | registry.cn-hangzhou.aliyuncs.com | docker.io |
| **GitHub 下载** | ghfast.top 代理 | 直连 |

### 切换区域

```bash
# 命令行指定
bash bootstrap/init-devbox.sh apply --region cn

# 或手动修改缓存
echo "overseas" > ~/.config/init-devbox/region
```

## 命令参考

### apply — 安装开发环境

```bash
init-devbox apply [选项]

选项:
  --region cn|overseas    网络区域
  --all                   安装所有模块
  --module m1,m2,...      指定模块（逗号分隔）
  --yes / -y              跳过确认提示
  --non-interactive       非交互模式（CI 用）
  --config <file>         自定义配置文件
```

### doctor — 系统预检

```bash
init-devbox doctor
```

检查项目：OS 版本、sudo 权限、磁盘空间、网络连通性、已安装工具状态。不会安装任何东西。

### verify — 安装验证

```bash
# 终端彩色报告
init-devbox verify

# 导出 JSON 报告
init-devbox verify --report-json /tmp/verify-report.json
```

检查：工具版本、策略合规（pip 污染、Corepack、fnm PATH、镜像源配置）。

## 模块说明

| 模块 | 默认 | 安装内容 |
|------|:---:|---------|
| **mirror** | ON | 根据区域配置 apt/npm/pypi 镜像源 |
| **base** | ON | git, curl, wget, vim, tmux, htop, build-essential, ripgrep, jq, unzip |
| **docker** | OFF | Docker Engine, docker-compose, Docker Buildx |
| **node** | ON | fnm, Node.js LTS, pnpm, bun |
| **python** | ON | uv, Python 3.12, Python 3.13 |
| **ai-tools** | OFF | Claude Code, OpenCode, Codex CLI, Qoder CLI, Gemini CLI |
| **shell-config** | OFF | bash 别名, Git-aware PS1, git 全局配置, 工具补全 |

**依赖关系**: `ai-tools` 依赖 `node`（npm-based 工具需要 Node.js），未安装时会自动添加。

### 单独运行模块

```bash
bash bootstrap/modules/node.sh
bash bootstrap/modules/python.sh
bash bootstrap/modules/ai-tools.sh
```

## 自定义配置

复制默认配置并修改：

```bash
cp bootstrap/config.default.toml bootstrap/config.toml
vim bootstrap/config.toml
```

### 配置项说明

```toml
[region]
value = ""              # "cn" | "overseas" | ""（交互询问）

[python]
manager = "uv"          # Python 版本管理器
versions = ["3.12", "3.13"]  # 安装的 Python 版本
default = "3.12"        # 默认版本

[node]
manager = "fnm"         # Node 版本管理器
lts = "22"              # LTS 版本号

[node.package_managers]
pnpm = true             # 是否安装 pnpm
bun = true              # 是否安装 bun

[typescript]
global = false          # 是否全局安装 TypeScript（建议 false）

[docker]
mode = "group"          # "group"（docker 组）或 "rootless"

[mirrors]
# 留空 = 根据 region 自动填充
# 手动填写则覆盖 region 预设
apt = ""
npm = ""
pypi = ""
docker_ce = ""
docker_hub = ""
github_proxy = ""
fallback_to_official = true  # 镜像不可达时回退官方源
```

## 安装后的日常使用

### fnm — Node.js 版本管理

```bash
fnm list                    # 查看已安装版本
fnm install 22              # 安装 Node 22
fnm install --lts           # 安装最新 LTS
fnm use 22                  # 切换当前 shell 的 Node 版本
fnm default 22              # 设置默认版本

# 项目自动切换（目录下有 .node-version 或 .nvmrc 时自动生效）
echo "22" > .node-version
```

### uv — Python 版本 & 包管理

```bash
# 创建新项目
uv init myproject && cd myproject

# 管理依赖
uv add requests fastapi     # 添加依赖
uv remove requests          # 移除依赖
uv sync                     # 同步依赖
uv lock                     # 锁定依赖版本

# 运行
uv run python app.py        # 在项目虚拟环境中运行
uv run pytest               # 运行测试

# 安装全局 CLI 工具
uv tool install ruff        # 代码检查
uv tool install black       # 代码格式化
uv tool install httpie      # HTTP 客户端

# Python 版本管理
uv python list              # 查看可用版本
uv python install 3.13      # 安装新版本
```

### pnpm — Node.js 包管理

```bash
pnpm init                   # 初始化项目
pnpm add express            # 添加依赖
pnpm add -D typescript      # 添加开发依赖
pnpm install                # 安装所有依赖
pnpm run dev                # 运行脚本
pnpm dlx create-next-app    # 一次性运行包
```

### bun — 全能 JS 运行时

```bash
bun init                    # 初始化项目
bun add express             # 添加依赖
bun run index.ts            # 直接运行 TypeScript
bun test                    # 运行测试
bunx create-next-app        # 一次性运行包
```

### AI 编码工具

| 工具 | 启动命令 | 认证方式 |
|------|---------|---------|
| Claude Code | `claude` | Anthropic 账号 (claude.ai) |
| OpenCode | `opencode` | ANTHROPIC/OPENAI/GEMINI_API_KEY |
| Codex CLI | `codex` | OpenAI API key 或 ChatGPT 订阅 |
| Qoder CLI | `qodercli` | Qoder 账号 (qoder.com) |
| Gemini CLI | `gemini` | Google 账号（免费额度）或 GEMINI_API_KEY |

## 故障排查

### 常见问题

**Q: 安装后命令找不到？**
```bash
source ~/.bashrc
# 或重新打开终端
```

**Q: 网络超时？**
```bash
# 切换到中国镜像
bash bootstrap/init-devbox.sh apply --region cn
```

**Q: 权限不足？**
```bash
# 确保有 sudo 权限
sudo bash bootstrap/init-devbox.sh apply --all
```

**Q: 部分工具安装失败？**
```bash
# 重新运行即可（幂等设计，已安装的会跳过）
bash bootstrap/init-devbox.sh apply --module ai-tools --yes
```

**Q: 如何查看安装状态？**
```bash
bash bootstrap/init-devbox.sh doctor    # 系统预检
bash bootstrap/init-devbox.sh verify    # 安装验证
```

**Q: 如何重置区域选择？**
```bash
rm ~/.config/init-devbox/region
# 下次运行时会重新询问
```

### verify 常见失败项

| 检查项 | 修复方法 |
|--------|---------|
| fnm PATH 不正确 | `source ~/.bashrc` 或重新打开终端 |
| 全局 pip 包污染 | `pip uninstall <pkg>` 后改用 `uv tool install` |
| npm 镜像未配置 | `npm config set registry https://registry.npmmirror.com` |
| Docker 组权限 | 重新登录 shell：`newgrp docker` 或重新登录 |
