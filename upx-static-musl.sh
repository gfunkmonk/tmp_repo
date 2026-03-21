#!/bin/bash
set -euo pipefail

. "$(dirname "$0")/common.sh"

setup_tools

echo -e "${VIOLET}= fetching latest upx version${NC}"
UPX_VERSION=$(gh_latest_release "upx/upx" '.tag_name | ltrimstr("v")') || true
if [ -z "${UPX_VERSION}" ]; then
  echo -e "${TAWNY}= GitHub API unavailable, falling back to upx 5.1.1${NC}"
  UPX_VERSION="5.1.1"
fi

PACKAGE_VERSION="${UPX_VERSION}"
UPX_TARBALL="upx-${UPX_VERSION}-src.tar.xz"
UPX_MIRRORS=(
  "https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-src.tar.xz"
  "https://fossies.org/linux/misc/upx-${UPX_VERSION}-src.tar.xz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "upx" "${UPX_VERSION}" "${UPX_TARBALL}" "${UPX_MIRRORS[@]}"
setup_alpine_chroot "${UPX_TARBALL}"
copy_patches "upx-mod.patch"
setup_qemu
mount_chroot

sudo chroot "./${CHROOTDIR}/" /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
zlib-dev \
zlib-static \
zstd-dev \
zstd-static \
cmake \
samurai && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf upx-${UPX_VERSION}-src.tar.xz && \
cd upx-${UPX_VERSION}-src/ && \
patch -p1 --fuzz=4 < ../upx-mod.patch && \
mkdir build && cd build/ && \
cmake -G Ninja \
  -DCMAKE_EXE_LINKER_FLAGS='-Wl,--gc-sections -static' \
  -DCMAKE_C_FLAGS_RELEASE='-Os -DNDEBUG -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector' \
  -DCMAKE_CXX_FLAGS_RELEASE='-Os -DNDEBUG -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector' \
  -DCMAKE_BUILD_TYPE=Release \
  -DUPX_CONFIG_DISABLE_GITREV=ON \
  -DUPX_CONFIG_DISABLE_WSTRICT=ON \
  -DUSE_STRICT_DEFAULTS=OFF \
  -DUPX_CONFIG_REQUIRE_THREADS=ON \
  -S .. && \
ninja -j\$(nproc) && \
strip upx && \
cp upx upx1 && \
./upx1 --lzma upx"

package_output "upx" "./${CHROOTDIR}/upx-${UPX_VERSION}-src/build/upx"
