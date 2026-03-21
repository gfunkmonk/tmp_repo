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

run_build_setup "lftp" "${LFTP_VERSION}" "${LFTP_TARBALL}" \
  "lftp.patch" \
  -- "${LFTP_MIRRORS[@]}"

# OPTIMIZATION: Use COMMON_BUILD_DEPS from common.sh
# Skip apk update if rootfs is fresh (< 1 day old)
sudo chroot "./${CHROOTDIR}/" /bin/sh -c "set -e && \
[ -f /.rootfs-fresh ] || apk update && \
rm -f /.rootfs-fresh && \
apk add ${COMMON_BUILD_DEPS} \
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
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf lftp-${LFTP_VERSION}.tar.xz && \
cd lftp-${LFTP_VERSION}/ && \
patch -p1 --fuzz=4 < ../lftp.patch && \
autoreconf -i -f && \
./configure CC=gcc CXX=g++ LIBS='-l:libreadline.a -l:libncursesw.a' \
  --with-openssl --without-gnutls --enable-static --enable-threads=posix --disable-nls --disable-shared \
  LDFLAGS='-static -Wl,--gc-sections' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector -std=c17 -Wno-unterminated-string-initialization -Wno-deprecated-declarations -no-pie' \
  CXXFLAGS='-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector -std=c++14 -Wno-deprecated-declarations -Wno-error=template-id-cdtor' && \
make -j\$(nproc) LDFLAGS='-static -all-static -Wl,--gc-sections' && \
strip src/lftp && \
../upx --lzma src/lftp"

package_output "lftp" "./${CHROOTDIR}/lftp-${LFTP_VERSION}/src/lftp"
