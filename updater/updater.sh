#!/usr/bin/env bash
# ExecAI Studio updater for Linux and macOS. Started by the editor right before
# it quits; runs in a terminal window when one can be opened so the user sees
# what happens, and silently otherwise. Everything is done here — waiting for
# the editor to close, downloading (GitHub first, mirror second) with a
# percentage, SHA-256, unpacking, an atomic swap, starting the new build. On
# failure it explains why and puts the previous version back.
#
#   updater.sh <version> <install-dir> [workspace-folder]
#   install-dir: <…>/execai-studio (linux) or <…>/ExecAI Studio.app (macOS)

set -euo pipefail
VERSION="$1"; INSTALL="$2"; FOLDER="${3:-}"
REPO="execai/execai-studio"
MIRROR="https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable"

os="$(uname -s)"; arch="$(uname -m)"
case "$os/$arch" in
  Linux/x86_64)  PLATFORM="linux-x64" ;;
  Darwin/x86_64) PLATFORM="darwin-x64" ;;
  Darwin/arm64)  PLATFORM="darwin-arm64" ;;
  *) echo "unsupported platform: $os/$arch" >&2; exit 1 ;;
esac
FILE="ExecAI-Studio-${PLATFORM}-${VERSION}.tar.gz"
PARENT="$(dirname "$INSTALL")"; LEAF="$(basename "$INSTALL")"
STAGING="$PARENT/$LEAF.staging-$VERSION"
OLD="$INSTALL.old"

step() { printf '  [%s/6] %s' "$1" "$2"; }
done_() { printf ' done\n'; }
fail() {
  printf '\n  update failed: %s\n' "$1" >&2
  if [[ ! -e "$INSTALL" && -e "$OLD" ]]; then mv "$OLD" "$INSTALL"; echo "  the previous version was restored." >&2; fi
  if [[ -t 0 ]]; then echo "  press Enter to close"; read -r _; fi
  exit 1
}
trap 'fail "unexpected error on line $LINENO"' ERR

# The updater itself may be fixed in the release being installed: fetch the
# target release's updater.sh and hand over to it; on failure keep this copy.
if [[ -z "${EXECAI_UPDATER_FRESH:-}" ]]; then
  SELF="${TMPDIR:-/tmp}/execai-studio-updater-$VERSION.sh"
  if curl -fsSL --max-time 20 -o "$SELF" "https://raw.githubusercontent.com/$REPO/v$VERSION/updater/updater.sh" 2>/dev/null \
     || curl -fsSL --max-time 20 -o "$SELF" "$MIRROR/updater.sh" 2>/dev/null; then
    if [[ -s "$SELF" ]] && bash -n "$SELF" 2>/dev/null; then
      chmod +x "$SELF"
      EXECAI_UPDATER_FRESH=1 exec bash "$SELF" "$VERSION" "$INSTALL" "$FOLDER"
    fi
  fi
fi

echo; echo "  ExecAI Studio update $VERSION"; echo "  ------------------------------"

step 1 "waiting for ExecAI Studio to close..."
deadline=$((SECONDS + 180))
while (( SECONDS < deadline )); do
  if ! pgrep -f "^$INSTALL/" >/dev/null 2>&1 && ! pgrep -f "$INSTALL/Contents/MacOS" >/dev/null 2>&1; then break; fi
  sleep 0.5
done
done_

# Sweep leftovers of earlier attempts; use a version-specific staging dir.
for d in "$PARENT/$LEAF".staging*; do [[ -e "$d" ]] && rm -rf "$d" 2>/dev/null || true; done
mkdir -p "$STAGING"

echo "  [2/6] downloading $FILE"
dl() { if [[ -t 2 ]]; then curl -fL --retry 2 -# -o "$STAGING/$FILE" "$1"; else curl -fL --retry 2 -sS -o "$STAGING/$FILE" "$1"; fi; }
if ! dl "https://github.com/$REPO/releases/download/v${VERSION}/${FILE}"; then
  echo "        GitHub failed, trying the mirror"
  dl "$MIRROR/$FILE" || fail "could not download $FILE"
fi

step 3 "verifying checksum..."
SUMS="$(curl -fsSL --max-time 20 "https://github.com/$REPO/releases/download/v${VERSION}/SHA256SUMS" 2>/dev/null || curl -fsSL --max-time 20 "$MIRROR/SHA256SUMS" 2>/dev/null || true)"
[[ -n "$SUMS" ]] || fail "could not fetch SHA256SUMS"
want="$(grep " $FILE\$" <<<"$SUMS" | cut -d' ' -f1)"
[[ -n "$want" ]] || fail "$FILE is missing from SHA256SUMS"
got="$(shasum -a 256 "$STAGING/$FILE" 2>/dev/null | cut -d' ' -f1 || sha256sum "$STAGING/$FILE" | cut -d' ' -f1)"
[[ "$want" == "$got" ]] || fail "checksum mismatch - the file is corrupted or tampered with"
done_

echo -n "  [4/6] unpacking..."
TOTAL="$(tar -tzf "$STAGING/$FILE" | wc -l | tr -d ' ')"
if [[ -t 2 && "$TOTAL" -gt 0 ]]; then
  n=0
  tar -xzvf "$STAGING/$FILE" -C "$STAGING" 2>&1 | while IFS= read -r _; do
    n=$((n+1)); if (( n % 200 == 0 || n == TOTAL )); then printf '\r  [4/6] unpacking... %3d%%' $(( n * 100 / TOTAL )); fi
  done
  printf '\r  [4/6] unpacking... 100%%'
else
  tar -xzf "$STAGING/$FILE" -C "$STAGING"
fi
done_
rm -f "$STAGING/$FILE"
TOP="$(find "$STAGING" -mindepth 1 -maxdepth 1 -type d | head -1)"
FRESH="$TOP"
if [[ "$PLATFORM" == darwin-* ]]; then
  FRESH="$(find "$TOP" -mindepth 1 -maxdepth 1 -name '*.app' | head -1)"
  [[ -n "$FRESH" ]] || fail "no .app in the archive"
  codesign --force --deep -s - "$FRESH" 2>/dev/null || true
  xattr -dr com.apple.quarantine "$FRESH" 2>/dev/null || true
fi

step 5 "installing..."
rm -rf "$OLD"
mv "$INSTALL" "$OLD"
mv "$FRESH" "$INSTALL"
done_

step 6 "starting ExecAI Studio $VERSION..."
if [[ "$PLATFORM" == darwin-* ]]; then
  if [[ -n "$FOLDER" ]]; then open -a "$INSTALL" "$FOLDER"; else open -a "$INSTALL"; fi
else
  if [[ -n "$FOLDER" ]]; then setsid nohup "$INSTALL/bin/execai-studio" "$FOLDER" >/dev/null 2>&1 < /dev/null &
  else setsid nohup "$INSTALL/bin/execai-studio" >/dev/null 2>&1 < /dev/null & fi
fi
done_
rm -rf "$STAGING" 2>/dev/null || true
sleep 2
