#!/usr/bin/env bash
# Print the latest official FFmpeg release for major version FFMPEG_SERIES (default 9).
# Matches 9.0, 9.0.2, 9.1, 9.1.1. Does not match 8.x or 10.x.
# Usage:
#   ./scripts/resolve-ffmpeg-version.sh           # prints e.g. 9.0.2
#   ./scripts/resolve-ffmpeg-version.sh --url      # prints tarball URL
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "${ROOT}/versions.env"

SERIES="${FFMPEG_SERIES:-9}"
mode="${1:-}"

# 9.0, 9.0.1, 9.1, 9.1.1. One or two numeric components after the major.
mapfile -t versions < <(
  curl -fsSL https://ffmpeg.org/releases/ \
    | grep -oE "ffmpeg-${SERIES}\.[0-9]+(\.[0-9]+)?\.tar\.xz" \
    | sed -E 's/^ffmpeg-//; s/\.tar\.xz$//' \
    | sort -u \
    | sort -V
)

if [[ ${#versions[@]} -eq 0 ]]; then
  echo "No FFmpeg releases found for series ${SERIES}" >&2
  exit 1
fi

latest="${versions[-1]}"
url="https://ffmpeg.org/releases/ffmpeg-${latest}.tar.xz"

case "$mode" in
  --url) echo "$url" ;;
  --series) echo "$SERIES" ;;
  ""|--version) echo "$latest" ;;
  *)
    echo "Unknown option: $mode (use --version, --url, or --series)" >&2
    exit 1
    ;;
esac
