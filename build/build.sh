#!/usr/bin/env bash
# Builds ExecAI Studio for Linux by repacking a VSCodium release.
#
# Why repack instead of compiling. The whole point of Studio (docs/plan.md) is a
# mechanical build with no core patches. Everything we change lives in files a
# release tarball already exposes: product.json, icons, bundled extensions and
# the agent binary. Repacking takes seconds, survives upstream updates without a
# human, and needs no build farm until Ф6 (Windows/macOS, where signing forces
# a real pipeline anyway).
#
# Inputs (flags or env):
#   --vsix PATH     extension package to bundle        (env VSIX)
#   --agent PATH    execai binary to bundle            (env EXECAI_BIN)
#   --codium VER    VSCodium release, e.g. 1.126.04524 (env VSCODIUM_VERSION)
#   --version VER   Studio version stamp               (env STUDIO_VERSION)
#
# Output: dist/ExecAI-Studio-linux-x64-<version>.tar.gz plus the unpacked tree
# in out/ for local runs.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VSCODIUM_VERSION="${VSCODIUM_VERSION:-1.126.04524}"
STUDIO_VERSION="${STUDIO_VERSION:-0.1.0}"
VSIX="${VSIX:-}"
EXECAI_BIN="${EXECAI_BIN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vsix)    VSIX="$2"; shift 2 ;;
    --agent)   EXECAI_BIN="$2"; shift 2 ;;
    --codium)  VSCODIUM_VERSION="$2"; shift 2 ;;
    --version) STUDIO_VERSION="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$VSIX" ]]       || { echo "extension package not found: --vsix PATH is required" >&2; exit 2; }
[[ -x "$EXECAI_BIN" ]] || { echo "agent binary not found or not executable: --agent PATH is required" >&2; exit 2; }
for tool in jq unzip curl tar; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done

CACHE="$ROOT/build/cache"
OUT="$ROOT/out/ExecAI-Studio-linux-x64"
DIST="$ROOT/dist"
mkdir -p "$CACHE" "$DIST"

# --- 1. Fetch the VSCodium release (cached) ---------------------------------
TARBALL="VSCodium-linux-x64-${VSCODIUM_VERSION}.tar.gz"
if [[ ! -f "$CACHE/$TARBALL" ]]; then
  echo "==> downloading $TARBALL"
  curl -fL --retry 3 -o "$CACHE/$TARBALL.part" \
    "https://github.com/VSCodium/vscodium/releases/download/${VSCODIUM_VERSION}/${TARBALL}"
  mv "$CACHE/$TARBALL.part" "$CACHE/$TARBALL"
else
  echo "==> using cached $TARBALL"
fi

echo "==> unpacking"
rm -rf "$OUT"
mkdir -p "$OUT"
tar -xzf "$CACHE/$TARBALL" -C "$OUT"

APP="$OUT/resources/app"
PRODUCT="$APP/product.json"
[[ -f "$PRODUCT" ]] || { echo "unexpected tarball layout: no resources/app/product.json" >&2; exit 1; }

# --- 2. Version gate: bundled agent vs the extension's MIN_CLI --------------
# The bundled extension.js carries its MIN_CLI as an R-version string literal
# (the identifier itself is renamed by the bundler). Every R-literal in the
# bundle is a version the panel may demand, so the agent must satisfy the
# highest one.
AGENT_VER="$("$EXECAI_BIN" version | grep -oE 'R[0-9]+\.[0-9]+' | head -1)"
MIN_CLI="$(unzip -p "$VSIX" extension/dist/extension.js \
  | grep -oE '"R[0-9]+\.[0-9]+"' | tr -d '"' | sort -t. -k1.2,1n -k2,2n | tail -1)"
[[ -n "$AGENT_VER" ]] || { echo "could not read agent version from $EXECAI_BIN" >&2; exit 1; }
[[ -n "$MIN_CLI" ]]   || { echo "could not find MIN_CLI literal in $VSIX" >&2; exit 1; }
ver_ge() { # R6.58 >= R6.58 ?
  local a="${1#R}" b="${2#R}"
  [[ "${a%%.*}" -gt "${b%%.*}" ]] && return 0
  [[ "${a%%.*}" -lt "${b%%.*}" ]] && return 1
  [[ "${a#*.}" -ge "${b#*.}" ]]
}
if ! ver_ge "$AGENT_VER" "$MIN_CLI"; then
  echo "bundled agent $AGENT_VER is older than the extension's MIN_CLI $MIN_CLI — the panel would call commands the agent does not know" >&2
  exit 1
fi
echo "==> version gate: agent $AGENT_VER >= MIN_CLI $MIN_CLI"

