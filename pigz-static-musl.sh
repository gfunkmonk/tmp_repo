#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

setup_tools

PIGZ_VERSION="2.8"
PACKAGE_VERSION="${PIGZ_VERSION}"
PIGZ_TARBALL="pigz-${PIGZ_VERSION}.tar.gz"
PIGZ_MIRRORS=(
  "https://zlib.net/pigz/pigz-${PIGZ_VERSION}.tar.gz"
  "https://fossies.org/linux/privat/pigz-${PIGZ_VERSION}.tar.gz"
  "https://gentoo.osuosl.org/distfiles/70/pigz-${PIGZ_VERSION}.tar.gz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "pigz" "${PIGZ_VERSION}" "${PIGZ_TARBALL}" "${PIGZ_MIRRORS[@]}"
setup_alpine_chroot "${PIGZ_TARBALL}"
copy_patches "pigz.patch"
setup_qemu
mount_chroot

sudo chroot "./${CHROOTDIR}/" /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
make \
sed \
gcc \
zlib-dev \
zlib-static && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf pigz-${PIGZ_VERSION}.tar.gz && \
cd pigz-${PIGZ_VERSION}/ && \
patch -p1 --fuzz=4 < ../pigz.patch && \
make -j\$(nproc) && \
strip pigz && \
../upx --lzma pigz"

package_output "pigz" "./${CHROOTDIR}/pigz-${PIGZ_VERSION}/pigz"
