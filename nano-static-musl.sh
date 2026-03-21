#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

setup_tools

NANO_VERSION="8.7.1"
PACKAGE_VERSION="${NANO_VERSION}"
NANO_TARBALL="nano-${NANO_VERSION}.tar.xz"
NANO_MIRRORS=(
  "https://www.nano-editor.org/dist/v8/nano-${NANO_VERSION}.tar.xz"
  "https://fossies.org/linux/misc/nano-${NANO_VERSION}.tar.xz"
  "https://mirrors.slackware.com/slackware/slackware-current/source/ap/nano/nano-${NANO_VERSION}.tar.xz"
  "https://artfiles.org/gnupg.org/nano/nano-${NANO_VERSION}.tar.xz"
  "https://pilotfiber.dl.sourceforge.net/project/immortalwrt/sources/nano-${NANO_VERSION}.tar.xz"
)

run_build_setup "nano" "${NANO_VERSION}" "${NANO_TARBALL}" \
  "nano-colors.patch" \
  -- "${NANO_MIRRORS[@]}"

sudo chroot "./${CHROOTDIR}/" /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
pkgconfig \
ncurses-dev \
ncurses-static \
libmagic-static \
libmagic \
file-dev \
linux-headers && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf ${NANO_TARBALL} && \
cd nano-${NANO_VERSION}/ && \
patch -p1 --fuzz=4 < ../nano-colors.patch && \
./configure CC='gcc' \
  --sysconfdir=/etc --disable-nls --disable-utf8 --disable-tiny \
  --enable-nanorc --enable-color --enable-extra --enable-largefile \
  --enable-libmagic --disable-justify \
  LDFLAGS='-static -Wl,--gc-sections' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector -no-pie' && \
CC='gcc' make -j\$(nproc) && \
strip src/nano && \
../upx --ultra-brute src/nano"

package_output "nano" "./${CHROOTDIR}/nano-${NANO_VERSION}/src/nano"
