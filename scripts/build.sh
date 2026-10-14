#!/usr/bin/env bash
# Configure and build FFmpeg for Dispatcharr.
# Sourced versions come from versions.env (export before calling).
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
JOBS="${JOBS:-$(nproc)}"

if [[ -z "${FFMPEG_SRC:-}" ]]; then
  echo "FFMPEG_SRC must point at the FFmpeg source tree" >&2
  exit 1
fi

cd "$FFMPEG_SRC"
chmod +x configure

# Record the exact configure line for license compliance / image docs.
CONFIGURE_ARGS=(
  --prefix="$PREFIX"
  --extra-version=Dispatcharr
  --disable-debug
  --disable-doc
  --disable-ffplay
  --disable-shared
  --enable-static
  --enable-gpl
  --enable-version3
  --enable-gnutls
  --enable-gmp
  --enable-libxml2
  --enable-libmp3lame
  --enable-libopus
  --enable-libvorbis
  --enable-libfdk-aac
  --enable-libx264
  --enable-libx265
  --enable-libvpx
  --enable-libdav1d
  --enable-libaom
  --enable-libsvtav1
  --enable-libass
  --enable-libfreetype
  --enable-libfribidi
  --enable-libfontconfig
  --enable-libharfbuzz
  --enable-libzvbi
  --enable-libsoxr
  --enable-libwebp
  --enable-libzimg
  --enable-libbluray
  --enable-libsrt
  --enable-librist
  --enable-libdrm
  --enable-vaapi
  --enable-opencl
  --enable-ffnvcodec
  --enable-nvenc
  --enable-nvdec
  --enable-cuvid
)

# CUDA kernel compilation (clang) is only wired for x86_64.
# NVENC/NVDEC stay enabled on every arch: they are a runtime driver API,
# and the NVIDIA driver itself comes from the host.
# libvpl (Intel Quick Sync) is amd64-only: Ubuntu 26.04 does not ship it for arm64.
arch="${TARGETARCH:-}"
if [[ -z "$arch" ]]; then
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
  esac
fi
if [[ "$arch" == "amd64" ]]; then
  CONFIGURE_ARGS+=(--enable-cuda-llvm --enable-libvpl)
fi

# Persist configure line next to the install prefix for the runtime image.
mkdir -p "${PREFIX}/share/doc/dispatcharr-ffmpeg"
{
  echo "# Dispatcharr FFmpeg configure"
  echo "# FFMPEG_VERSION=${FFMPEG_VERSION:-unknown}"
  echo "# NV_CODEC_HEADERS_TAG=${NV_CODEC_HEADERS_TAG:-unknown}"
  echo "# FDK_AAC_STRIPPED_COMMIT=${FDK_AAC_STRIPPED_COMMIT:-unknown}"
  echo
  printf './configure'
  printf ' %q' "${CONFIGURE_ARGS[@]}"
  echo
} > "${PREFIX}/share/doc/dispatcharr-ffmpeg/CONFIGURATION"

./configure "${CONFIGURE_ARGS[@]}"
make -j"$JOBS"
make install
