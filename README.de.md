[English](README.md) | [Русский](README.ru.md) | [Español](README.es.md) | **Deutsch** | [中文](README.zh.md)

🌐 **Website:** [execai.ru](https://execai.ru) · 💬 Web-Chat: [chat.execai.ru](https://chat.execai.ru) · 🤖 Agent: [execai/execai-agent](https://github.com/execai/execai-agent) · 🔌 Erweiterung: [execai/execai-vscode](https://github.com/execai/execai-vscode)

---

# ExecAI Studio

Ein Code-Editor mit eingebautem [ExecAI-Agenten](https://github.com/execai/execai-agent): eine Sache installieren und loslegen — Agent, Panel und sinnvolle Voreinstellungen sind schon drin. Gebaut auf [VSCodium](https://github.com/VSCodium/vscodium) (dem frei lizenzierten VS-Code-Build), sodass jede Erweiterung aus Open VSX und alle VS-Code-Gewohnheiten erhalten bleiben.

Kein Cursor-Klon — eine Umgebung, in der der Agent lebt:

- **Der `execai`-Agent ist im Paket.** Beim ersten Start wird nichts heruntergeladen; der Agent installiert sich zusätzlich nach `~/.local/bin`, sodass der Befehl `execai` in jedem Terminal funktioniert. Ist bereits ein neuerer Agent vorhanden, nutzt der Editor deinen.
- **Der ExecAI-Chat ist vorinstalliert und lebt in der rechten Seitenleiste** — `Ctrl+L` fokussiert ihn.
- **10 Modellquellen** — das ExecAI-Backend, deine Abos von Z.ai / Kimi / Anthropic / OpenAI oder komplett lokal über Ollama. Wechsel im laufenden Betrieb, eine gemeinsame Historie.
- **Sicherheitsstufen und Berechtigungen pro Aktion** — der Agent fragt, bevor er anfasst, was er nicht anfassen sollte.
- **Open VSX** als Erweiterungskatalog. Keine Microsoft-Dienste, keine Telemetrie über die VSCodium-Defaults hinaus.

## Installation (Linux x64)

Lade den Tarball von [Releases](https://github.com/execai/execai-studio/releases/latest) oder vom Spiegel ([storage.yandexcloud.net/…/latest.json](https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable/latest.json) zeigt auf den aktuellen Build), dann:

```sh
tar -xzf ExecAI-Studio-linux-x64-*.tar.gz
./ExecAI-Studio-linux-x64/bin/execai-studio
```

Updates: Der Editor prüft Spiegel und GitHub Releases selbst und bietet den Download an, sobald eine neue Version erschienen ist. Builds für Windows und macOS stehen auf der Roadmap.

## Aus dem Quellcode bauen

Der Build ist ein mechanisches Neupacken eines VSCodium-Releases — keine Core-Patches, nichts zu kompilieren:

```sh
./build/build.sh --vsix pfad/zu/execai-<version>.vsix --agent pfad/zu/execai
```

Das Skript lädt den festgelegten VSCodium-Tarball, wendet das ExecAI-Branding an, legt die [Erweiterung](https://github.com/execai/execai-vscode) und die Agent-Binärdatei bei, prüft, dass die Agent-Version das Minimum der Erweiterung erfüllt, und packt das Ergebnis nach `dist/`.

## Lizenz

Die Build-Skripte und das Branding in diesem Repository stehen unter der [Business Source License 1.1](LICENSE). Der VS-Code-Quellcode ist MIT © Microsoft; das VSCodium-Build-Tooling ist MIT © VSCodium-Mitwirkende. Dieses Projekt ist weder mit Microsoft noch mit VSCodium affiliiert.
