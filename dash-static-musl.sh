#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

setup_tools

DASH_VERSION="0.5.13.1"
PACKAGE_VERSION="${DASH_VERSION}"
DASH_TARBALL="dash-${DASH_VERSION}.tar.gz"
DASH_MIRRORS=(
  "http://gondor.apana.org.au/~herbert/dash/files/dash-${DASH_VERSION}.tar.gz"
  "https://distfiles-origin.macports.org/dash/dash-${DASH_VERSION}.tar.gz"
  "https://distfiles.alpinelinux.org/distfiles/v3.23/dash-${DASH_VERSION}.tar.gz"
  "https://ftp.fr.openbsd.org/pub/OpenBSD/distfiles/dash-${DASH_VERSION}.tar.gz"
  "https://mirror-hk.koddos.net/blfs/svn/d/dash-${DASH_VERSION}.tar.gz"
  "https://mirrors.lug.mtu.edu/gentoo/distfiles/46/dash-${DASH_VERSION}.tar.gz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "dash" "${DASH_VERSION}" "${DASH_TARBALL}" "${DASH_MIRRORS[@]}"
setup_alpine_chroot "${DASH_TARBALL}"
copy_patches "dash.patch"
setup_qemu
mount_chroot

sudo chroot "./${CHROOTDIR}/" /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
automake \
libtool \
bison \
flex \
pkgconfig \
readline-dev \
readline-static \
ncurses-dev \
ncurses-static \
autoconf \
patch \
libedit-dev \
libedit-static && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR} && \
chmod 755 upx && \
tar xf dash-${DASH_VERSION}.tar.gz && \
cd dash-${DASH_VERSION}/ && \
patch -p1 --fuzz=4 < ../dash.patch && \
autoreconf -f -i && \
./configure --enable-static \
  LDFLAGS='-static -Wl,--gc-sections' \
  PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector -no-pie -fstack-clash-protection' && \
make -j\$(nproc) && \
strip src/dash && \
../upx --lzma src/dash"

package_output "dash" "./${CHROOTDIR}/dash-${DASH_VERSION}/src/dash"
