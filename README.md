**English** | [Русский](README.ru.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [中文](README.zh.md)

🌐 **Website:** [execai.ru](https://execai.ru) · 💬 Web chat: [chat.execai.ru](https://chat.execai.ru) · 🤖 Agent: [execai/execai-agent](https://github.com/execai/execai-agent) · 🔌 Extension: [execai/execai-vscode](https://github.com/execai/execai-vscode)

---

# ExecAI Studio

A code editor with the [ExecAI agent](https://github.com/execai/execai-agent) built in: install one thing and start working — the agent, the panel and sane defaults are already inside. Built on [VSCodium](https://github.com/VSCodium/vscodium) (the freely-licensed VS Code build), so every extension from Open VSX and every VS Code skill you have carries over.

Not a Cursor clone — an environment the agent lives in:

- **The `execai` agent ships inside.** No downloads on first start; the agent also installs itself into `~/.local/bin` so the `execai` command works in any terminal. If you already have a newer agent, the editor uses yours.
- **The ExecAI chat is pre-installed and lives in the right side bar** — `Ctrl+L` focuses it.
- **10 model sources** — ExecAI backend, your Z.ai / Kimi / Anthropic / OpenAI subscriptions, or fully local via Ollama. Switch on the fly, one shared history.
- **Security levels and per-action permissions** — the agent asks before it touches things it shouldn't.
- **Open VSX** as the extension gallery. No Microsoft services, no telemetry beyond VSCodium defaults.

## Install (Linux x64)

Download the tarball from [Releases](https://github.com/execai/execai-studio/releases/latest) or the mirror ([storage.yandexcloud.net/…/latest.json](https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable/latest.json) points at the current build), then:

```sh
tar -xzf ExecAI-Studio-linux-x64-*.tar.gz
./ExecAI-Studio-linux-x64/bin/execai-studio
```

Updates: the editor checks the mirror and GitHub Releases itself and offers a download when a new version is out. Windows and macOS builds are on the roadmap.

## Build from source

The build is a mechanical repack of a VSCodium release — no core patches, nothing to compile:

```sh
./build/build.sh --vsix path/to/execai-<version>.vsix --agent path/to/execai
```

It fetches the pinned VSCodium tarball, applies ExecAI branding, bundles the [extension](https://github.com/execai/execai-vscode) and the agent binary, verifies that the agent version satisfies the extension's minimum, and packs the result into `dist/`.

## License

The build scripts and branding in this repository are under the [Business Source License 1.1](LICENSE). VS Code sources are MIT © Microsoft; VSCodium build tooling is MIT © VSCodium contributors. This project is not affiliated with Microsoft or VSCodium.
