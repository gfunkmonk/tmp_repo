#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

XZ_VERSION="5.8.2"
PACKAGE_VERSION="${XZ_VERSION}"
XZ_TARBALL="xz-${XZ_VERSION}.tar.xz"
XZ_URL="https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.xz"

setup_arch
setup_cleanup
install_host_deps
download_source "xz" "${XZ_VERSION}" "${XZ_TARBALL}" "${XZ_URL}"
setup_alpine_chroot "${XZ_TARBALL}"
setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
clang \
make \
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