# --- 3. Rebrand product.json ------------------------------------------------
# updateUrl is dropped on purpose: until our own channel is wired up (Ф6),
# an update check would offer to turn Studio back into vanilla VSCodium.
# The Open VSX gallery from VSCodium is kept as is.
jq --arg v "$STUDIO_VERSION" '
  .nameShort = "ExecAI Studio"
  | .nameLong = "ExecAI Studio"
  | .applicationName = "execai-studio"
  | .dataFolderName = ".execai-studio"
  | .serverApplicationName = "execai-studio-server"
  | .serverDataFolderName = ".execai-studio-server"
  | .urlProtocol = "execai-studio"
  | .win32MutexName = "execaistudio"
  | .win32DirName = "ExecAI Studio"
  | .win32NameVersion = ("ExecAI Studio " + $v)
  | .win32RegValueName = "ExecAIStudio"
  | .win32AppUserModelId = "ExecAI.Studio"
  | .win32ShellNameShort = "ExecAI Studio"
  | .darwinBundleIdentifier = "com.execai.studio"
  | .studioVersion = $v
  | del(.updateUrl)
  | .configurationDefaults = (.configurationDefaults // {}) + {
      "workbench.secondarySideBar.defaultVisibility": "visible",
      "chat.disableAIFeatures": true
    }
' "$PRODUCT" > "$PRODUCT.tmp"
mv "$PRODUCT.tmp" "$PRODUCT"

# --- 4. Brand assets and launcher names -------------------------------------
# The ExecAI logo goes everywhere VSCodium's mark appears: the window icon,
# the empty-editor letterpress watermarks, the workbench code-icon and the
# auth flow pages. One source of truth — branding/icon.png (the same image
# the marketplaces show for the extension) — wrapped into an SVG where the
# target is an SVG. The .ico favicons of the bundled auth extensions need an
# ico encoder we don't require; they never show outside a browser tab during
# OAuth and are left alone.
cp "$ROOT/branding/icon.png" "$APP/resources/linux/code.png"

LOGO_B64="$(base64 -w0 "$ROOT/branding/icon.png")"
logo_svg() { # $1 = opacity
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><image width="256" height="256" opacity="%s" href="data:image/png;base64,%s"/></svg>' \
    "$1" "$LOGO_B64"
}
for f in letterpress-light letterpress-dark letterpress-hcLight letterpress-hcDark; do
  logo_svg 0.45 > "$APP/out/media/$f.svg"
done
logo_svg 1 > "$APP/out/media/code-icon.svg"
for f in "$APP"/out/vs/sessions/contrib/chat/browser/media/letterpress-sessions-*.svg; do
  [[ -f "$f" ]] && logo_svg 0.45 > "$f"
done
[[ -f "$APP/extensions/github-authentication/media/code-icon.svg" ]] \
  && logo_svg 1 > "$APP/extensions/github-authentication/media/code-icon.svg"
[[ -f "$APP/extensions/npm/images/code.svg" ]] \
  && logo_svg 1 > "$APP/extensions/npm/images/code.svg"
mv "$OUT/codium" "$OUT/execai-studio"
# The bin/ wrapper is a shell script pointing at the electron binary by name.
if [[ -f "$OUT/bin/codium" ]]; then
  sed 's/"codium"/"execai-studio"/g; s|/codium|/execai-studio|g' "$OUT/bin/codium" > "$OUT/bin/execai-studio"
  chmod +x "$OUT/bin/execai-studio"
  rm "$OUT/bin/codium"
fi

# --- 5. Bundle the extension as a built-in ----------------------------------
# resources/app/extensions is scanned at startup; anything there is a built-in
# extension the user cannot accidentally uninstall.
EXT_DIR="$APP/extensions/execai.execai"
rm -rf "$EXT_DIR"
mkdir -p "$EXT_DIR"
TMP_EXT="$(mktemp -d)"
unzip -q "$VSIX" -d "$TMP_EXT"
cp -a "$TMP_EXT/extension/." "$EXT_DIR/"
rm -rf "$TMP_EXT"

# In Studio the chat lives in the secondary side bar (right, Cursor-style) and
# Ctrl+L focuses it, the way Cursor users expect. The marketplace vsix keeps
# the activity bar and the stock keymap: the `secondarySidebar` contribution
# key is too young for the older editors the plugin supports, and stealing
# Ctrl+L from a stock VS Code would be rude — so both changes happen here,
# on our own bundled copy only.
jq '
  .contributes.viewsContainers.secondarySidebar = .contributes.viewsContainers.activitybar
  | del(.contributes.viewsContainers.activitybar)
  | .contributes.keybindings = (.contributes.keybindings // []) + [
      { "key": "ctrl+l", "mac": "cmd+l", "command": "execai.chat.focus" }
    ]
' "$EXT_DIR/package.json" > "$EXT_DIR/package.json.tmp"
mv "$EXT_DIR/package.json.tmp" "$EXT_DIR/package.json"

# --- 6. Bundle the agent ----------------------------------------------------
# <install>/resources/execai/execai — the path bundledPath() in the extension
# resolves relative to appRoot. Keep the two in sync.
mkdir -p "$OUT/resources/execai"
cp "$EXECAI_BIN" "$OUT/resources/execai/execai"
chmod +x "$OUT/resources/execai/execai"

# --- 7. Sanity + package ----------------------------------------------------
jq -e '.nameShort == "ExecAI Studio" and (.updateUrl | not)' "$PRODUCT" >/dev/null
[[ -x "$OUT/execai-studio" ]]
[[ -f "$EXT_DIR/package.json" ]]

ARCHIVE="$DIST/ExecAI-Studio-linux-x64-${STUDIO_VERSION}.tar.gz"
tar -czf "$ARCHIVE" -C "$(dirname "$OUT")" "$(basename "$OUT")"
echo "==> built: $ARCHIVE"
echo "==> run locally: $OUT/execai-studio"
