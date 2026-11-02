#!/usr/bin/env bash
# Build the Intel free-kernel media stack into PREFIX (amd64 only).
# Pins come from intel-media.env (export before calling).
#
# Stack (keep these on the same Intel media release train):
#   libva, gmmlib, media-driver (ENABLE_NONFREE_KERNELS=OFF), libvpl, vpl-gpu-rt
#
# Ubuntu 26.04's intel-media-va-driver / libmfx-gen stay on 26.1.2, which breaks
# hevc_qsv on Arc (Invalid FrameType:0). Building the free-kernel driver from
# upstream restores a current iHD without the multiverse non-free package.
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
JOBS="${JOBS:-$(nproc)}"
TRIPLET="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)"
DRI_PATH="${LIBVA_DRIVERS_PATH_INSTALL:-${PREFIX}/lib/${TRIPLET}/dri}"

require_pin() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing pin: $name (source intel-media.env before calling)" >&2
    exit 1
  fi
}

require_pin LIBVA_VERSION
require_pin LIBVA_URL
require_pin INTEL_GMMLIB_VERSION
require_pin INTEL_GMMLIB_URL
require_pin INTEL_MEDIA_DRIVER_VERSION
require_pin INTEL_MEDIA_DRIVER_URL
require_pin LIBVPL_VERSION
require_pin LIBVPL_URL
require_pin VPL_GPU_RT_VERSION
require_pin VPL_GPU_RT_URL

export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/${TRIPLET}/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${PREFIX}/lib/${TRIPLET}:${LD_LIBRARY_PATH:-}"

# Upstream license and notice files are copied next to the other image docs
# before each source tree is deleted, so the binaries ship with their notices.
LICENSE_DIR="${PREFIX}/share/doc/dispatcharr-ffmpeg/intel-media-licenses"

fetch_tree() {
  local name="$1"
  local url="$2"
  local dest="$3"
  local file
  local found=0
  mkdir -p "$dest" "${LICENSE_DIR}/${name}"
  curl -fsSL "$url" | tar -xz --strip-components=1 -C "$dest"
  for file in "$dest"/LICENSE* "$dest"/COPYING* "$dest"/NOTICE* \
    "$dest"/third-party-programs.txt; do
    if [[ -f "$file" ]]; then
      cp "$file" "${LICENSE_DIR}/${name}/"
      found=1
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    echo "No license file found in the ${name} source tree" >&2
    exit 1
  fi
}

echo "**** libva ${LIBVA_VERSION} ****"
fetch_tree libva "$LIBVA_URL" /tmp/libva
(
  cd /tmp/libva
  ./autogen.sh
  ./configure \
    --prefix="$PREFIX" \
    --libdir="${PREFIX}/lib/${TRIPLET}" \
    --enable-drm \
    --disable-x11 \
    --disable-glx \
    --disable-wayland \
    --disable-static \
    --enable-shared
  make -j"$JOBS"
  make install
)
rm -rf /tmp/libva

echo "**** gmmlib ${INTEL_GMMLIB_VERSION} ****"
fetch_tree gmmlib "$INTEL_GMMLIB_URL" /tmp/gmmlib
cmake -S /tmp/gmmlib -B /tmp/gmmlib/build -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR="lib/${TRIPLET}"
cmake --build /tmp/gmmlib/build -j"$JOBS"
cmake --install /tmp/gmmlib/build
rm -rf /tmp/gmmlib

echo "**** media-driver ${INTEL_MEDIA_DRIVER_VERSION} (free-kernel) ****"
fetch_tree media-driver "$INTEL_MEDIA_DRIVER_URL" /tmp/media-driver
# GCC 15 treats some libstdc++ false positives as errors under -Werror=array-bounds.
cmake -S /tmp/media-driver -B /tmp/media-driver/build -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR="lib/${TRIPLET}" \
  -DCMAKE_CXX_FLAGS="-Wno-error=array-bounds" \
  -DENABLE_KERNELS=ON \
  -DENABLE_NONFREE_KERNELS=OFF \
  -DBUILD_CMRTLIB=ON \
  -DLIBVA_DRIVERS_PATH="$DRI_PATH"
cmake --build /tmp/media-driver/build -j"$JOBS"
cmake --install /tmp/media-driver/build
rm -rf /tmp/media-driver

echo "**** libvpl ${LIBVPL_VERSION} ****"
fetch_tree libvpl "$LIBVPL_URL" /tmp/libvpl
cmake -S /tmp/libvpl -B /tmp/libvpl/build -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR="lib/${TRIPLET}" \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_TESTS=OFF
cmake --build /tmp/libvpl/build -j"$JOBS"
cmake --install /tmp/libvpl/build
rm -rf /tmp/libvpl

echo "**** vpl-gpu-rt ${VPL_GPU_RT_VERSION} ****"
fetch_tree vpl-gpu-rt "$VPL_GPU_RT_URL" /tmp/vpl-gpu-rt
cmake -S /tmp/vpl-gpu-rt -B /tmp/vpl-gpu-rt/build -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR="lib/${TRIPLET}" \
  -DCMAKE_CXX_FLAGS="-Wno-error=array-bounds" \
  -DBUILD_TESTS=OFF
