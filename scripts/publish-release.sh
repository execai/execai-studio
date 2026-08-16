#!/usr/bin/env bash
# publish-release.sh — publishes an ExecAI Studio build to both update channels.
#
# Channels, in the order the editor checks them:
#   1. Yandex S3 (our production bucket, always reachable in Russia):
#      s3://execai-agent-prod/execai-studio/stable/ — the tarball, SHA256SUMS
#      and latest.json the in-editor checker reads;
#   2. GitHub Releases on execai/execai-studio — tag v<version> with the same
#      files; the checker falls back to the releases/latest API.
#
# Usage: publish-release.sh <version> --vsix PATH --agent PATH [--notes 'text']
#
# Requires:
#   * ~/.local/share/agent-vbai/yc-s3-credentials.env — AWS keys for S3
#   * gh CLI logged in with rights to execai/execai-studio

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="execai/execai-studio"
BUCKET="s3://execai-agent-prod/execai-studio/stable"
PUBLIC_BASE="https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable"

[[ $# -ge 1 ]] || { echo "Usage: $0 <version> --vsix PATH --agent PATH [--notes 'text']" >&2; exit 2; }
VERSION="$1"; shift
VSIX="" ; EXECAI_BIN="" ; NOTES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vsix)  VSIX="$2"; shift 2 ;;
    --agent) EXECAI_BIN="$2"; shift 2 ;;
    --notes) NOTES="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

CREDS="$HOME/.local/share/agent-vbai/yc-s3-credentials.env"
[[ -f "$CREDS" ]] || { echo "no $CREDS — cannot upload to S3" >&2; exit 2; }
# The env file sets shell vars without `export` — aws-cli reads only the
# environment, so export explicitly.
set -a; source "$CREDS"; set +a

echo "==> building ${VERSION}"
"$ROOT/build/build.sh" --vsix "$VSIX" --agent "$EXECAI_BIN" --version "$VERSION"

TARBALL="$ROOT/dist/ExecAI-Studio-linux-x64-${VERSION}.tar.gz"
[[ -f "$TARBALL" ]] || { echo "build did not produce $TARBALL" >&2; exit 1; }

cd "$ROOT/dist"
sha256sum "$(basename "$TARBALL")" > SHA256SUMS
SHA256="$(cut -d' ' -f1 SHA256SUMS)"

jq -n --arg v "$VERSION" --arg url "$PUBLIC_BASE/$(basename "$TARBALL")" --arg sha "$SHA256" '
  { name: ("ExecAI Studio " + $v), version: $v, url: $url, sha256: $sha }
' > latest.json

echo "==> uploading to ${BUCKET}"
for f in "$(basename "$TARBALL")" SHA256SUMS latest.json; do
  aws --endpoint-url=https://storage.yandexcloud.net s3 cp "$f" "$BUCKET/$f"
done

echo "==> publishing GitHub release v${VERSION}"
gh release create "v${VERSION}" --repo "$REPO" \
  --title "ExecAI Studio ${VERSION}" \
  --notes "${NOTES:-ExecAI Studio ${VERSION} — Linux x64 tarball. Mirror: $PUBLIC_BASE/$(basename "$TARBALL")}" \
  "$TARBALL" SHA256SUMS

echo "==> done: $PUBLIC_BASE/latest.json and https://github.com/$REPO/releases/tag/v${VERSION}"
