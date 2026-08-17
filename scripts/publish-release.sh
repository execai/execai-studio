#!/usr/bin/env bash
# publish-release.sh — builds ExecAI Studio for every platform and publishes
# to both update channels.
#
# Channels (the editor and the install scripts try GitHub first, then the mirror):
#   1. Yandex S3 (our production bucket, always reachable in Russia):
#      s3://execai-agent-prod/execai-studio/stable/ — artifacts, SHA256SUMS,
#      latest.json (with per-platform urls) and the install scripts;
#   2. GitHub Releases on execai/execai-studio — tag v<version> with the same
#      artifacts; the checker falls back to the releases/latest API.
#
# Usage:
#   publish-release.sh <version> --vsix PATH --agent-dir DIR --agent-version RX.Y [--notes 'text']
#
# --agent-dir holds per-platform agent binaries named the way the agent's own
# releases name them: execai-linux-amd64, execai-windows-amd64.exe,
# execai-darwin-amd64, execai-darwin-arm64.
#
# Requires:
#   * ~/.local/share/agent-vbai/yc-s3-credentials.env — AWS keys for S3
#   * gh CLI logged in with rights to execai/execai-studio

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="execai/execai-studio"
BUCKET="s3://execai-agent-prod/execai-studio/stable"
PUBLIC_BASE="https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable"

[[ $# -ge 1 ]] || { echo "Usage: $0 <version> --vsix PATH --agent-dir DIR --agent-version RX.Y [--notes 'text']" >&2; exit 2; }
VERSION="$1"; shift
VSIX="" ; AGENT_DIR="" ; AGENT_VERSION="" ; NOTES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vsix)          VSIX="$2"; shift 2 ;;
    --agent-dir)     AGENT_DIR="$2"; shift 2 ;;
    --agent-version) AGENT_VERSION="$2"; shift 2 ;;
    --notes)         NOTES="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done
[[ -f "$VSIX" && -d "$AGENT_DIR" && -n "$AGENT_VERSION" ]] \
  || { echo "--vsix, --agent-dir and --agent-version are all required" >&2; exit 2; }

CREDS="$HOME/.local/share/agent-vbai/yc-s3-credentials.env"
[[ -f "$CREDS" ]] || { echo "no $CREDS — cannot upload to S3" >&2; exit 2; }
# The env file sets shell vars without `export` — aws-cli reads only the
# environment, so export explicitly.
set -a; source "$CREDS"; set +a

# platform → agent binary name (the agent's own release naming)
declare -A AGENT=(
  [linux-x64]="execai-linux-amd64"
  [win32-x64]="execai-windows-amd64.exe"
  [darwin-x64]="execai-darwin-amd64"
  [darwin-arm64]="execai-darwin-arm64"
)

ARTIFACTS=()
for p in linux-x64 win32-x64 darwin-x64 darwin-arm64; do
  bin="$AGENT_DIR/${AGENT[$p]}"
  [[ -f "$bin" ]] || { echo "missing agent binary: $bin" >&2; exit 2; }
  echo "==> building $p"
  "$ROOT/build/build.sh" --platform "$p" --vsix "$VSIX" --agent "$bin" \
    --agent-version "$AGENT_VERSION" --version "$VERSION"
  ext="tar.gz"; [[ "$p" == win32-* ]] && ext="zip"
  ARTIFACTS+=("ExecAI-Studio-${p}-${VERSION}.${ext}")
done

cd "$ROOT/dist"
sha256sum "${ARTIFACTS[@]}" > SHA256SUMS

