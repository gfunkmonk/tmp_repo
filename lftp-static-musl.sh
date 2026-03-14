#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

LFTP_VERSION="4.9.3"
PACKAGE_VERSION="${LFTP_VERSION}"
LFTP_TARBALL="lftp-${LFTP_VERSION}.tar.xz"
LFTP_URL="https://lftp.yar.ru/ftp/lftp-${LFTP_VERSION}.tar.xz"

setup_arch
setup_cleanup
install_host_deps
download_source "lftp" "${LFTP_VERSION}" "${LFTP_TARBALL}" "${LFTP_URL}"
setup_alpine_chroot "${LFTP_TARBALL}"
copy_patches "lftp-4.9.3.patch"
setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
autoconf \
automake \
libtool \
linux-headers \
perl \
python3 \
python3-dev \
expat-dev \
expat-static \
gettext-dev \
gettext-static \
libidn-dev \
libunistring-dev \
libunistring-static \
make \
pkgconfig \
ncurses-dev \
ncurses-static \
openssl-dev \
openssl-libs-static \
readline-dev \
readline-static \
zlib-dev \
zlib-static \
libstdc++-dev && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf lftp-${LFTP_VERSION}.tar.xz && \
cd lftp-${LFTP_VERSION}/ && \
patch -p1 --fuzz=4 < ../lftp-4.9.3.patch && \
autoreconf -i -f && \
./configure CC=gcc CXX=g++ LIBS='-l:libreadline.a -l:libncursesw.a' \
  --with-openssl --without-gnutls --enable-static --enable-threads=posix --disable-nls --disable-shared \
  LDFLAGS='-static -Wl,--gc-sections' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-std=c17 -Os -fomit-frame-pointer -ffunction-sections -fdata-sections -Wno-unterminated-string-initialization -Wno-deprecated-declarations' \
  CXXFLAGS='-std=c++14 -Os -fomit-frame-pointer -ffunction-sections -fdata-sections -Wno-deprecated-declarations -Wno-error=template-id-cdtor' && \
make -j\$(nproc) LDFLAGS='-static -all-static -Wl,--gc-sections' && \
strip src/lftp && \
../upx --lzma src/lftp"

package_output "lftp" "./pasta/lftp-${LFTP_VERSION}/src/lftp"
