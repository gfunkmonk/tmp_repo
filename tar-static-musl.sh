#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

TAR_VERSION="1.35"
PACKAGE_VERSION="${TAR_VERSION}"
TAR_TARBALL="tar-${TAR_VERSION}.tar.xz"
TAR_MIRRORS=(
  "https://ftp.gnu.org/gnu/tar/tar-${TAR_VERSION}.tar.xz"
  "https://fossies.org/linux/misc/tar-${TAR_VERSION}.tar.xz"
  "https://mirrors.slackware.com/slackware/slackware64-current/source/a/tar/tar-${TAR_VERSION}.tar.xz"
  "https://mirrors.omnios.org/tar/tar-${TAR_VERSION}.tar.xz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "tar" "${TAR_VERSION}" "${TAR_TARBALL}" "${TAR_MIRRORS[@]}"
setup_alpine_chroot "${TAR_TARBALL}"
copy_patches "tar-1.35.patch"
setup_qemu
mount_chroot

# Note: --with-zlib, --without-bz2lib; lzma/zstd/xml2/openssl linked via pkg-config --static
sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
automake \
autoconf \
pkgconfig \
zlib-dev \
zlib-static \
xz-dev \
xz-static \
zstd-dev \
zstd-static \
lz4-dev \
lz4-static \
libbz2 \
bzip2-static && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf tar-${TAR_VERSION}.tar.xz && \
cd tar-${TAR_VERSION}/ && \
patch -p1 --fuzz=4 < ../tar-1.35.patch && \
autoreconf -f -i && \
FORCE_UNSAFE_CONFIGURE=1 ./configure CC=gcc  --without-selinux \
  --disable-nls --disable-rpath --enable-largefile \
  LDFLAGS='-static -Wl,--gc-sections' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -ffunction-sections -fdata-sections -no-pie' && \
make -j\$(nproc) && \
strip src/tar && \
../upx --lzma src/tar"

package_output "tar" "./pasta/tar-${TAR_VERSION}/src/tar"
