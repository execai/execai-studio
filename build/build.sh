#!/usr/bin/env bash
# Builds ExecAI Studio for one platform by repacking a VSCodium release.
#
# Why repack instead of compiling. The whole point of Studio (docs/plan.md) is a
# mechanical build with no core patches. Everything we change lives in files a
# release artifact already exposes: product.json, icons, bundled extensions and
# the agent binary. Repacking takes seconds on any Linux box for every target —
# Windows and macOS included: the exe is rebranded with pure-JS resedit, the
# .app with plistlib. No build farm, no cross-compilers.
#
# Signing is the one thing a repack cannot give (Ф6 in the plan): the Windows
# exe and the .app ship unsigned, and the install scripts are the path around
# that until we have certificates — curl|bash never sets the quarantine bit on
# macOS, and install.ps1 extracts without the mark-of-the-web on Windows.
#
# Inputs (flags or env):
#   --platform P    linux-x64 | win32-x64 | darwin-x64 | darwin-arm64 (env PLATFORM)
#   --vsix PATH     extension package to bundle        (env VSIX)
#   --agent PATH    execai binary FOR THAT PLATFORM    (env EXECAI_BIN)
#   --agent-version RX.Y  version of that binary; required for cross targets
#                   (a win/mac binary cannot be executed here to ask it)
#   --codium VER    VSCodium release, e.g. 1.126.04524 (env VSCODIUM_VERSION)
#   --version VER   Studio version stamp               (env STUDIO_VERSION)
#
# Output: dist/ExecAI-Studio-<platform>-<version>.{tar.gz|zip} plus the
# unpacked tree in out/ for local runs.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VSCODIUM_VERSION="${VSCODIUM_VERSION:-1.126.04524}"
STUDIO_VERSION="${STUDIO_VERSION:-0.1.0}"
PLATFORM="${PLATFORM:-linux-x64}"
VSIX="${VSIX:-}"
EXECAI_BIN="${EXECAI_BIN:-}"
AGENT_VERSION="${AGENT_VERSION:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)      PLATFORM="$2"; shift 2 ;;
    --vsix)          VSIX="$2"; shift 2 ;;
    --agent)         EXECAI_BIN="$2"; shift 2 ;;
    --agent-version) AGENT_VERSION="$2"; shift 2 ;;
    --codium)        VSCODIUM_VERSION="$2"; shift 2 ;;
    --version)       STUDIO_VERSION="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

case "$PLATFORM" in
  linux-x64)    ASSET="VSCodium-linux-x64-${VSCODIUM_VERSION}.tar.gz"; PACK=tar ;;
  win32-x64)    ASSET="VSCodium-win32-x64-${VSCODIUM_VERSION}.zip";    PACK=zip ;;
  darwin-x64)   ASSET="VSCodium-darwin-x64-${VSCODIUM_VERSION}.zip";  PACK=tar ;;
  darwin-arm64) ASSET="VSCodium-darwin-arm64-${VSCODIUM_VERSION}.zip"; PACK=tar ;;
  *) echo "unknown platform: $PLATFORM" >&2; exit 2 ;;
esac

[[ -f "$VSIX" ]] || { echo "extension package not found: --vsix PATH is required" >&2; exit 2; }
[[ -f "$EXECAI_BIN" ]] || { echo "agent binary not found: --agent PATH is required" >&2; exit 2; }
for tool in jq unzip curl tar node python3; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done

CACHE="$ROOT/build/cache"
OUT="$ROOT/out/ExecAI-Studio-${PLATFORM}"
DIST="$ROOT/dist"
mkdir -p "$CACHE" "$DIST"

# --- 1. Fetch the VSCodium release (cached) ---------------------------------
if [[ ! -f "$CACHE/$ASSET" ]]; then
  echo "==> downloading $ASSET"
  curl -fL --retry 3 -o "$CACHE/$ASSET.part" \
    "https://github.com/VSCodium/vscodium/releases/download/${VSCODIUM_VERSION}/${ASSET}"
  mv "$CACHE/$ASSET.part" "$CACHE/$ASSET"
else
  echo "==> using cached $ASSET"
fi

echo "==> unpacking ($PLATFORM)"
rm -rf "$OUT"
mkdir -p "$OUT"
case "$ASSET" in
  *.tar.gz) tar -xzf "$CACHE/$ASSET" -C "$OUT" ;;
  *.zip)    unzip -q "$CACHE/$ASSET" -d "$OUT" ;;
esac

# Locate the app root per platform layout.
case "$PLATFORM" in
  darwin-*)
    [[ -d "$OUT/VSCodium.app" ]] || { echo "unexpected zip layout: no VSCodium.app" >&2; exit 1; }
    mv "$OUT/VSCodium.app" "$OUT/ExecAI Studio.app"
    CONTENTS="$OUT/ExecAI Studio.app/Contents"
    APP="$CONTENTS/Resources/app"
    RES_PARENT="$CONTENTS/Resources"
    ;;
  *)
    APP="$OUT/resources/app"
    RES_PARENT="$OUT/resources"
    ;;