# latest.json: per-platform urls; the flat `url` stays for pre-0.2.9 checkers.
{
  printf '{ "name": "ExecAI Studio %s", "version": "%s",\n' "$VERSION" "$VERSION"
  printf '  "url": "%s/%s",\n' "$PUBLIC_BASE" "${ARTIFACTS[0]}"
  printf '  "urls": {\n'
  first=1
  for a in "${ARTIFACTS[@]}"; do
    plat="${a#ExecAI-Studio-}"; plat="${plat%-${VERSION}.*}"
    [[ $first -eq 0 ]] && printf ',\n'
    printf '    "%s": "%s/%s"' "$plat" "$PUBLIC_BASE" "$a"
    first=0
  done
  printf '\n  }\n}\n'
} > latest.json
jq -e .version latest.json >/dev/null # syntax check

# Feed for VS Code's own updater (Help → Check for Updates):
# {updateUrl}/{quality}/{platform}/{arch}/latest.json with
# {url, version, productVersion, timestamp}. productVersion must be the exact
# string stamped into product.json.version (base VSCodium + "+" + Studio):
# the updater compares them with semver.compareBuild. `url` is what the
# updater opens on Linux; Windows/macOS open product.json.downloadUrl instead.
CODIUM_VERSION="$(sed -n 's/^VSCODIUM_VERSION="\${VSCODIUM_VERSION:-\(.*\)}"$/\1/p' "$ROOT/build/build.sh")"
[[ -n "$CODIUM_VERSION" ]] || { echo "could not read VSCODIUM_VERSION from build.sh" >&2; exit 1; }
PRODUCT_VERSION="${CODIUM_VERSION}+${VERSION}"
NOW_MS="$(date +%s)000"
mkdir -p update
# On Windows the core updater appends its setup kind to the path
# (…/win32/x64/{archive|user|system}/latest.json), so the feed goes into all
# three; Linux/macOS read …/{platform}/{arch}/latest.json directly.
declare -A FEED=( [linux-x64]="linux/x64" [win32-x64]="win32/x64/archive win32/x64/user win32/x64/system" [darwin-x64]="darwin/x64" [darwin-arm64]="darwin/arm64" )
for a in "${ARTIFACTS[@]}"; do
  plat="${a#ExecAI-Studio-}"; plat="${plat%-${VERSION}.*}"
  sum="$(grep " $a\$" SHA256SUMS | cut -d' ' -f1)"
  for sub in ${FEED[$plat]}; do
    dir="update/stable/$sub"
    mkdir -p "$dir"
    jq -n --arg url "$PUBLIC_BASE/$a" --arg v "$VERSION" --arg pv "$PRODUCT_VERSION" \
          --arg ts "$NOW_MS" --arg sha "$sum" \
      '{ url: $url, name: $v, version: $pv, productVersion: $pv, timestamp: ($ts|tonumber), sha256hash: $sha }' \
      > "$dir/latest.json"
  done
done

echo "==> uploading to ${BUCKET}"
for f in "${ARTIFACTS[@]}" SHA256SUMS latest.json; do
  aws --endpoint-url=https://storage.yandexcloud.net s3 cp --no-progress "$f" "$BUCKET/$f"
done
# The updater feed lives one level up from stable/ (…/execai-studio/update/…).
aws --endpoint-url=https://storage.yandexcloud.net s3 cp --no-progress --recursive \
  --content-type application/json --cache-control "max-age=300" \
  update/ "${BUCKET%/stable}/update/"
for s in install.sh install.ps1; do
  aws --endpoint-url=https://storage.yandexcloud.net s3 cp --no-progress "$ROOT/$s" "$BUCKET/$s"
done

echo "==> publishing GitHub release v${VERSION}"
gh release create "v${VERSION}" --repo "$REPO" \
  --title "ExecAI Studio ${VERSION}" \
  --notes "${NOTES:-ExecAI Studio ${VERSION} — Linux x64, Windows x64, macOS x64/arm64. Mirror: $PUBLIC_BASE/latest.json}" \
  "${ARTIFACTS[@]/#/$ROOT/dist/}" "$ROOT/dist/SHA256SUMS"

echo "==> done: $PUBLIC_BASE/latest.json and https://github.com/$REPO/releases/tag/v${VERSION}"
