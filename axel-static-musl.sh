#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

AXEL_VERSION="2.17.14"
PACKAGE_VERSION="${AXEL_VERSION}"
AXEL_TARBALL="axel-${AXEL_VERSION}.tar.xz"
AXEL_MIRRORS=(
  "https://github.com/axel-download-accelerator/axel/releases/download/v${AXEL_VERSION}/axel-${AXEL_VERSION}.tar.xz"
  "https://bos.us.distfiles.macports.org/axel/axel-${AXEL_VERSION}.tar.xz"
  "http://download.nus.edu.sg/mirror/gentoo/distfiles/d5/axel-${AXEL_VERSION}.tar.xz"
  "https://mse.uk.distfiles.macports.org/axel/axel-${AXEL_VERSION}.tar.xz"
  "https://mirror.ismdeep.com/axel/v2.17.14/axel-${AXEL_VERSION}.tar.xz"
  "https://code.opensuse.org/package/axel/blob/master/f/axel-${AXEL_VERSION}.tar.xz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "axel" "${AXEL_VERSION}" "${AXEL_TARBALL}" "${AXEL_MIRRORS[@]}"
setup_alpine_chroot "${AXEL_TARBALL}"
setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
openssl-dev \
zlib-dev \
libidn2-dev \
libpsl-dev \
libidn2-static \
openssl-libs-static \
zlib-static \
libpsl-static \
libunistring-dev \
libunistring-static && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf axel-${AXEL_VERSION}.tar.xz && \
cd axel-${AXEL_VERSION}/ && \
./configure CC=gcc LDFLAGS='-static' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -Wno-unterminated-string-initialization' && \
make -j\$(nproc) && \
strip axel && \
../upx --lzma axel"

package_output "axel" "./pasta/axel-${AXEL_VERSION}/axel"