esac
PRODUCT="$APP/product.json"
[[ -f "$PRODUCT" ]] || { echo "unexpected layout: no product.json at $PRODUCT" >&2; exit 1; }

# --- 2. Version gate: bundled agent vs the extension's MIN_CLI --------------
# The bundled extension.js carries its MIN_CLI as an R-version string literal
# (the identifier itself is renamed by the bundler). Every R-literal in the
# bundle is a version the panel may demand, so the agent must satisfy the
# highest one. Cross-target binaries cannot be executed here — their version
# comes from --agent-version instead.
if [[ -z "$AGENT_VERSION" ]]; then
  if [[ "$PLATFORM" == "linux-x64" ]]; then
    AGENT_VERSION="$("$EXECAI_BIN" version | grep -oE 'R[0-9]+\.[0-9]+' | head -1)"
  else
    echo "--agent-version is required for $PLATFORM (cannot run a cross binary to ask it)" >&2
    exit 2
  fi
fi
MIN_CLI="$(unzip -p "$VSIX" extension/dist/extension.js \
  | grep -oE '"R[0-9]+\.[0-9]+"' | tr -d '"' | sort -t. -k1.2,1n -k2,2n | tail -1)"
[[ -n "$AGENT_VERSION" ]] || { echo "could not read agent version" >&2; exit 1; }
[[ -n "$MIN_CLI" ]]       || { echo "could not find MIN_CLI literal in $VSIX" >&2; exit 1; }
ver_ge() { # R6.58 >= R6.58 ?
  local a="${1#R}" b="${2#R}"
  [[ "${a%%.*}" -gt "${b%%.*}" ]] && return 0
  [[ "${a%%.*}" -lt "${b%%.*}" ]] && return 1
  [[ "${a#*.}" -ge "${b#*.}" ]]
}
if ! ver_ge "$AGENT_VERSION" "$MIN_CLI"; then
  echo "bundled agent $AGENT_VERSION is older than the extension's MIN_CLI $MIN_CLI — the panel would call commands the agent does not know" >&2
  exit 1
fi
echo "==> version gate: agent $AGENT_VERSION >= MIN_CLI $MIN_CLI"

# --- 3. Rebrand product.json ------------------------------------------------
# updateUrl is dropped on purpose: the extension checks our two channels
# itself (mirror + GitHub); the built-in updater would offer to turn Studio
# back into vanilla VSCodium. The Open VSX gallery from VSCodium is kept.
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
  | .licenseUrl = "https://github.com/execai/execai-studio/blob/main/LICENSE"
  | del(.updateUrl)
  | .configurationDefaults = (.configurationDefaults // {}) + {
      "workbench.secondarySideBar.defaultVisibility": "visible",
      "chat.disableAIFeatures": true
    }
' "$PRODUCT" > "$PRODUCT.tmp"
mv "$PRODUCT.tmp" "$PRODUCT"

# --- 3b. License layering ---------------------------------------------------
# The bundle is an aggregate: ExecAI parts under BUSL-1.1, the VS Code core
# under MIT. Their notices (LICENSE.txt, ThirdPartyNotices.txt) stay untouched
# — MIT demands it; ours goes in a separate file next to them.
{
  cat <<'NOTICE'
ExecAI Studio — license layout
==============================

This distribution is an aggregate of separately licensed works:

* The ExecAI components — the bundled ExecAI extension, the bundled `execai`
  agent binary, the ExecAI branding and the build scripts that produced this
  distribution — are licensed under the Business Source License 1.1, see below.
* The Visual Studio Code sources this build is based on are MIT
  (c) Microsoft Corporation — see LICENSE.txt in this directory.
* Other bundled third-party components are listed in ThirdPartyNotices.txt.

ExecAI Studio is not affiliated with Microsoft or VSCodium.

--------------------------------------------------------------------------

NOTICE
  cat "$ROOT/LICENSE"
} > "$APP/LICENSE-EXECAI.txt"

# --- 4. Brand assets and launcher names -------------------------------------
# The ExecAI logo goes everywhere VSCodium's mark appears. One source of truth
# — branding/icon.png — wrapped into SVG/ICO/ICNS containers as needed (both
# newer formats embed PNG as is, no image tooling involved).
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

