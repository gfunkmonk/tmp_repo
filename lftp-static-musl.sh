#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

setup_tools

LFTP_VERSION="4.9.3"
PACKAGE_VERSION="${LFTP_VERSION}"
LFTP_TARBALL="lftp-${LFTP_VERSION}.tar.xz"
LFTP_MIRRORS=(
  "https://lftp.yar.ru/ftp/lftp-${LFTP_VERSION}.tar.xz"
  "https://distfiles.openadk.org/lftp-${LFTP_VERSION}.tar.xz"
  "https://fossies.org/linux/misc/lftp-${LFTP_VERSION}.tar.xz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "lftp" "${LFTP_VERSION}" "${LFTP_TARBALL}" "${LFTP_MIRRORS[@]}"
setup_alpine_chroot "${LFTP_TARBALL}"
copy_patches "lftp.patch"
setup_qemu
mount_chroot

sudo chroot "./${CHROOTDIR}/" /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
autoconf \
automake \
libtool \
linux-headers \
expat-dev \
expat-static \
libidn-dev \
libunistring-dev \
libunistring-static \
pkgconfig \
ncurses-dev \
ncurses-static \
openssl-dev \
openssl-libs-static \
readline-dev \
readline-static \
zlib-dev \
zlib-static \
libstdc++-dev \
gettext-dev \
gettext-static && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR} && \
chmod 755 upx && \
tar xf lftp-${LFTP_VERSION}.tar.xz && \
cd lftp-${LFTP_VERSION}/ && \
patch -p1 --fuzz=4 < ../lftp.patch && \
autoreconf -i -f && \
./configure CC=gcc CXX=g++ LIBS='-l:libreadline.a -l:libncursesw.a' \
  --with-openssl --without-gnutls --enable-static --enable-threads=posix --disable-nls --disable-shared \
  LDFLAGS='-static -Wl,--gc-sections' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-std=c17 -Os -static -fomit-frame-pointer -ffunction-sections -fdata-sections -Wno-unterminated-string-initialization -Wno-deprecated-declarations -no-pie' \
  CXXFLAGS='-std=c++14 -Os -fomit-frame-pointer -ffunction-sections -fdata-sections -Wno-deprecated-declarations -Wno-error=template-id-cdtor' && \
make -j\$(nproc) LDFLAGS='-static -all-static -Wl,--gc-sections' && \
strip src/lftp && \
../upx --lzma src/lftp"

package_output "lftp" "./${CHROOTDIR}/lftp-${LFTP_VERSION}/src/lftp"
