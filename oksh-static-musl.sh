#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

echo -e "${VIOLET}= fetching latest oksh version${NC}"
OKSH_VERSION=$(curl -fsSL "https://api.github.com/repos/ibara/oksh/releases/latest" \
  | grep '"tag_name"' | sed 's/.*"release-\([^"]*\)".*/\1/' \
  | sed 's/  "tag_name": "oksh-//g' | sed 's/",//g') || true
if [ -z "${OKSH_VERSION}" ]; then
  echo -e "${TAWNY}= GitHub API unavailable, falling back to oksh 7.8${NC}"
  OKSH_VERSION="7.8"
fi

PACKAGE_VERSION="${OKSH_VERSION}"
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
pkgconfig \
ncurses-dev \
ncurses-static \
autoconf \
patch && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf oksh-${OKSH_VERSION}.tar.gz && \
cd oksh-${OKSH_VERSION}/ && \
./configure --cc=gcc --cflags=\"-Os -fomit-frame-pointer\" \
  --enable-curses --enable-lto --enable-static \
  LDFLAGS='-static' PKG_CONFIG='pkg-config --static' && \
make -j\$(nproc) && \
strip oksh && \
../upx --ultra-brute oksh"

package_output "oksh" "./pasta/oksh-${OKSH_VERSION}/oksh"
