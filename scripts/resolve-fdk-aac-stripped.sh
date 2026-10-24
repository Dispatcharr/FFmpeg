#!/usr/bin/env bash
# Print the tip commit of FDK_AAC_STRIPPED_REF (default stripped5).
#
# Tags on this repo are mostly Android noise. Track the stripping branch tip.
#
# Usage:
#   ./scripts/resolve-fdk-aac-stripped.sh            # full commit SHA
#   ./scripts/resolve-fdk-aac-stripped.sh --url       # archive URL
#   ./scripts/resolve-fdk-aac-stripped.sh --ref-name  # branch name
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "${ROOT}/versions.env"

REF="${FDK_AAC_STRIPPED_REF:-stripped5}"
mode="--commit"
PROJECT="wtaymans%2Ffdk-aac-stripped"
API="https://gitlab.freedesktop.org/api/v4/projects/${PROJECT}"

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

commit="$(
  curl -fsSL "${API}/repository/commits?ref_name=${REF}&per_page=1" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["id"])'
)"

if [[ -z "$commit" || ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
  echo "No tip commit found for fdk-aac-stripped ref ${REF}" >&2
  exit 1
fi

url="https://gitlab.freedesktop.org/wtaymans/fdk-aac-stripped/-/archive/${commit}/fdk-aac-stripped-${commit}.tar.gz"

case "$mode" in
  --url) echo "$url" ;;
  --ref-name) echo "$REF" ;;
  --commit|--version) echo "$commit" ;;
  *)
    echo "Unknown option: $mode" >&2
    exit 1
    ;;
esac
