#!/usr/bin/env bash
# Print the tip commit of X264_REF (default master).
#
# Usage:
#   ./scripts/resolve-x264.sh            # full commit SHA
#   ./scripts/resolve-x264.sh --url      # archive URL
#   ./scripts/resolve-x264.sh --ref-name # ref name
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "${ROOT}/versions.env"

REF="${X264_REF:-master}"
mode="--commit"
REPO="https://code.videolan.org/videolan/x264.git"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      [[ $# -ge 2 ]] || { echo "--ref needs a branch name" >&2; exit 1; }
      REF="$2"
      shift 2
      ;;
    --ref=*)
      REF="${1#--ref=}"
      shift
      ;;
    --url|--commit|--version|--ref-name)
      mode="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1 (use --commit/--version, --url, --ref-name, or --ref NAME)" >&2
      exit 1
      ;;
  esac
done

commit="$(git ls-remote "$REPO" "refs/heads/${REF}" | awk '{print $1}')"
if [[ -z "$commit" || ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
  # Fall back to bare ref (some remotes advertise the branch tip without refs/heads/).
  commit="$(git ls-remote "$REPO" "$REF" | awk 'NF==2 && $2 !~ /\^/ {print $1; exit}')"
fi

if [[ -z "$commit" || ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
  echo "No tip commit found for x264 ref ${REF}" >&2
  exit 1
fi

url="https://code.videolan.org/videolan/x264/-/archive/${commit}/x264-${commit}.tar.gz"

case "$mode" in
  --url) echo "$url" ;;
  --ref-name) echo "$REF" ;;
  --commit|--version) echo "$commit" ;;
  *)
    echo "Unknown option: $mode" >&2
    exit 1
    ;;
esac