case "$PLATFORM" in
  linux-x64)
    cp "$ROOT/branding/icon.png" "$APP/resources/linux/code.png"
    mv "$OUT/codium" "$OUT/execai-studio"
    if [[ -f "$OUT/bin/codium" ]]; then
      sed 's/"codium"/"execai-studio"/g; s|/codium|/execai-studio|g' "$OUT/bin/codium" > "$OUT/bin/execai-studio"
      chmod +x "$OUT/bin/execai-studio"
      rm "$OUT/bin/codium"
    fi
    ;;
  win32-x64)
    # resedit (pure JS) swaps the exe icon and version strings right here on Linux.
    if [[ ! -d "$ROOT/build/node_modules/resedit" ]]; then
      (cd "$ROOT/build" && npm install --no-audit --no-fund >/dev/null)
    fi
    node "$ROOT/build/make-icons.mjs" ico "$ROOT/branding/icon.png" "$CACHE/icon.ico"
    NODE_PATH="$ROOT/build/node_modules" node "$ROOT/build/patch-exe.mjs" \
      "$OUT/VSCodium.exe" "$CACHE/icon.ico" "$STUDIO_VERSION" "$OUT/ExecAI Studio.exe"
    rm "$OUT/VSCodium.exe"
    # The bin\ wrappers reference the exe by name.
    for w in "$OUT/bin/codium.cmd" "$OUT/bin/codium"; do
      [[ -f "$w" ]] || continue
      n="$(dirname "$w")/execai-studio${w##*/codium}"
      sed 's/VSCodium\.exe/ExecAI Studio.exe/g; s/"codium"/"execai-studio"/g' "$w" > "$n"
      rm "$w"
    done
    ;;
  darwin-*)
    node "$ROOT/build/make-icons.mjs" icns "$ROOT/branding/icon.png" "$CACHE/icon.icns"
    # Keep the icns file name Info.plist already points at.
    ICNS_NAME="$(python3 -c "import plistlib,sys; print(plistlib.load(open('$CONTENTS/Info.plist','rb'))['CFBundleIconFile'])")"
    cp "$CACHE/icon.icns" "$CONTENTS/Resources/${ICNS_NAME%.icns}.icns"
    python3 - "$CONTENTS/Info.plist" <<'PYEOF'
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, 'rb'))
d['CFBundleName'] = 'ExecAI Studio'
d['CFBundleDisplayName'] = 'ExecAI Studio'
d['CFBundleIdentifier'] = 'com.execai.studio'
for t in d.get('CFBundleURLTypes', []):
    t['CFBundleURLName'] = 'com.execai.studio'
    t['CFBundleURLSchemes'] = ['execai-studio']
plistlib.dump(d, open(p, 'wb'))
PYEOF
    # Modifying the bundle invalidates VSCodium's signature; install.sh
    # re-signs ad hoc on the user's machine (codesign is macOS-only).
    rm -rf "$CONTENTS/_CodeSignature"
    if [[ -f "$APP/bin/codium" ]]; then
      sed 's/"codium"/"execai-studio"/g' "$APP/bin/codium" > "$APP/bin/execai-studio"
      chmod +x "$APP/bin/execai-studio"
      rm "$APP/bin/codium"
    fi
    ;;
esac

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
# <resources>/execai/execai[.exe] — the path bundledPath() in the extension
# resolves relative to appRoot. Keep the two in sync.
AGENT_NAME="execai"; [[ "$PLATFORM" == win32-* ]] && AGENT_NAME="execai.exe"
mkdir -p "$RES_PARENT/execai"
cp "$EXECAI_BIN" "$RES_PARENT/execai/$AGENT_NAME"
chmod +x "$RES_PARENT/execai/$AGENT_NAME"

# --- 7. Sanity + package ----------------------------------------------------
jq -e '.nameShort == "ExecAI Studio" and (.updateUrl | not)' "$PRODUCT" >/dev/null
[[ -f "$EXT_DIR/package.json" ]]
# The MIT notices must survive the repack, ours must be present.
[[ -f "$APP/LICENSE.txt" && -f "$APP/ThirdPartyNotices.txt" && -f "$APP/LICENSE-EXECAI.txt" ]] \
  || { echo "license layering broken: LICENSE.txt / ThirdPartyNotices.txt / LICENSE-EXECAI.txt must all exist" >&2; exit 1; }

case "$PACK" in
  tar)
    ARCHIVE="$DIST/ExecAI-Studio-${PLATFORM}-${STUDIO_VERSION}.tar.gz"
    tar -czf "$ARCHIVE" -C "$(dirname "$OUT")" "$(basename "$OUT")"
    ;;
  zip)
    ARCHIVE="$DIST/ExecAI-Studio-${PLATFORM}-${STUDIO_VERSION}.zip"
    rm -f "$ARCHIVE"
    python3 - "$OUT" "$ARCHIVE" <<'PYEOF'
import os, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
base = os.path.basename(src)
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.join(base, os.path.relpath(p, src)))
PYEOF
    ;;
esac
echo "==> built: $ARCHIVE"
