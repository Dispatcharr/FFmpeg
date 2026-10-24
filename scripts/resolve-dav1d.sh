#!/usr/bin/env bash
# Print the latest dav1d release tag for major version DAV1D_SERIES (default 1).
#
# Usage:
#   ./scripts/resolve-dav1d.sh                 # 1.5.4
#   ./scripts/resolve-dav1d.sh --url           # tarball URL
#   ./scripts/resolve-dav1d.sh --series 1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "${ROOT}/versions.env"

SERIES="${DAV1D_SERIES:-1}"
mode="--version"
REPO="https://code.videolan.org/videolan/dav1d.git"

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

mapfile -t tags < <(
  git ls-remote --tags "$REPO" \
    | awk '{print $2}' \
    | sed -E 's|^refs/tags/||; s/\^\{\}$//' \
    | grep -E "^${SERIES}(\.[0-9]+)+$" \
    | sort -u \
    | sort -V
)

if [[ ${#tags[@]} -eq 0 ]]; then
  echo "No dav1d tags found for series ${SERIES}" >&2
  exit 1
fi

latest="${tags[-1]}"
url="https://code.videolan.org/videolan/dav1d/-/archive/${latest}/dav1d-${latest}.tar.gz"

case "$mode" in
  --url) echo "$url" ;;
  --version|--tag) echo "$latest" ;;
  *)
    echo "Unknown option: $mode" >&2
    exit 1
    ;;
esac
