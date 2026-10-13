# Licenses for Dispatcharr FFmpeg

This image redistributes FFmpeg under **GPL version 3** (`--enable-gpl --enable-version3`).

## Included license texts

Copied into the image at `/usr/local/share/doc/dispatcharr-ffmpeg/`:

- `COPYING.GPLv3` / `COPYING.LGPLv3` from the FFmpeg release tarball
- `fdk-aac-stripped-NOTICE` from the fdk-aac-stripped tarball, when that archive ships one
- `CONFIGURATION`: exact `./configure` line used for the binary
- `VERSIONS`: pinned FFmpeg, nv-codec-headers, and fdk-aac-stripped tags
- `UBUNTU-PACKAGES.txt`: Ubuntu package names and versions linked into the image
- `FDK-AAC-STRIPPED.txt`: note that AAC uses the stripped AAC-LC fork, not full Fraunhofer FDK

## Source offer

Corresponding source for this build is:

- This repository (Dockerfile, `versions.env`, patches, and scripts)
- The upstream archives named in `versions.env` and recorded in `VERSIONS` (FFmpeg, nv-codec-headers, fdk-aac-stripped, and the static codec libraries)
- The Ubuntu 26.04 source packages named in `UBUNTU-PACKAGES.txt` (same versions as the binary packages in the image; source is the Ubuntu archive for resolute)

That is the usual approach for a distro-based image: pin the exact upstream tarballs you compile, and point at the distro source archive for libraries you install with apt instead of vendoring their tarballs.

## What we intentionally omit

- `--enable-nonfree`
- OpenSSL (HTTPS uses GnuTLS)
- Full Fraunhofer FDK AAC (GPL-incompatible with this build)
- Intel's proprietary Media SDK (`--enable-libmfx`) and the multiverse `intel-media-va-driver-non-free` package. Quick Sync uses oneVPL (`libvpl`) plus the universe `intel-media-va-driver`.
- NVIDIA proprietary drivers. NVENC loads those from the host.

## Patents

Codec patents (for example H.264 / HEVC / AAC) are separate from copyright licensing. Redistributing this image does not grant patent licenses.
