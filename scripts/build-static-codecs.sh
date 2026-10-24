#!/usr/bin/env bash
# Build codec libraries as static archives under $PREFIX.
# FFmpeg links these in. Driver libraries (VAAPI, NVENC) are not built here.
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
JOBS="${JOBS:-$(nproc)}"

fetch() {
  local url="$1" dest="$2"
  mkdir -p "$dest"
  curl -fsSL "$url" | tar -xz --strip-components=1 -C "$dest"
}

echo "=== x264 ${X264_COMMIT} ==="
fetch "$X264_URL" /tmp/x264
cd /tmp/x264
./configure --prefix="$PREFIX" --enable-static --disable-cli
make -j"$JOBS"
make install
cd /
rm -rf /tmp/x264

echo "=== x265 ${X265_VERSION} ==="
fetch "$X265_URL" /tmp/x265
# Older trees (3.6) set CMP0025/CMP0054 to OLD; CMake 4 rejects that. 4.x is
# cleaner but still declares a low cmake_minimum_required, so keep the floor.
sed -i \
  -e '/cmake_policy(SET CMP0025 OLD)/d' \
  -e '/cmake_policy(SET CMP0054 OLD)/d' \
  /tmp/x265/source/CMakeLists.txt
cmake -S /tmp/x265/source -B /tmp/x265/build -G Ninja \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SHARED=OFF \
  -DENABLE_CLI=OFF \
  -DENABLE_PIC=ON \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
ninja -C /tmp/x265/build
ninja -C /tmp/x265/build install
cd /
rm -rf /tmp/x265
# x265.pc is produced by x265's CMake only after git reads x265Version.txt.
if [[ ! -f "$PREFIX/lib/pkgconfig/x265.pc" ]]; then
  echo "x265 did not install x265.pc (git must be available at configure time)" >&2
  exit 1
fi

echo "=== lame ${LAME_VERSION} ==="
fetch "$LAME_URL" /tmp/lame
cd /tmp/lame
# LAME's --enable-nasm selects i386 assembly, so it is only passed on x86.
lame_nasm=()
if [[ "$(uname -m)" == "x86_64" || "$(uname -m)" == "i386" ]]; then
  lame_nasm=(--enable-nasm)
fi
./configure --prefix="$PREFIX" --enable-static --disable-shared \
  --disable-frontend --disable-decoder "${lame_nasm[@]}"
make -j"$JOBS"
make install
cd /
rm -rf /tmp/lame

echo "=== opus ${OPUS_VERSION} ==="
fetch "$OPUS_URL" /tmp/opus
cd /tmp/opus
./configure --prefix="$PREFIX" --enable-static --disable-shared --disable-doc --disable-extra-programs
make -j"$JOBS"
make install
cd /
rm -rf /tmp/opus

echo "=== dav1d ${DAV1D_VERSION} ==="
fetch "$DAV1D_URL" /tmp/dav1d
meson setup /tmp/dav1d/build /tmp/dav1d \
  --prefix="$PREFIX" \
  --libdir=lib \
  --buildtype=release \
  --default-library=static \
  -Denable_tools=false \
  -Denable_tests=false
ninja -C /tmp/dav1d/build
ninja -C /tmp/dav1d/build install
cd /
rm -rf /tmp/dav1d

echo "=== libvpx ${LIBVPX_VERSION} ==="
fetch "$LIBVPX_URL" /tmp/libvpx
cd /tmp/libvpx
vpx_as=()
if [[ "$(uname -m)" == "x86_64" ]]; then
  vpx_as=(--as=nasm)
fi
./configure --prefix="$PREFIX" --enable-static --disable-shared --enable-pic \
  --disable-examples --disable-tools --disable-unit-tests --disable-docs "${vpx_as[@]}"
make -j"$JOBS"
make install
cd /
rm -rf /tmp/libvpx

# FFmpeg calls pkg-config without --static. Static archives still need the
# private libs (libstdc++, libm, pthread) on the Libs line or the link fails.
python3 - <<'PY'
import pathlib, os
lib = pathlib.Path(os.environ["PREFIX"]) / "lib" / "pkgconfig"
for pc in lib.glob("*.pc"):
    text = pc.read_text()
    libs = priv = None
    lines = text.splitlines()
    for line in lines:
        if line.startswith("Libs:"):
            libs = line
        elif line.startswith("Libs.private:"):
            priv = line.split(":", 1)[1].strip()
    if not libs or not priv:
        continue
    have = set(libs.split())
    extra = [tok for tok in priv.split() if tok not in have]
    if not extra:
        continue
    new_libs = libs + " " + " ".join(extra)
    pc.write_text("\n".join(new_libs if line == libs else line for line in lines) + "\n")
    print(f"merged Libs.private into {pc.name}")
PY

test -f "$PREFIX/lib/libx264.a"
test -f "$PREFIX/lib/libx265.a"
test -f "$PREFIX/lib/libmp3lame.a"
test -f "$PREFIX/lib/libopus.a"
test -f "$PREFIX/lib/libdav1d.a"
test -f "$PREFIX/lib/libvpx.a"
test ! -e "$PREFIX/lib/libx264.so"
echo "Static codecs installed."
