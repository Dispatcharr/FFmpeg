#!/usr/bin/env bash
# Guard for the Intel Quick Sync userspace in the final image (amd64 only).
# Runs in the runtime stage after the Intel files are copied in and ldconfig has
# run, so it sees exactly what the dynamic loader and the libvpl dispatcher will.
#
# Usage: check-intel-media-runtime.sh [ffmpeg-binary]
# TRIPLET overrides the multiarch directory (default x86_64-linux-gnu).
set -euo pipefail

FFMPEG_BIN="${1:-/usr/local/bin/ffmpeg}"
TRIPLET="${TRIPLET:-x86_64-linux-gnu}"
LOCAL_LIBDIR="/usr/local/lib/${TRIPLET}"
SYSTEM_LIBDIR="/usr/lib/${TRIPLET}"

fail() {
  echo "check-intel-media-runtime: $*" >&2
  exit 1
}

# Print the path the loader resolves for a soname in ldd output ("" if absent).
resolved() {
  awk -v lib="$2" '$1 == lib { print $3; exit }' <<< "$1"
}

# Fail when ldd cannot resolve something.
require_complete() {
  local file="$1"
  local listing="$2"
  if grep -q 'not found' <<< "$listing"; then
    echo "$listing" >&2
    fail "unresolved libraries for $file"
  fi
}

# A library we build must resolve to our copy, not an Ubuntu one. Ubuntu's
# libva2 is pulled in by i965-va-driver (and by libavcodec in derived images), so
# both copies exist and only the loader search order keeps ours first.
# With require=1 the library must be linked; otherwise it is only checked if present.
require_local() {
  local file="$1"
  local listing="$2"
  local lib="$3"
  local require="${4:-1}"
  local path
  path="$(resolved "$listing" "$lib")"
  if [[ -z "$path" ]]; then
    [[ "$require" == "1" ]] && fail "$file does not link $lib"
    return 0
  fi
  case "$path" in
    "${LOCAL_LIBDIR}/"*) ;;
    *) fail "$file resolves $lib to $path, expected ${LOCAL_LIBDIR}/" ;;
  esac
}

[[ -x "$FFMPEG_BIN" ]] || fail "ffmpeg binary not found: $FFMPEG_BIN"

ffmpeg_ldd="$(ldd "$FFMPEG_BIN")"
require_complete "$FFMPEG_BIN" "$ffmpeg_ldd"
require_local "$FFMPEG_BIN" "$ffmpeg_ldd" libva.so.2
require_local "$FFMPEG_BIN" "$ffmpeg_ldd" libva-drm.so.2
require_local "$FFMPEG_BIN" "$ffmpeg_ldd" libvpl.so.2

# iHD is loaded by libva at runtime. Its own dependencies must resolve too.
ihd="${LOCAL_LIBDIR}/dri/iHD_drv_video.so"
[[ -f "$ihd" ]] || fail "missing $ihd"
ihd_ldd="$(ldd "$ihd")"
require_complete "$ihd" "$ihd_ldd"
require_local "$ihd" "$ihd_ldd" libigdgmm.so.12
require_local "$ihd" "$ihd_ldd" libva.so.2 0

# The libvpl dispatcher only searches LD_LIBRARY_PATH, the system library
# directories and ONEVPL_SEARCH_PATH, so libmfx-gen must be in /usr/lib/<triplet>.
# Under /usr/local it is never found and every QSV session fails. The enctools
# plugin is located relative to libmfx-gen, so it must sit beside it.
mfx="${SYSTEM_LIBDIR}/libmfx-gen.so.1.2"
[[ -e "$mfx" ]] || fail "missing $mfx (the libvpl dispatcher does not search /usr/local)"
[[ -f "${SYSTEM_LIBDIR}/libmfx-gen/enctools.so" ]] \
  || fail "missing ${SYSTEM_LIBDIR}/libmfx-gen/enctools.so"
for file in "$mfx" "${SYSTEM_LIBDIR}/libmfx-gen/enctools.so"; do
  file_ldd="$(ldd "$file")"
  require_complete "$file" "$file_ldd"
  require_local "$file" "$file_ldd" libva.so.2 0
  require_local "$file" "$file_ldd" libva-drm.so.2 0
done

# A distro package owning the file would be upgraded over our build later.
if command -v dpkg > /dev/null 2>&1 \
  && dpkg -S "$mfx" > /dev/null 2>&1; then
  fail "$mfx is owned by a distro package, expected our build"
fi

echo "Intel media runtime checks passed."
