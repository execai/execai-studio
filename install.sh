#!/usr/bin/env bash
# ExecAI Studio installer for Linux and macOS. One command:
#
#   curl -fsSL https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable/install.sh | bash
#   # or
#   curl -fsSL https://raw.githubusercontent.com/execai/execai-studio/main/install.sh | bash
#
# What it does, and why a script at all:
# * picks the artifact for this OS/arch and downloads it, GitHub first,
#   the Yandex mirror (always reachable in Russia) second;
# * macOS: the bundle ships unsigned (no Apple developer account yet), so the
#   script ad-hoc signs it locally — and because curl never sets the
#   quarantine attribute, Gatekeeper has nothing to complain about;
# * Linux: unpacks to ~/.local/opt, links ~/.local/bin/execai-studio and
#   writes a .desktop entry so the app shows up in menus.
# No sudo anywhere.

set -euo pipefail

MIRROR="https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable"
REPO="execai/execai-studio"

os="$(uname -s)"; arch="$(uname -m)"
case "$os/$arch" in
  Linux/x86_64)  PLATFORM="linux-x64" ;;
  Darwin/x86_64) PLATFORM="darwin-x64" ;;
  Darwin/arm64)  PLATFORM="darwin-arm64" ;;
  *) echo "unsupported platform: $os/$arch" >&2; exit 1 ;;
esac

# Version: the GitHub release redirect first, latest.json on the mirror second.
VERSION="$(curl -fsSLI --max-time 15 -o /dev/null -w '%{url_effective}' \
  "https://github.com/$REPO/releases/latest" 2>/dev/null | sed -n 's|.*/v\([0-9][0-9.]*\)$|\1|p' || true)"
if [[ -z "$VERSION" ]]; then
  VERSION="$(curl -fsSL --max-time 15 "$MIRROR/latest.json" 2>/dev/null \
    | sed -n 's/.*"version"[^"]*"\([^"]*\)".*/\1/p' | head -1 || true)"
fi
[[ -n "$VERSION" ]] || { echo "could not determine the latest version" >&2; exit 1; }

FILE="ExecAI-Studio-${PLATFORM}-${VERSION}.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> ExecAI Studio ${VERSION} (${PLATFORM})"
if ! curl -fL --retry 2 -o "$TMP/$FILE" \
    "https://github.com/$REPO/releases/download/v${VERSION}/${FILE}"; then
  echo "==> GitHub failed, trying the mirror"
  curl -fL --retry 2 -o "$TMP/$FILE" "$MIRROR/$FILE"
fi

# Checksum: SHA256SUMS from GitHub, then the mirror; a missing file is not fatal.
if curl -fsSL --max-time 15 -o "$TMP/SHA256SUMS" "https://github.com/$REPO/releases/download/v${VERSION}/SHA256SUMS" 2>/dev/null \
   || curl -fsSL --max-time 15 -o "$TMP/SHA256SUMS" "$MIRROR/SHA256SUMS" 2>/dev/null; then
  want="$(grep " $FILE\$" "$TMP/SHA256SUMS" | cut -d' ' -f1 || true)"
  if [[ -n "$want" ]]; then
    got="$(shasum -a 256 "$TMP/$FILE" 2>/dev/null | cut -d' ' -f1 || sha256sum "$TMP/$FILE" | cut -d' ' -f1)"
    [[ "$want" == "$got" ]] || { echo "checksum mismatch — aborting" >&2; exit 1; }
    echo "==> checksum ok"
  fi
fi

tar -xzf "$TMP/$FILE" -C "$TMP"

if [[ "$PLATFORM" == darwin-* ]]; then
  DEST="$HOME/Applications/ExecAI Studio.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  mv "$TMP/ExecAI-Studio-${PLATFORM}/ExecAI Studio.app" "$DEST"
  # The bundle was modified after VSCodium signed it; an ad-hoc signature
  # makes it launchable (arm64 refuses unsigned binaries outright).
  codesign --force --deep -s - "$DEST" 2>/dev/null || true
  xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
  mkdir -p "$HOME/.local/bin"
  ln -sf "$DEST/Contents/Resources/app/bin/execai-studio" "$HOME/.local/bin/execai-studio"
  echo "==> installed: $DEST (also linked as ~/.local/bin/execai-studio)"
  echo "    open it from Launchpad or: open -a 'ExecAI Studio'"
else
  DEST="$HOME/.local/opt/execai-studio"
  rm -rf "$DEST"
  mkdir -p "$HOME/.local/opt" "$HOME/.local/bin" "$HOME/.local/share/applications"
  mv "$TMP/ExecAI-Studio-${PLATFORM}" "$DEST"
  ln -sf "$DEST/bin/execai-studio" "$HOME/.local/bin/execai-studio"
  cat > "$HOME/.local/share/applications/execai-studio.desktop" <<DESK
[Desktop Entry]
Name=ExecAI Studio
Comment=Code editor with the ExecAI agent built in
Exec=$DEST/bin/execai-studio %F
Icon=$DEST/resources/app/resources/linux/code.png
Type=Application
Categories=Development;IDE;
StartupWMClass=execai-studio
MimeType=x-scheme-handler/execai-studio;inode/directory;text/plain;
DESK
  # The execai-studio:// scheme is how the editor's own «Download Update»
  # hands control back to the ExecAI extension; register it with the desktop.
  command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  command -v xdg-mime >/dev/null && xdg-mime default execai-studio.desktop x-scheme-handler/execai-studio 2>/dev/null || true
  # inode/directory in MimeType puts Studio into «Open With» for folders in
  # GNOME Files, Dolphin, Thunar and friends; the default handler for folders
  # is deliberately NOT changed (that would hijack double-click on folders).
  echo "==> installed: $DEST"
  echo "    run: execai-studio (make sure ~/.local/bin is on PATH) or find it in the app menu"
fi
