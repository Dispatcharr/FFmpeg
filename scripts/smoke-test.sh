#!/usr/bin/env bash
# Assert redistributable IPTV-oriented FFmpeg features (no GPU required).
set -euo pipefail

FFMPEG_BIN="${1:-ffmpeg}"

if ! command -v "$FFMPEG_BIN" >/dev/null 2>&1 && [[ ! -x "$FFMPEG_BIN" ]]; then
  echo "ffmpeg not found: $FFMPEG_BIN" >&2
  exit 1
fi

version_out="$("$FFMPEG_BIN" -hide_banner -version 2>&1)"
echo "$version_out" | head -n 20

config_line="$(echo "$version_out" | awk '/^configuration:/{print; exit}')"
if [[ -z "$config_line" ]]; then
  echo "Could not read configuration line from ffmpeg -version" >&2
  exit 1
fi

require_config() {
  local needle="$1"
  if ! echo "$config_line" | grep -q -- "$needle"; then
    echo "Missing configure flag: $needle" >&2
    echo "$config_line" >&2
    exit 1
  fi
}

forbid_config() {
  local needle="$1"
  if echo "$config_line" | grep -q -- "$needle"; then
    echo "Forbidden configure flag present: $needle" >&2
    echo "$config_line" >&2
    exit 1
  fi
}

require_config '--enable-gpl'
require_config '--enable-version3'
require_config '--enable-gnutls'
require_config '--enable-libzvbi'
require_config '--enable-libfdk-aac'
require_config '--enable-libx264'
require_config '--enable-libx265'
require_config '--enable-libsrt'
require_config '--enable-librist'
require_config '--enable-nvenc'
require_config '--enable-vaapi'

forbid_config '--enable-nonfree'
forbid_config '--enable-openssl'
forbid_config '--enable-libnpp'
forbid_config '--enable-libmfx'

encoders="$("$FFMPEG_BIN" -hide_banner -encoders 2>&1)"
decoders="$("$FFMPEG_BIN" -hide_banner -decoders 2>&1)"

require_encoder() {
  local name="$1"
  if ! echo "$encoders" | grep -Eq "[[:space:]]${name}[[:space:]]"; then
    echo "Missing encoder: $name" >&2
    exit 1
  fi
}

require_decoder() {
  local name="$1"
  if ! echo "$decoders" | grep -Eq "[[:space:]]${name}[[:space:]]"; then
    echo "Missing decoder: $name" >&2
    exit 1
  fi
}

require_encoder 'libx264'
require_encoder 'aac'
require_encoder 'libfdk_aac'
require_encoder 'h264_nvenc'
require_decoder 'libzvbi_teletextdec'

# libav and the codecs we compile must be inside the binary.
# VAAPI (libva) and TLS (GnuTLS) stay shared. NVENC loads the host driver later.
linked="$(ldd "$FFMPEG_BIN" 2>/dev/null || true)"
if echo "$linked" | grep -Eq 'libavcodec|libavformat|libx264|libx265|libfdk-aac|libmp3lame\.so|libopus\.so|libdav1d|libvpx\.so'; then
  echo "A library that should be static is still dynamically linked:" >&2
  echo "$linked" >&2
  exit 1
fi
if ! echo "$linked" | grep -q 'libgnutls'; then
  echo "Expected dynamic libgnutls" >&2
  echo "$linked" >&2
  exit 1
fi
if ! echo "$linked" | grep -q 'libva\.so'; then
  echo "Expected dynamic libva (VAAPI driver loader)" >&2
  echo "$linked" >&2
  exit 1
fi

# Intel Quick Sync via oneVPL. Ubuntu ships libvpl only on amd64.
# The old Media SDK (--enable-libmfx) stays off.
arch="${TARGETARCH:-}"
if [[ -z "$arch" ]]; then
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
  esac
fi
if [[ "$arch" == "amd64" ]]; then
  require_config '--enable-libvpl'
  require_encoder 'h264_qsv'
  require_encoder 'hevc_qsv'
  require_encoder 'av1_qsv'
  hwaccels="$("$FFMPEG_BIN" -hide_banner -hwaccels 2>&1)"
  if ! echo "$hwaccels" | grep -Eq '(^|[[:space:]])qsv([[:space:]]|$)'; then
    echo "Missing hwaccel: qsv" >&2
    echo "$hwaccels" >&2
    exit 1
  fi
  if ! echo "$linked" | grep -q 'libvpl\.so'; then
    echo "Expected dynamic libvpl (Quick Sync dispatcher)" >&2
    echo "$linked" >&2
    exit 1
  fi
fi

# The image does not include NVIDIA drivers. NVENC loads libnvidia-encode from
# the host at runtime (NVIDIA container toolkit). What we pin is the API
# compiled into ffmpeg, from the nv-codec-headers installed under $PREFIX.
nvenc_header="${PREFIX:-/usr/local}/include/ffnvcodec/nvEncodeAPI.h"
if [[ ! -f "$nvenc_header" ]]; then
  echo "Missing NVENC headers: $nvenc_header" >&2
  exit 1
fi
nvenc_major="$(sed -n 's/^#define NVENCAPI_MAJOR_VERSION \([0-9]*\).*/\1/p' "$nvenc_header")"
nvenc_minor="$(sed -n 's/^#define NVENCAPI_MINOR_VERSION \([0-9]*\).*/\1/p' "$nvenc_header")"
echo "Compiled NVENC API: ${nvenc_major}.${nvenc_minor}"
if [[ "$nvenc_major" != "13" || "$nvenc_minor" != "0" ]]; then
  echo "Expected NVENC API 13.0, got ${nvenc_major}.${nvenc_minor}" >&2
  exit 1
fi

# License and build docs that the builder stage copies next to the binary.
doc_dir="${PREFIX:-/usr/local}/share/doc/dispatcharr-ffmpeg"
require_doc() {
  local name="$1"
  if [[ ! -f "${doc_dir}/${name}" ]]; then
    echo "Missing license/doc file: ${doc_dir}/${name}" >&2
    exit 1
  fi
}
require_doc 'CONFIGURATION'
require_doc 'VERSIONS'
require_doc 'COPYING.GPLv3'
require_doc 'COPYING.LGPLv3'
require_doc 'README.md'
require_doc 'FDK-AAC-STRIPPED.txt'
require_doc 'fdk-aac-stripped-NOTICE'
require_doc 'versions.env'
require_doc 'SOURCE_REVISION'

if ! grep -q '^FFMPEG_VERSION=' "${doc_dir}/versions.env"; then
  echo "versions.env is missing FFMPEG_VERSION" >&2
  exit 1
fi
if ! grep -q '^X264_COMMIT=' "${doc_dir}/versions.env"; then
  echo "versions.env is missing the static codec pins" >&2
  exit 1
fi
revision="$(tr -d '[:space:]' < "${doc_dir}/SOURCE_REVISION")"
if [[ ! "$revision" =~ ^(unknown|[0-9a-f]{40})$ ]]; then
  echo "SOURCE_REVISION must be a git commit or unknown, got: ${revision}" >&2
  exit 1
fi

echo "Smoke tests passed."
