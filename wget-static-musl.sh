#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

WGET_VERSION="1.25.0"
WGET_TARBALL="wget-${WGET_VERSION}.tar.gz"
WGET_MIRRORS=(
  "https://gnu.askapache.com/wget/wget-${WGET_VERSION}.tar.gz"
  "https://mirror.team-cymru.com/gnu/wget/wget-${WGET_VERSION}.tar.gz"
  "https://ftp.wayne.edu/gnu/wget/wget-${WGET_VERSION}.tar.gz"
  "https://mirror.us-midwest-1.nexcess.net/gnu/wget/wget-${WGET_VERSION}.tar.gz"
  "https://mirrors.ibiblio.org/gnu/wget/wget-${WGET_VERSION}.tar.gz"
  "https://mirror.csclub.uwaterloo.ca/gnu/wget/wget-${WGET_VERSION}.tar.gz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "wget" "${WGET_VERSION}" "${WGET_TARBALL}" "${WGET_MIRRORS[@]}"
setup_alpine_chroot "${WGET_TARBALL}"
copy_patches "wget-1.25.0-passive-ftp.patch"
setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
openssl-dev \
zlib-dev \
libidn2-dev \
libpsl-dev \
libidn2-static \
openssl-libs-static \
zlib-static \
libpsl-static \
libunistring-dev \
libunistring-static \
upx \
patch \
texinfo \
pcre2-dev \
pcre2-static \
perl && \
tar xf wget-${WGET_VERSION}.tar.gz && \
cd wget-${WGET_VERSION}/ && \
patch -p1 --fuzz=4 < ../wget-1.25.0-passive-ftp.patch && \
./configure CC=gcc --with-ssl=openssl --with-libidn --disable-nls \
  --disable-rpath --sysconfdir=/etc \
  LDFLAGS='-static -lidn2 -lunistring' \
  PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -Wno-unterminated-string-initialization' \
  PERL=/usr/bin/perl && \
make -j\$(nproc) && \
strip src/wget && \
upx --lzma src/wget"

package_output "wget" "./pasta/wget-${WGET_VERSION}/src/wget"