cmake --build /tmp/vpl-gpu-rt/build -j"$JOBS"
cmake --install /tmp/vpl-gpu-rt/build
rm -rf /tmp/vpl-gpu-rt

# Runtime-only tree for the final image (skip headers, static libs, pkgconfig).
# The tree is rooted at / so it can be copied straight over the final image:
#   usr/local/lib/<triplet>/      libva, libva-drm, libigdgmm, libvpl, libigfxcmrt,
#                                 dri/iHD_drv_video.so
#   usr/lib/<triplet>/            libmfx-gen and its libmfx-gen/ plugin directory
#
# libmfx-gen has to live in a system directory. The libvpl dispatcher only looks in
# LD_LIBRARY_PATH, /usr/lib/x86_64-linux-gnu, /lib, /usr/lib, /lib64, /usr/lib64 and
# ONEVPL_SEARCH_PATH (plus the install libdir if built with
# ENABLE_LIBDIR_IN_RUNTIME_SEARCH, and not at all in its low-latency mode). A copy
# under /usr/local is never found, and FFmpeg then cannot open a QSV session on
# any Intel GPU. enctools.so is located relative to libmfx-gen itself, so the
# libmfx-gen/ plugin directory moves with it.
RUNTIME_ROOT="${INTEL_MEDIA_RUNTIME_ROOT:-/opt/intel-media-runtime}"
LOCAL_LIBDIR="${RUNTIME_ROOT}/usr/local/lib/${TRIPLET}"
SYSTEM_LIBDIR="${RUNTIME_ROOT}/usr/lib/${TRIPLET}"
rm -rf "$RUNTIME_ROOT"
mkdir -p "${LOCAL_LIBDIR}/dri" "$SYSTEM_LIBDIR"

copy_globs() {
  local dest="$1"
  local pattern="$2"
  local -a matches=()
  if ! compgen -G "$pattern" > /dev/null; then
    echo "Failed to collect runtime libs matching: $pattern" >&2
    exit 1
  fi
  readarray -t matches < <(compgen -G "$pattern")
  cp -a "${matches[@]}" "$dest/"
}

copy_globs "$LOCAL_LIBDIR" "${PREFIX}/lib/${TRIPLET}/libva.so*"
copy_globs "$LOCAL_LIBDIR" "${PREFIX}/lib/${TRIPLET}/libva-drm.so*"
copy_globs "$LOCAL_LIBDIR" "${PREFIX}/lib/${TRIPLET}/libigdgmm.so*"
copy_globs "$LOCAL_LIBDIR" "${PREFIX}/lib/${TRIPLET}/libvpl.so*"
copy_globs "$LOCAL_LIBDIR" "${PREFIX}/lib/${TRIPLET}/libigfxcmrt.so*"
copy_globs "$SYSTEM_LIBDIR" "${PREFIX}/lib/${TRIPLET}/libmfx-gen.so*"

# vpl-gpu-rt ships helper plugins in libmfx-gen/ (for example enctools.so).
if [[ ! -f "${PREFIX}/lib/${TRIPLET}/libmfx-gen/enctools.so" ]]; then
  echo "vpl-gpu-rt did not install libmfx-gen/enctools.so under ${PREFIX}/lib/${TRIPLET}" >&2
  exit 1
fi
cp -a "${PREFIX}/lib/${TRIPLET}/libmfx-gen" "${SYSTEM_LIBDIR}/"

if [[ ! -f "${DRI_PATH}/iHD_drv_video.so" ]]; then
  echo "media-driver did not install iHD_drv_video.so under ${DRI_PATH}" >&2
  exit 1
fi
cp -a "${DRI_PATH}/iHD_drv_video.so" "${LOCAL_LIBDIR}/dri/"
find "${RUNTIME_ROOT}/usr" -type f \( -name '*.so' -o -name '*.so.*' \) \
  -exec strip --strip-unneeded {} +

ihd_size="$(wc -c < "${LOCAL_LIBDIR}/dri/iHD_drv_video.so")"
# Free-kernel builds are ~15-25MB. Full/non-free builds are ~40MB+.
if [[ "$ihd_size" -gt 35000000 ]]; then
  echo "iHD_drv_video.so is ${ihd_size} bytes; expected a free-kernel build under ~35MB" >&2
  exit 1
fi

mkdir -p "${PREFIX}/share/doc/dispatcharr-ffmpeg"
{
  echo "LIBVA_VERSION=${LIBVA_VERSION}"
  echo "INTEL_GMMLIB_VERSION=${INTEL_GMMLIB_VERSION}"
  echo "INTEL_MEDIA_DRIVER_VERSION=${INTEL_MEDIA_DRIVER_VERSION}"
  echo "INTEL_MEDIA_DRIVER_BUILD=free-kernel"
  echo "LIBVPL_VERSION=${LIBVPL_VERSION}"
  echo "VPL_GPU_RT_VERSION=${VPL_GPU_RT_VERSION}"
} > "${PREFIX}/share/doc/dispatcharr-ffmpeg/INTEL-MEDIA.txt"

echo "Intel free-kernel media stack installed to ${PREFIX}"
echo "Runtime bundle: ${RUNTIME_ROOT} (iHD ${ihd_size} bytes)"
