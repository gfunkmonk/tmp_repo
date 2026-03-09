#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

CURL_VERSION="8.18.0"
CURL_TARBALL="curl-${CURL_VERSION}.tar.xz"
CURL_MIRRORS=(
  "https://curl.se/download/curl-${CURL_VERSION}.tar.xz"
  "https://github.com/curl/curl/releases/download/curl-8_18_0/curl-${CURL_VERSION}.tar.xz"
  "https://mirrors.omnios.org/curl/curl-${CURL_VERSION}.tar.xz"
  "https://mirrors.slackware.com/slackware/slackware-current/source/n/curl/curl-${CURL_VERSION}.tar.xz"
  "https://ftp.belnet.be/mirror/rsync.gentoo.org/gentoo/distfiles/e8/curl-${CURL_VERSION}.tar.xz"
  "https://mirror.ircam.fr/pub/OpenBSD/distfiles/curl-${CURL_VERSION}.tar.xz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "curl" "${CURL_VERSION}" "${CURL_TARBALL}" "${CURL_MIRRORS[@]}"
setup_alpine_chroot "${CURL_TARBALL}"
setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
openssl-dev \
openssl-libs-static \
nghttp2-dev \
nghttp2-static \
libssh2-dev \
libssh2-static \
zlib-dev \
zlib-static \
zstd-dev \
zstd-static \
clang && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf curl-${CURL_VERSION}.tar.xz && \
cd curl-${CURL_VERSION}/ && \
./configure \
  --disable-shared --enable-static \
  --disable-ldap --enable-ipv6 --enable-unix-sockets \
  --with-ssl --with-libssh2 \
  --disable-docs --disable-manual --without-libpsl \
  CC=clang LDFLAGS='-static' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -Wno-unterminated-string-initialization' && \
make -j\$(nproc) V=1 LDFLAGS='-static -all-static' && \
strip src/curl && \
../upx --lzma src/curl"

package_output "curl" "./pasta/curl-${CURL_VERSION}/src/curl"
