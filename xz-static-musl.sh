#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

echo -e "${VIOLET}= fetching latest vim version${NC}"
XZ_VERSION=$(curl -fsSL "https://api.github.com/repos/tukaani-project/xz/releases/latest"  \
  | grep '"tag_name"' | sed 's/.*"release-\([^"]*\)".*/\1/' \
  | sed 's/",//g' | sed 's/  "tag_name": "v//g') || true
if [ -z "${XZ_VERSION}" ]; then
  echo -e "${TAWNY}= GitHub API unavailable, falling back to xz 5.8.2${NC}"
  XZ_VERSION="5.8.2"
fi

PACKAGE_VERSION="${XZ_VERSION}"
XZ_TARBALL="xz-${XZ_VERSION}.tar.xz"
XZ_MIRRORS=(
  "https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.xz"
  "https://netactuate.dl.sourceforge.net/project/lzmautils/xz-${XZ_VERSION}.tar.xz"
  "https://www.mirrorservice.org/pub/slackware/slackware-current/source/a/xz/xz-${XZ_VERSION}.tar.xz"
  "https://m3-container.net/M3_Container/oss_packages/xz-${XZ_VERSION}.tar.xz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "xz" "${XZ_VERSION}" "${XZ_TARBALL}" "${XZ_MIRRORS[@]}"
setup_alpine_chroot "${XZ_TARBALL}"
setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
clang \
pkgconfig && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf xz-${XZ_VERSION}.tar.xz && \
cd xz-${XZ_VERSION}/ && \
./configure CC=clang \
  --enable-static --disable-shared --disable-nls \
  LDFLAGS='-static -Wl,--gc-sections' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -ffunction-sections -fdata-sections -Wno-unterminated-string-initialization' && \
CC=clang LDFLAGS='-static -Wl,--gc-sections' make -j\$(nproc) && \
strip src/xz/xz && \
../upx --lzma src/xz/xz"

package_output "xz" "./pasta/xz-${XZ_VERSION}/src/xz/xz"
