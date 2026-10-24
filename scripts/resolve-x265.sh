#!/usr/bin/env bash
# Print the latest x265 release tag for major version X265_SERIES (default 4).
# Matches 4, 4.0, 4.2. Does not match 3.x or 5.x.
#
# Usage:
#   ./scripts/resolve-x265.sh                 # 4.2
#   ./scripts/resolve-x265.sh --url           # tarball URL
#   ./scripts/resolve-x265.sh --series 3
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "${ROOT}/versions.env"

SERIES="${X265_SERIES:-4}"
mode="--version"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --series)
      [[ $# -ge 2 ]] || { echo "--series needs a major version (e.g. 4)" >&2; exit 1; }
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
  echo "SERIES must be a major version integer (e.g. 4), got: ${SERIES}" >&2
  exit 1
fi

mapfile -t tags < <(
  SERIES="$SERIES" python3 - <<'PY'
import json, os, re, urllib.request

series = os.environ["SERIES"]
pat = re.compile(rf"^{re.escape(series)}(\.[0-9]+)*$")
names = []
url = (
    "https://api.bitbucket.org/2.0/repositories/multicoreware/x265_git/"
    "refs/tags?pagelen=50&sort=-target.date"
)
while url:
    with urllib.request.urlopen(url) as resp:
        data = json.load(resp)
    for row in data.get("values", []):
        name = row.get("name", "")
        if pat.match(name):
            names.append(name)
    url = data.get("next")
if names:
    print("\n".join(sorted(set(names), key=lambda v: [int(p) for p in v.split(".")])))
PY
)

# mapfile turns a lone newline into one empty element. That is not a tag.
if [[ ${#tags[@]} -eq 0 || -z "${tags[-1]}" ]]; then
  echo "No x265 tags found for series ${SERIES}" >&2
  exit 1
fi

latest="${tags[-1]}"
url="https://bitbucket.org/multicoreware/x265_git/get/${latest}.tar.gz"

case "$mode" in
  --url) echo "$url" ;;
  --version|--tag) echo "$latest" ;;
  *)
    echo "Unknown option: $mode" >&2
    exit 1
    ;;
esac
