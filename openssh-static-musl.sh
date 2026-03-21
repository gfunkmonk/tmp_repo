#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

OPENSSH_VERSION="10.2p1"
PACKAGE_VERSION="${OPENSSH_VERSION}"
OPENSSH_TARBALL="openssh-${OPENSSH_VERSION}.tar.gz"
OPENSSH_MIRRORS=(
  "https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz"
  "https://mirrors.slackware.com/slackware/slackware64-current/source/n/openssh/openssh-${OPENSSH_VERSION}.tar.gz"
  "https://mirrors.mit.edu/macports/distfiles/openssh/openssh-${OPENSSH_VERSION}.tar.gz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "openssh" "${OPENSSH_VERSION}" "${OPENSSH_TARBALL}" "${OPENSSH_MIRRORS[@]}"
setup_alpine_chroot "${OPENSSH_TARBALL}"
setup_qemu
mount_chroot

sudo chroot "./${CHROOTDIR}/" /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
openssl-dev \
openssl-libs-static \
zlib-dev \
zlib-static \
autoconf \
automake && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf openssh-${OPENSSH_VERSION}.tar.gz && \
cd openssh-${OPENSSH_VERSION}/ && \
./configure --with-privsep-user=nobody \
  LIBS='-pthread' LDFLAGS='-static -Wl,--gc-sections' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector -no-pie -Wno-unterminated-string-initialization' && \
make -j\$(nproc) && \
strip ssh && \
../upx --lzma ssh"

package_output "openssh" "./${CHROOTDIR}/openssh-${OPENSSH_VERSION}/ssh"
