# Licenses for Dispatcharr FFmpeg

This image redistributes FFmpeg under **GPL version 3** (`--enable-gpl --enable-version3`).

## Included license texts

Copied into the image at `/usr/local/share/doc/dispatcharr-ffmpeg/`:

- `COPYING.GPLv3` / `COPYING.LGPLv3` from the FFmpeg release tarball
- `fdk-aac-stripped-NOTICE` from the fdk-aac-stripped tarball
- `CONFIGURATION`: exact `./configure` line used for the binary
- `VERSIONS`: FFmpeg version, nv-codec-headers tag, and fdk-aac-stripped commit used for this build
- `versions.env`: every pinned archive URL and package version
- `SOURCE_REVISION`: git commit of this repository that built the image. The matching tag is `v` plus `FFMPEG_VERSION` and `IMAGE_TAG_SUFFIX` from `versions.env` (for example `v9.0.1-nvenc130`)
- `UBUNTU-PACKAGES.txt`: Ubuntu package names and versions linked into the image
- `FDK-AAC-STRIPPED.txt`: note that AAC uses the stripped AAC-LC fork, not full Fraunhofer FDK

## Source offer

Corresponding source for this build is:

- This repository at the commit in `SOURCE_REVISION`, also published as the git tag named above (Dockerfile, `versions.env`, patches, and scripts)
- The upstream archives named in `versions.env` (FFmpeg, nv-codec-headers, fdk-aac-stripped, and the static codec libraries)
- The Ubuntu 26.04 source packages named in `UBUNTU-PACKAGES.txt` (same versions as the binary packages in the image; source is the Ubuntu archive for resolute)

Ubuntu packages are not vendored here; use the resolute source packages that match the versions in `UBUNTU-PACKAGES.txt`.

## What we intentionally omit

- `--enable-nonfree`
- OpenSSL (HTTPS uses GnuTLS)
- Full Fraunhofer FDK AAC (GPL-incompatible with this build)
- Intel's proprietary Media SDK (`--enable-libmfx`) and the multiverse `intel-media-va-driver-non-free` package. Quick Sync uses oneVPL (`libvpl`) plus the universe `intel-media-va-driver`.
- NVIDIA proprietary drivers. NVENC loads those from the host.

## Patents

Codec patents (for example H.264 / HEVC / AAC) are separate from copyright licensing. Redistributing this image does not grant patent licenses.
