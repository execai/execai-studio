[English](README.md) | [Русский](README.ru.md) | [Español](README.es.md) | [Deutsch](README.de.md) | **中文**

🌐 **官网：**[execai.ru](https://execai.ru) · 💬 网页聊天：[chat.execai.ru](https://chat.execai.ru) · 🤖 智能体：[execai/execai-agent](https://github.com/execai/execai-agent) · 🔌 扩展：[execai/execai-vscode](https://github.com/execai/execai-vscode)

---

# ExecAI Studio

内置 [ExecAI 智能体](https://github.com/execai/execai-agent)的代码编辑器：只装一样东西就能开工 — 智能体、聊天面板和合理的默认设置都已内置。基于 [VSCodium](https://github.com/VSCodium/vscodium)（自由许可的 VS Code 构建版），Open VSX 的所有扩展和你的 VS Code 使用习惯都能无缝沿用。

它不是 Cursor 的克隆 — 而是智能体栖身的环境：

- **`execai` 智能体随包附带。** 首次启动无需任何下载；在 Linux 和 macOS 上，智能体还会自动安装到 `~/.local/bin`，让 `execai` 命令在任意终端可用。如果你已装有更新版本的智能体，编辑器会直接使用你的。
- **ExecAI 聊天预装在右侧边栏** — `Ctrl+L` 即可聚焦。聊天以标签页形式排在面板顶部：点击切换、「×」关闭、拖动排序。回答中的链接和文件路径可点击，每个代码块都有复制按钮。
- **首次启动的 Getting started** — 空对话会显示五个带勾选标记的步骤（登录、接入模型、开启同步、把文件夹绑定到项目、用手机呼叫智能体），每一步都有完成它的按钮。面板标题栏中的 **My machine** 显示智能体版本、套餐、哪些模型来源有响应、同步会带走哪些内容，以及供手机扫描的二维码。
- **12 个模型来源** — ExecAI 后端、你的 Z.ai / Kimi Code / Moonshot / Anthropic / OpenAI / OpenRouter 密钥、你自己的 OpenAI 或 Anthropic 兼容端点，或通过 Ollama 完全本地运行。随时切换，共享同一份历史。
- **安全级别与逐操作授权** — 智能体在触碰不该碰的东西之前会先询问。
- **Open VSX** 作为扩展市场。没有 Microsoft 服务，除 VSCodium 默认设置外没有额外遥测。

## 安装

一条命令，无需管理员权限：

```sh
# Linux / macOS — Yandex 镜像
curl -fsSL https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable/install.sh | bash

# Linux / macOS — GitHub
curl -fsSL https://raw.githubusercontent.com/execai/execai-studio/main/install.sh | bash
```

```powershell
# Windows (PowerShell) — Yandex 镜像
irm https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable/install.ps1 | iex

# Windows (PowerShell) — GitHub
irm https://raw.githubusercontent.com/execai/execai-studio/main/install.ps1 | iex
```

脚本会自动选择适合你系统的构建（Linux x64、Windows x64、macOS Intel/Apple Silicon），从镜像或 GitHub 下载，校验哈希并创建菜单项。手动下载：[Releases](https://github.com/execai/execai-studio/releases/latest)。Windows 和 macOS 构建暂未签名 — 安装脚本已妥善处理（macOS 上做 ad-hoc 签名；Windows 上文件不带 mark-of-the-web，因此不会被 SmartScreen 拦截）。

更新：编辑器会自行检查镜像和 GitHub Releases，有新版本时提示 **Update and restart**——新构建会被下载、校验哈希，并替换旧版本。

## 从源码构建

构建就是对 VSCodium 发行版的机械式重新打包 — 不打核心补丁，无需编译：

```sh
./build/build.sh --vsix 路径/到/execai-<版本>.vsix --agent 路径/到/execai
```

脚本会下载固定版本的 VSCodium 压缩包，套用 ExecAI 品牌，捆绑[扩展](https://github.com/execai/execai-vscode)与智能体二进制文件，校验智能体版本满足扩展的最低要求，并将结果打包到 `dist/`。

## 许可证

本仓库中的构建脚本与品牌资源采用 [Business Source License 1.1](LICENSE)。VS Code 源码为 MIT © Microsoft；VSCodium 构建工具为 MIT © VSCodium 贡献者。本项目与 Microsoft 或 VSCodium 均无关联。
