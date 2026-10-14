# Dispatcharr FFmpeg

Redistributable FFmpeg image used by [Dispatcharr](https://github.com/Dispatcharr/Dispatcharr) containers.

| Knob | Value |
|------|--------|
| FFmpeg | 9.0.1 (pinned in `versions.env`) |
| License flags | `--enable-gpl --enable-version3` |
| TLS | GnuTLS (not OpenSSL) |
| AAC | native `aac` + `libfdk_aac` from **fdk-aac-stripped** |
| NVENC | `nv-codec-headers` **n13.0.19.0** (API 13.0; Pascal / driver 580 OK) |
| Quick Sync | `--enable-libvpl` on amd64 (oneVPL). The arm64 image has no `qsv`: Ubuntu 26 publishes `libvpl` and the Intel media driver for amd64 only, and arm64 has no Quick Sync engine. VAAPI stays on both architectures. The old `--enable-libmfx` flag is not used. |
| GPU userspace | amd64: Intel iHD + i965, plus AMD radeonsi/r600. arm64: AMD radeonsi/r600 only. NVIDIA's driver stays on the host. |
| Nonfree | **not enabled** |
| Base OS | Ubuntu 26.04 (`ubuntu:26.04` / resolute) |
| Linkage | libav, x264, x265, libvpx, dav1d, LAME, Opus, and fdk-aac-stripped are compiled into `ffmpeg`. GnuTLS, subtitles, SRT/RIST, libaom, SVT-AV1, VAAPI, Quick Sync, and NVENC stay dynamic. |

Published image: `ghcr.io/dispatcharr/ffmpeg`

## Build locally

```bash
docker build -t ghcr.io/dispatcharr/ffmpeg:local .
docker run --rm ghcr.io/dispatcharr/ffmpeg:local ffmpeg -hide_banner -version
```

## Image layout

- Base: Ubuntu 26.04
- `/usr/local/bin/ffmpeg`, `/usr/local/bin/ffprobe` (libav and the codecs we compile are inside the binary)
- AMD VA drivers (`radeonsi`, `r600`) on both architectures, under `/usr/lib/<triplet>/dri/`
- Intel Quick Sync userspace (`iHD`, `i965`, `libvpl`, `libmfx-gen`) on amd64 only
- Docs: `/usr/local/share/doc/dispatcharr-ffmpeg/` (`CONFIGURATION`, `VERSIONS`, `versions.env`, `SOURCE_REVISION`, license texts)

## CI

Workflows:

- `.github/workflows/build.yml` — manual only. Builds the amd64 + arm64 image and publishes it to GHCR. Pushes and pull requests do not run it.
- `.github/workflows/version-bump.yml`: daily, on push to `main`, and manual. Checks for a newer **FFmpeg 9 release** (`9.0.x` and `9.1.x`) and for a newer **nv-codec-headers** tag on the pinned NVENC API line (`13.0`, not `13.1`). Each pin has its own pull request (`chore/ffmpeg-bump` and `chore/nv-codec-headers-bump`). Merging one recreates the other from current `main` if that bump is still needed. Merging does not build the image.

Tags (after a build). These names point at that build:

- `<version>-nvenc130-<commit>` (e.g. `9.0.1-nvenc130-2b081ea69803`). This tag does not move. It is the same name as the git release, without the leading `v`, so this image and that release are the same build.
- `<version>-nvenc130` (e.g. `9.0.1-nvenc130`). This is the pin to use for the current build. The suffix is the NVENC API compiled into the binary (`nv-codec-headers` n13.0.19.0). API 13.0 still runs on Pascal and driver 580. A later 13.1 build of the same FFmpeg version is published as `<version>-nvenc131`, and the `nvenc130` tag stays on the 13.0 image. Rebuilding this FFmpeg version from a new commit moves this tag.
- `<version>` (e.g. `9.0.1`). Same image, without the API in the name. This tag moves if that FFmpeg version is rebuilt.
- `latest`, when the build workflow is run from `main` or `dev`. A build from another branch publishes the version tags and leaves `latest` where it is.

The build also creates git tag `v<version>-nvenc130-<commit>` (for example `v9.0.1-nvenc130-2b081ea69803`) and a GitHub Release. The commit is the first 12 characters of the git commit that built the image. That tag is the source for that build. GitHub attaches an archive of this repository. Upstream tarballs stay at the URLs in `versions.env`.

To publish an image, or to check for a new FFmpeg point release:

```bash
gh workflow run build.yml
gh workflow run version-bump.yml
```

## Smoke checks

`scripts/smoke-test.sh` asserts GPL/version3/GnuTLS/libzvbi/libfdk_aac/NVENC/VAAPI are enabled, that `nonfree` / `openssl` / `libmfx` are absent, that libav and the compiled-in codecs (x264, x265, libvpx, dav1d, LAME, Opus, fdk-aac-stripped) are not dynamically linked, that the license/docs under `/usr/local/share/doc/dispatcharr-ffmpeg/` are present, and on amd64 that Quick Sync (`libvpl`, `h264_qsv`) is present.

## Licensing

See [licenses/README.md](licenses/README.md). FDK support uses the Fedora/freedesktop **stripped** AAC-LC library (`fdk-aac-stripped`) with FFmpeg's configure adjusted so `libfdk_aac` is not treated as nonfree. Full Fraunhofer FDK and `--enable-nonfree` are not used.
