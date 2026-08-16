[English](README.md) | **Русский** | [Español](README.es.md) | [Deutsch](README.de.md) | [中文](README.zh.md)

🌐 **Сайт:** [execai.ru](https://execai.ru) · 💬 Веб-чат: [chat.execai.ru](https://chat.execai.ru) · 🤖 Агент: [execai/execai-agent](https://github.com/execai/execai-agent) · 🔌 Расширение: [execai/execai-vscode](https://github.com/execai/execai-vscode)

---

# ExecAI Studio

Редактор кода со встроенным [агентом ExecAI](https://github.com/execai/execai-agent): поставил одну вещь — и работаешь. Агент, панель и разумные настройки уже внутри. Собран на [VSCodium](https://github.com/VSCodium/vscodium) (свободная сборка VS Code), поэтому все расширения из Open VSX и все привычки из VS Code переносятся как есть.

Это не клон Cursor — это среда, в которой живёт агент:

- **Агент `execai` в поставке.** Ничего не качается при первом старте; агент сам ставится в `~/.local/bin`, и команда `execai` работает в любом терминале. Если у тебя уже стоит более новый агент — редактор использует его.
- **Чат ExecAI предустановлен и живёт в правой панели** — `Ctrl+L` фокусирует его.
- **10 источников моделей** — бэкенд ExecAI, твои подписки Z.ai / Kimi / Anthropic / OpenAI или полностью локально через Ollama. Переключение на лету, одна общая история.
- **Уровни безопасности и разрешения на действия** — агент спрашивает, прежде чем трогать то, что трогать не следует.
- **Open VSX** как каталог расширений. Без сервисов Microsoft и без телеметрии сверх умолчаний VSCodium.

## Установка (Linux x64)

Скачай тарболл из [Releases](https://github.com/execai/execai-studio/releases/latest) или с зеркала ([storage.yandexcloud.net/…/latest.json](https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable/latest.json) указывает на текущую сборку), затем:

```sh
tar -xzf ExecAI-Studio-linux-x64-*.tar.gz
./ExecAI-Studio-linux-x64/bin/execai-studio
```

Обновления: редактор сам проверяет зеркало и GitHub Releases и предлагает скачать новую версию. Сборки под Windows и macOS — в планах.

## Сборка из исходников

Сборка — механический репак релиза VSCodium: без патчей ядра, компилировать нечего:

```sh
./build/build.sh --vsix путь/к/execai-<версия>.vsix --agent путь/к/execai
```

Скрипт скачивает закреплённый тарболл VSCodium, накладывает брендинг ExecAI, вкладывает [расширение](https://github.com/execai/execai-vscode) и бинарь агента, проверяет, что версия агента удовлетворяет минимуму расширения, и пакует результат в `dist/`.

## Лицензия

Сборочные скрипты и брендинг в этом репозитории — под [Business Source License 1.1](LICENSE). Исходники VS Code — MIT © Microsoft; сборочный инструментарий VSCodium — MIT © участники VSCodium. Проект не аффилирован с Microsoft или VSCodium.
