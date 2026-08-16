[English](README.md) | [Русский](README.ru.md) | **Español** | [Deutsch](README.de.md) | [中文](README.zh.md)

🌐 **Sitio web:** [execai.ru](https://execai.ru) · 💬 Chat web: [chat.execai.ru](https://chat.execai.ru) · 🤖 Agente: [execai/execai-agent](https://github.com/execai/execai-agent) · 🔌 Extensión: [execai/execai-vscode](https://github.com/execai/execai-vscode)

---

# ExecAI Studio

Un editor de código con el [agente ExecAI](https://github.com/execai/execai-agent) integrado: instalas una sola cosa y te pones a trabajar — el agente, el panel y unos valores predeterminados sensatos ya vienen dentro. Construido sobre [VSCodium](https://github.com/VSCodium/vscodium) (la compilación libre de VS Code), así que todas las extensiones de Open VSX y toda tu experiencia con VS Code se conservan.

No es un clon de Cursor — es el entorno donde vive el agente:

- **El agente `execai` viene incluido.** Nada que descargar en el primer arranque; el agente además se instala en `~/.local/bin`, y el comando `execai` funciona en cualquier terminal. Si ya tienes un agente más nuevo, el editor usa el tuyo.
- **El chat de ExecAI viene preinstalado y vive en la barra lateral derecha** — `Ctrl+L` lo enfoca.
- **10 fuentes de modelos** — el backend de ExecAI, tus suscripciones de Z.ai / Kimi / Anthropic / OpenAI, o totalmente local con Ollama. Cambia sobre la marcha, con un historial compartido.
- **Niveles de seguridad y permisos por acción** — el agente pregunta antes de tocar lo que no debe.
- **Open VSX** como galería de extensiones. Sin servicios de Microsoft ni telemetría más allá de los valores de VSCodium.

## Instalación

Un solo comando, sin derechos de administrador:

```sh
# Linux / macOS
curl -fsSL https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable/install.sh | bash
```

```powershell
# Windows (PowerShell)
irm https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable/install.ps1 | iex
```

El script elige la compilación para tu sistema (Linux x64, Windows x64, macOS Intel/Apple Silicon), la descarga del espejo o de GitHub, verifica la suma de comprobación y crea la entrada en el menú. Descarga manual: [Releases](https://github.com/execai/execai-studio/releases/latest). Las compilaciones de Windows y macOS aún no están firmadas — los scripts de instalación lo resuelven (firma ad hoc en macOS; en Windows nada llega con el mark-of-the-web, así que SmartScreen no se interpone).

Actualizaciones: el editor consulta el espejo y GitHub Releases por sí mismo y ofrece la descarga cuando hay una versión nueva.

## Compilar desde el código fuente

La compilación es un reempaquetado mecánico de un release de VSCodium — sin parches del núcleo, nada que compilar:

```sh
./build/build.sh --vsix ruta/a/execai-<versión>.vsix --agent ruta/a/execai
```

El script descarga el tarball fijado de VSCodium, aplica la marca ExecAI, incluye la [extensión](https://github.com/execai/execai-vscode) y el binario del agente, verifica que la versión del agente cumpla el mínimo de la extensión y empaqueta el resultado en `dist/`.

## Licencia

Los scripts de compilación y la marca de este repositorio están bajo la [Business Source License 1.1](LICENSE). El código fuente de VS Code es MIT © Microsoft; las herramientas de compilación de VSCodium son MIT © colaboradores de VSCodium. Este proyecto no está afiliado a Microsoft ni a VSCodium.
