#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

BSDTAR_VERSION="3.8.5"
BSDTAR_TARBALL="libarchive-${BSDTAR_VERSION}.tar.xz"
BSDTAR_MIRRORS=(
  "https://github.com/libarchive/libarchive/releases/download/v${BSDTAR_VERSION}/libarchive-${BSDTAR_VERSION}.tar.xz"
  "https://mirror.fcix.net/slackware/slackware-current/source/l/libarchive/libarchive-${BSDTAR_VERSION}.tar.xz"
  "https://sources.voidlinux.org/libarchive-${BSDTAR_VERSION}/libarchive-${BSDTAR_VERSION}.tar.xz"
  "https://ftp2.osuosl.org/pub/blfs/svn/l/libarchive-${BSDTAR_VERSION}.tar.xz"
  "https://ftp.fau.de/macports/distfiles/libarchive/libarchive-${BSDTAR_VERSION}.tar.xz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "libarchive" "${BSDTAR_VERSION}" "${BSDTAR_TARBALL}" "${BSDTAR_MIRRORS[@]}"
setup_alpine_chroot "${BSDTAR_TARBALL}"
setup_qemu
mount_chroot

# Note: --with-zlib, --without-bz2lib; lzma/zstd/xml2/openssl linked via pkg-config --static
sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
make \
pkgconfig \
zlib-dev \
zlib-static \
xz-dev \
xz-static \
zstd-dev \
zstd-static \
lz4-dev \
lz4-static \
openssl-dev \
openssl-libs-static \
libxml2-dev \
libxml2-static && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf libarchive-${BSDTAR_VERSION}.tar.xz && \
cd libarchive-${BSDTAR_VERSION}/ && \
./configure CC=gcc \
  --disable-shared --enable-static \
  --enable-bsdtar=static \
  --disable-bsdcat --disable-bsdcpio \
  --with-zlib --without-bz2lib \
  --disable-maintainer-mode --disable-dependency-tracking \
  LDFLAGS='-static' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -no-pie' && \
make -j\$(nproc) && \
gcc -static -o bsdtar tar/bsdtar-bsdtar.o \
  tar/bsdtar-cmdline.o tar/bsdtar-creation_set.o \
  tar/bsdtar-read.o tar/bsdtar-subst.o tar/bsdtar-util.o \
  tar/bsdtar-write.o .libs/libarchive.a .libs/libarchive_fe.a \
  -lz -llzma -lzstd -llz4 -lxml2 -lcrypto -lssl && \
strip bsdtar && \
../upx --lzma bsdtar"

package_output "bsdtar" "./pasta/libarchive-${BSDTAR_VERSION}/bsdtar"
