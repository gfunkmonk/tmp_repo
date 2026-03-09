#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

echo -e "${AQUA}= fetching latest aria2 version${NC}"
ARIA2_VERSION=$(curl -fsSL --connect-timeout 10 --max-time 30 \
  "https://api.github.com/repos/aria2/aria2/releases/latest" \
  | grep '"tag_name"' | sed 's/.*"release-\([^"]*\)".*/\1/') || true
if [ -z "${ARIA2_VERSION}" ]; then
  echo -e "${TAWNY}= GitHub API unavailable, falling back to aria2 1.37.0${NC}"
  ARIA2_VERSION="1.37.0"
fi
echo -e "${MINT}= building aria2 version: ${ARIA2_VERSION}${NC}"
PACKAGE_VERSION="${ARIA2_VERSION}"

ARIA2_TARBALL="aria2-${ARIA2_VERSION}.tar.gz"
ARIA2_MIRRORS=(
  "https://github.com/aria2/aria2/releases/download/release-${ARIA2_VERSION}/aria2-${ARIA2_VERSION}.tar.gz"
  "https://distfiles.alpinelinux.org/distfiles/v3.21/aria2-${ARIA2_VERSION}.tar.gz"
  "https://sources.voidlinux.org/aria2-${ARIA2_VERSION}/aria2-${ARIA2_VERSION}.tar.gz"
  "https://mirrors.lug.mtu.edu/gentoo/distfiles/aria2-${ARIA2_VERSION}.tar.gz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "aria2" "${ARIA2_VERSION}" "${ARIA2_TARBALL}" "${ARIA2_MIRRORS[@]}"
setup_alpine_chroot "${ARIA2_TARBALL}"
copy_patches "aria2-1.37.0.patch"
setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
openssl-dev \
openssl-libs-static \
zlib-dev \
zlib-static \
libpsl-dev \
libpsl-static \
libidn2-static \
c-ares-dev \
libssh2-dev \
libssh2-static \
sqlite-dev \
sqlite-static \
libxml2-dev \
libxml2-static \
util-linux-static \
xz-dev \
xz-static \
curl \
patch \
pkgconfig && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf aria2-${ARIA2_VERSION}.tar.gz && \
cd aria2-${ARIA2_VERSION}/ && \
patch -p1 --fuzz=4 < ../aria2-1.37.0.patch && \
./configure CC=gcc ARIA2_STATIC=yes \
  --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
  --without-gnutls --with-openssl --with-libcares \
  --disable-bittorrent --with-sqlite3 \
  --enable-shared=no --enable-static --disable-shared \
  LDFLAGS='-static' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -Wno-unterminated-string-initialization' && \
make -j\$(nproc) && \
strip src/aria2c && \
../upx --lzma src/aria2c"

package_output "aria2c" "./pasta/aria2-${ARIA2_VERSION}/src/aria2c"
