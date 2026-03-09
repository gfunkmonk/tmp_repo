#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

OKSH_VERSION="7.8"
OKSH_TARBALL="oksh-${OKSH_VERSION}.tar.gz"
OKSH_MIRRORS=(
  "https://github.com/ibara/oksh/releases/download/oksh-${OKSH_VERSION}/oksh-${OKSH_VERSION}.tar.gz"
  "https://distfiles.alpinelinux.org/distfiles/v3.23/oksh-${OKSH_VERSION}.tar.gz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "oksh" "${OKSH_VERSION}" "${OKSH_TARBALL}" "${OKSH_MIRRORS[@]}"
setup_alpine_chroot "${OKSH_TARBALL}"
setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
make \
automake \
clang \
libtool \
bison \
flex \
pkgconfig \
readline-dev \
readline-static \
libedit \
libedit-dev \
libedit-static \
ncurses-dev \
ncurses-static \
autoconf \
patch \
upx && \
mkdir -p /ccache && export CCACHE_DIR=/ccache CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
tar xf oksh-${OKSH_VERSION}.tar.gz && \
cd oksh-${OKSH_VERSION}/ && \
./configure --cc=gcc --cflags=\"-Os -fomit-frame-pointer\" \
  --enable-curses --enable-lto --enable-static \
  LDFLAGS='-static' PKG_CONFIG='pkg-config --static' && \
make -j\$(nproc) && \
strip oksh && \
upx --ultra-brute oksh"

package_output "oksh" "./pasta/oksh-${OKSH_VERSION}/oksh"
