# syntax=docker/dockerfile:1.7
# Redistributable FFmpeg for Dispatcharr:
#   GPL v3 + version3, GnuTLS, fdk-aac-stripped, NVENC API 13.0, no nonfree.
# Keep UBUNTU_BASE in sync with versions.env (Ubuntu 26.04 / resolute).
ARG UBUNTU_BASE=ubuntu:26.04

# =============================================================================
# builder
# =============================================================================
FROM ${UBUNTU_BASE} AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV PREFIX=/usr/local
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
ARG TARGETARCH

COPY versions.env /tmp/versions.env
# shellcheck disable=SC1091
RUN set -eux; . /tmp/versions.env; \
    echo "FFMPEG_VERSION=$FFMPEG_VERSION" > /tmp/build-versions; \
    echo "NV_CODEC_HEADERS_TAG=$NV_CODEC_HEADERS_TAG" >> /tmp/build-versions; \
    echo "FDK_AAC_STRIPPED_COMMIT=$FDK_AAC_STRIPPED_COMMIT" >> /tmp/build-versions

RUN set -eux; \
    apt-get update; \
    apt-get install --no-install-recommends -y \
    ca-certificates curl xz-utils \
    build-essential pkg-config nasm clang cmake ninja-build meson git \
    autoconf automake libtool \
    libgnutls28-dev libgmp-dev \
    libxml2-dev \
    libvorbis-dev \
    libaom-dev libsvtav1enc-dev \
    libass-dev libfreetype-dev libfribidi-dev libfontconfig-dev libharfbuzz-dev \
    libzvbi-dev \
    libsoxr-dev libwebp-dev libzimg-dev libbluray-dev \
    libsrt-gnutls-dev librist-dev \
    libdrm-dev libva-dev \
    ocl-icd-opencl-dev; \
    arch="${TARGETARCH:-}"; \
    if [ -z "$arch" ]; then \
      case "$(uname -m)" in \
        x86_64) arch=amd64 ;; \
        aarch64|arm64) arch=arm64 ;; \
      esac; \
    fi; \
    if [ "$arch" = "amd64" ]; then \
      apt-get install --no-install-recommends -y libvpl-dev; \
    fi; \
    rm -rf /var/lib/apt/lists/*

# --- nv-codec-headers (pinned 13.0 for Pascal / driver 580) ---
RUN set -eux; . /tmp/versions.env; \
    mkdir -p /tmp/nv-codec-headers; \
    curl -fsSL "$NV_CODEC_HEADERS_URL" \
      | tar -xz --strip-components=1 -C /tmp/nv-codec-headers; \
    make -C /tmp/nv-codec-headers PREFIX="$PREFIX" install; \
    pkg-config --modversion ffnvcodec; \
    rm -rf /tmp/nv-codec-headers

# --- fdk-aac-stripped (AAC-LC only; not full Fraunhofer FDK) ---
RUN set -eux; . /tmp/versions.env; \
    mkdir -p /tmp/fdk-aac-stripped; \
    curl -fsSL "$FDK_AAC_STRIPPED_URL" \
      | tar -xz --strip-components=1 -C /tmp/fdk-aac-stripped; \
    cd /tmp/fdk-aac-stripped; \
    ./autogen.sh; \
    ./configure --prefix="$PREFIX" --enable-static --disable-shared \
      CFLAGS="-O3 -DNDEBUG -fPIC" CXXFLAGS="-O3 -DNDEBUG -fPIC"; \
    make -j"$(nproc)"; \
    make install; \
    mkdir -p /usr/local/share/doc/dispatcharr-ffmpeg; \
    cp NOTICE /usr/local/share/doc/dispatcharr-ffmpeg/fdk-aac-stripped-NOTICE; \
    rm -rf /tmp/fdk-aac-stripped

COPY patches/remove-fdk-aac-from-nonfree.sh /tmp/remove-fdk-aac-from-nonfree.sh
COPY scripts/build-static-codecs.sh /tmp/build-static-codecs.sh
COPY scripts/build.sh /tmp/build.sh
COPY licenses/README.md /tmp/licenses-README.md
RUN chmod +x /tmp/remove-fdk-aac-from-nonfree.sh /tmp/build-static-codecs.sh /tmp/build.sh

# x264, x265, lame, opus, dav1d, libvpx. Built before FFmpeg so only .a exists.
RUN set -eux; set -a; . /tmp/versions.env; set +a; /tmp/build-static-codecs.sh

# --- FFmpeg ---
# set -a exports versions.env into build.sh (CONFIGURATION records those pins).
# TARGETARCH is set by BuildKit (amd64 / arm64). cuda-llvm and libvpl are amd64-only.
RUN set -eux; set -a; . /tmp/versions.env; set +a; \
    mkdir -p /tmp/ffmpeg; \
    curl -fsSL "$FFMPEG_URL" | tar -xJ --strip-components=1 -C /tmp/ffmpeg; \
    /tmp/remove-fdk-aac-from-nonfree.sh /tmp/ffmpeg/configure; \
    export FFMPEG_SRC=/tmp/ffmpeg TARGETARCH="${TARGETARCH:-}"; \
    /tmp/build.sh; \
    cp /tmp/ffmpeg/COPYING.GPLv3 /usr/local/share/doc/dispatcharr-ffmpeg/; \
    cp /tmp/ffmpeg/COPYING.LGPLv3 /usr/local/share/doc/dispatcharr-ffmpeg/; \
    cp /tmp/licenses-README.md /usr/local/share/doc/dispatcharr-ffmpeg/README.md; \
    cp /tmp/build-versions /usr/local/share/doc/dispatcharr-ffmpeg/VERSIONS; \
    echo "This build links fdk-aac-stripped (${FDK_AAC_STRIPPED_COMMIT}), not full Fraunhofer FDK." \
      > /usr/local/share/doc/dispatcharr-ffmpeg/FDK-AAC-STRIPPED.txt; \
    rm -rf /tmp/ffmpeg

# Source offer for this binary: full pin list, plus the git commit that built it.
# Local builds that do not pass SOURCE_REVISION record "unknown".
ARG SOURCE_REVISION=unknown
RUN set -eux; \
    cp /tmp/versions.env /usr/local/share/doc/dispatcharr-ffmpeg/versions.env; \
    printf '%s\n' "$SOURCE_REVISION" > /usr/local/share/doc/dispatcharr-ffmpeg/SOURCE_REVISION

COPY scripts/smoke-test.sh /tmp/smoke-test.sh
RUN chmod +x /tmp/smoke-test.sh && /tmp/smoke-test.sh /usr/local/bin/ffmpeg

# =============================================================================
# runtime: Ubuntu 26.04 + ffmpeg/ffprobe + runtime libs + license docs
# =============================================================================
FROM ${UBUNTU_BASE} AS final

ENV DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH

# Package SONAMEs are for Ubuntu 26.04 (resolute). Re-check when bumping the base.
# mesa-libgallium ships the AMD VA drivers (radeonsi, r600). Ubuntu 26 has no mesa-va-drivers package.
# Intel Quick Sync and iHD/i965 are amd64-only in this archive. NVIDIA drivers stay on the host.
RUN set -eux; \
    apt-get update && apt-get install --no-install-recommends -y \
    ca-certificates \
    libgnutls30t64 libgmp10 \
    libxml2-16 \
    libvorbis0a libvorbisenc2 \
    libaom3 libsvtav1enc2 \
    libass9 libfreetype6 libfribidi0 libfontconfig1 libharfbuzz0b \
    libzvbi0t64 \
    libsoxr0 libwebp7 libwebpmux3 libzimg2 libbluray3 \
    libsrt1.5-gnutls librist4 \
    libdrm2 libva2 libva-drm2 \
    ocl-icd-libopencl1 \
    mesa-libgallium \
    ; \
    arch="${TARGETARCH:-}"; \
    if [ -z "$arch" ]; then \
      case "$(uname -m)" in \
        x86_64) arch=amd64 ;; \
        aarch64|arm64) arch=arm64 ;; \
      esac; \
    fi; \
    if [ "$arch" = "amd64" ]; then \
      apt-get install --no-install-recommends -y \
        libvpl2 \
        libmfx-gen1.2 \
        intel-media-va-driver \
        i965-va-driver; \
    fi; \
    rm -rf /var/lib/apt/lists/*; \
    if [ "$arch" = "amd64" ]; then triplet=x86_64-linux-gnu; else triplet=aarch64-linux-gnu; fi; \
    test -f "/usr/lib/${triplet}/dri/radeonsi_drv_video.so"; \
    test -f "/usr/lib/${triplet}/dri/r600_drv_video.so"; \
    if [ "$arch" = "amd64" ]; then \
      test -f "/usr/lib/${triplet}/dri/iHD_drv_video.so"; \
      test -f "/usr/lib/${triplet}/dri/i965_drv_video.so"; \
      test -e "/usr/lib/${triplet}/libvpl.so.2"; \
      test -e "/usr/lib/${triplet}/libmfx-gen.so.1.2"; \
    fi

# Runtime needs the binaries and license docs only. Static .a / headers / .pc stay in builder.
COPY --from=builder /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=builder /usr/local/bin/ffprobe /usr/local/bin/ffprobe
COPY --from=builder /usr/local/share/doc/dispatcharr-ffmpeg /usr/local/share/doc/dispatcharr-ffmpeg

RUN set -eux; \
    arch="${TARGETARCH:-}"; \
    if [ -z "$arch" ]; then \
      case "$(uname -m)" in \
        x86_64) arch=amd64 ;; \
        aarch64|arm64) arch=arm64 ;; \
      esac; \
    fi; \
    pkgs="libgnutls30t64 libgmp10 libxml2-16 \
        libvorbis0a libvorbisenc2 \
        libaom3 libsvtav1enc2 \
        libass9 libfreetype6 libfribidi0 libfontconfig1 libharfbuzz0b \
        libzvbi0t64 \
        libsoxr0 libwebp7 libwebpmux3 libzimg2 libbluray3 \
        libsrt1.5-gnutls librist4 \
        libdrm2 libva2 libva-drm2 \
        ocl-icd-libopencl1 \
        mesa-libgallium"; \
    if [ "$arch" = "amd64" ]; then \
      pkgs="$pkgs libvpl2 libmfx-gen1.2 intel-media-va-driver i965-va-driver"; \
    fi; \
    dpkg-query -W -f '${Package} ${Version}\n' $pkgs \
        > /usr/local/share/doc/dispatcharr-ffmpeg/UBUNTU-PACKAGES.txt; \
    ffmpeg -hide_banner -version | head -n 5

# Keep PATH obvious for derived images (DispatcharrBase).
ENV PATH="/usr/local/bin:${PATH}"

LABEL org.opencontainers.image.title="ffmpeg" \
      org.opencontainers.image.description="Redistributable FFmpeg image for Dispatcharr. GPL v3, GnuTLS, NVENC API 13.0, no nonfree." \
      org.opencontainers.image.source="https://github.com/Dispatcharr/FFmpeg" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"
