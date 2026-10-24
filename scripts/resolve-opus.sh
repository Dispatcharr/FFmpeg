#!/usr/bin/env bash
# Print the latest Opus release for major version OPUS_SERIES (default 1).
#
# Usage:
#   ./scripts/resolve-opus.sh                 # 1.6.1
#   ./scripts/resolve-opus.sh --url           # tarball URL
#   ./scripts/resolve-opus.sh --series 1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "${ROOT}/versions.env"

SERIES="${OPUS_SERIES:-1}"
mode="--version"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --series)
      [[ $# -ge 2 ]] || { echo "--series needs a major version (e.g. 1)" >&2; exit 1; }
      SERIES="$2"
      shift 2
      ;;
    --series=*)
      SERIES="${1#--series=}"
      shift
      ;;
    --url|--version|--tag)
      mode="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1 (use --version/--tag, --url, or --series N)" >&2
      exit 1
      ;;
  esac
done

if [[ ! "$SERIES" =~ ^[0-9]+$ ]]; then
  echo "SERIES must be a major version integer (e.g. 1), got: ${SERIES}" >&2
  exit 1
fi

mapfile -t versions < <(
  curl -fsSL https://downloads.xiph.org/releases/opus/ \
    | grep -oE "opus-${SERIES}\.[0-9]+(\.[0-9]+)?\.tar\.gz" \
    | sed -E 's/^opus-//; s/\.tar\.gz$//' \
    | sort -u \
    | sort -V
)

if [[ ${#versions[@]} -eq 0 ]]; then
  echo "No Opus releases found for series ${SERIES}" >&2
  exit 1
fi

latest="${versions[-1]}"
url="https://downloads.xiph.org/releases/opus/opus-${latest}.tar.gz"

case "$mode" in
  --url) echo "$url" ;;
  --version|--tag) echo "$latest" ;;
  *)
    echo "Unknown option: $mode" >&2
    exit 1
    ;;
esac
