# static-musl-builds

Build scripts that produce fully static, multi-architecture binaries using musl libc and Alpine Linux.

## Tools

| Tool | Version | Description |
|------|---------|-------------|
| aria2c | latest | Multi-protocol download utility |
| axel | 2.17.14 | Parallel download accelerator |
| bsdtar | 3.8.5 | Archive tool (libarchive) |
| curl | 8.18.0 | Data transfer tool |
| dash | 0.5.13.1 | POSIX shell |
| oksh | 7.8 | OpenBSD ksh shell |
| tar | 1.35 | GNU tar archive utility |
| vim | 9.2.0119 | Text editor |
| wget | 1.25.0 | File downloader |
| xz | 5.8.2 | XZ/LZMA compression |

## Architectures

`x86_64` · `x86` · `aarch64` · `armv7`

## Usage

```bash
# Build for host architecture
./curl-static-musl.sh

# Build for a specific architecture
ARCH=aarch64 ./curl-static-musl.sh
```

Output binaries are written to `dist/` as `<tool>-<arch>.tar.xz`.

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
architectures on a schedule (every 6 days) and publishes a
[continuous release](../../releases/tag/continuous-universal).

