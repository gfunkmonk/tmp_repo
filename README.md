# static-musl-builds

Build scripts that produce fully static, multi-architecture binaries using musl libc and Alpine Linux.

## Tools

| Tool | Version | Description |
|------|---------|-------------|
| 7zz | v1.5.7-R4 | CLI 7zip built from 7-Zip-zstd |
| aria2c | latest | Multi-protocol download utility |
| axel | latest | Parallel download accelerator |
| bash | 5.3 | Bash (Bourne Again SHell) |
| bsdtar | latest | Archive tool (libarchive) |
| curl | latest | Data transfer tool |
| dash | 0.5.13.1 | POSIX shell |
| htop | latest | Interactive process viewer |
| lftp | 4.9.3 | Command line ftp client |
| nano | 8.7.1 | Small command-line text editor |
| oksh | latest | OpenBSD ksh shell |
| openssh | 10.2p1 | OpenSSH ssh client |
| pigz | 2.8 | Parallel implementation of GZip |
| tar | 1.35 | GNU tar archive utility |
| upx | latest | UPX w/ custom patch & zstd support |
| vim | latest | Text editor |
| wget | 1.25.0 | File downloader |
| xz | latest | XZ/LZMA compression |

## Architectures

`x86_64` · `x86` · `aarch64` · `armv7`

## Usage

```bash
# Build for host architecture
./curl-static-musl.sh

# Build for a specific architecture
ARCH=aarch64 ./curl-static-musl.sh
```

Output binaries are written to `dist/` as `<tool>-<version>-<arch>.tar.xz`.

## Structure

```
.
├── common.sh               # Shared functions sourced by all build scripts
├── *-static-musl.sh        # Per-tool build scripts
├── patches/                # Patch files applied during builds
└── .github/workflows/
    └── build-all.yml       # CI: builds all tools × all architectures
```

## CI

The workflow in `.github/workflows/build-all.yml` builds all tools for all
architectures on a schedule (every 6 days) and publishes releases tagged with
the specific tool version (e.g., `bash-5.3`).
