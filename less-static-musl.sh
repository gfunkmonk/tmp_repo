#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

setup_tools

LESS_VERSION="692"
PACKAGE_VERSION="${LESS_VERSION}"
LESS_TARBALL="less-${LESS_VERSION}.tar.gz"
LESS_MIRRORS=(
  "https://www.greenwoodsoftware.com/less/less-${LESS_VERSION}.tar.gz"
  "https://fossies.org/linux/misc/less-${LESS_VERSION}.tar.gz"
)

run_build_setup "less" "${LESS_VERSION}" "${LESS_TARBALL}" \
  -- "${LESS_MIRRORS[@]}"

# OPTIMIZATION: Use COMMON_BUILD_DEPS from common.sh
# Skip apk update if rootfs is fresh (< 1 day old)
sudo chroot "./${CHROOTDIR}/" /bin/sh -c "set -e && \
[ -f /.rootfs-fresh ] || apk update && \
rm -f /.rootfs-fresh && \
apk add ${COMMON_BUILD_DEPS} \
pkgconfig \
pcre2-static \
pcre2-dev \
ncurses-dev \
ncurses-static && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf ${LESS_TARBALL} && \
cd less-${LESS_VERSION}/ && \
./configure --with-regex=pcre2 --enable-year2038 --sysconfdir=/etc \
  LDFLAGS='-static -Wl,--gc-sections' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector' && \
make -j\$(nproc) && \
strip less && \
../upx --brute less"

package_output "less" "./${CHROOTDIR}/less-${LESS_VERSION}/less"
