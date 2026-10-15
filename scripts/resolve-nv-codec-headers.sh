#!/usr/bin/env bash
# Print the latest FFmpeg/nv-codec-headers tag for an NVENC API series.
#
# Tag shape is nMAJOR.MINOR.SDK.PATCH (e.g. n13.0.19.1, n12.2.72.0).
# SERIES is MAJOR.MINOR of the NVENC API line, not the SDK patch:
#   13.0 -> n13.0.* only (not n13.1.*)
#   12.2 -> n12.2.* only
#
# Default SERIES comes from NV_CODEC_HEADERS_SERIES in versions.env.
# Override with --series for a one-off lookup (e.g. before switching the pin).
#
# Usage:
#   ./scripts/resolve-nv-codec-headers.sh                 # n13.0.19.1
#   ./scripts/resolve-nv-codec-headers.sh --url            # tarball URL
#   ./scripts/resolve-nv-codec-headers.sh --api            # 13.0
#   ./scripts/resolve-nv-codec-headers.sh --series 12.2
#   ./scripts/resolve-nv-codec-headers.sh --series 12.2 --url
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "${ROOT}/versions.env"

SERIES="${NV_CODEC_HEADERS_SERIES:-13.0}"
mode="--tag"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --series)
      [[ $# -ge 2 ]] || { echo "--series needs MAJOR.MINOR (e.g. 13.0)" >&2; exit 1; }
      SERIES="$2"
      shift 2
      ;;
    --series=*)
      SERIES="${1#--series=}"
      shift
      ;;
    --url|--tag|--version|--api)
      mode="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1 (use --version/--tag, --url, --api, or --series MAJOR.MINOR)" >&2
      exit 1
      ;;
  esac
done

if [[ ! "$SERIES" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "SERIES must be MAJOR.MINOR (e.g. 13.0 or 12.2), got: ${SERIES}" >&2
  exit 1
fi

# Escape dots for grep. Match only this API line: n13.0.19.1, not n13.1.15.0.
series_re="n${SERIES//./\\.}\\.[0-9]+\\.[0-9]+"

mapfile -t tags < <(
  git ls-remote --tags https://github.com/FFmpeg/nv-codec-headers.git \
    | awk '{print $2}' \
    | sed -E 's|^refs/tags/||; s/\^\{\}$//' \
    | grep -E "^${series_re}$" \
    | sort -u \
    | sort -V
)

if [[ ${#tags[@]} -eq 0 ]]; then
  echo "No nv-codec-headers tags found for series ${SERIES}" >&2
  exit 1
fi

latest="${tags[-1]}"
url="https://github.com/FFmpeg/nv-codec-headers/archive/refs/tags/${latest}.tar.gz"

case "$mode" in
  --url) echo "$url" ;;
  --api) echo "$SERIES" ;;
  --version|--tag) echo "$latest" ;;
  *)
    echo "Unknown option: $mode" >&2
    exit 1
    ;;
esac
