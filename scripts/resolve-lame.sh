#!/usr/bin/env bash
# Print the newest LAME orig tarball version from the Ubuntu pool.
#
# Stock sourceforge 3.100 fails on GCC 15. Ubuntu's orig tarballs (3.101 beta,
# then 4.0) are what we build. This script tracks that pool, not sourceforge.
#
# Usage:
#   ./scripts/resolve-lame.sh            # 4.0
#   ./scripts/resolve-lame.sh --url      # pool URL
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "${ROOT}/versions.env"

mode="${1:-}"
POOL_URL="https://archive.ubuntu.com/ubuntu/pool/main/l/lame/"

listing="$(curl -fsSL "$POOL_URL")"

mapfile -t archives < <(
  printf '%s\n' "$listing" \
    | grep -oE 'lame_[^"/]+\.orig\.tar\.(gz|xz|bz2)' \
    | sort -u
)

if [[ ${#archives[@]} -eq 0 ]]; then
  echo "No LAME orig tarballs found in the Ubuntu pool" >&2
  exit 1
fi

mapfile -t versions < <(
  printf '%s\n' "${archives[@]}" \
    | sed -E 's/^lame_//; s/\.orig\.tar\.(gz|xz|bz2)$//' \
    | sort -u \
    | sort -V
)

latest="${versions[-1]}"

archive=""
for candidate in gz xz bz2; do
  name="lame_${latest}.orig.tar.${candidate}"
  for a in "${archives[@]}"; do
    if [[ "$a" == "$name" ]]; then
      archive="$name"
      break 2
    fi
  done
done

if [[ -z "$archive" ]]; then
  echo "Could not determine archive name for LAME ${latest}" >&2
  exit 1
fi

url="${POOL_URL}${archive}"

case "$mode" in
  --url) echo "$url" ;;
  ""|--version) echo "$latest" ;;
  *)
    echo "Unknown option: $mode (use --version or --url)" >&2
    exit 1
    ;;
esac
