#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

UPX_VERSION="5.1.3"
PACKAGE_VERSION="${UPX_VERSION}"

setup_arch
setup_cleanup
install_host_deps

################################################################################
# setup_alpine_chroot is not used here: there is no source tarball to copy in, #
# and no pre-built upx binary is needed (we are building upx itself).          #
################################################################################

echo -e "${HELIOTROPE}= download alpine rootfs${NC}"
wget -c "${ALPINE_URL}"
echo -e "${SKY}= extract rootfs${NC}"
mkdir -p pasta
tar xf "${TARBALL}" -C pasta/
echo -e "${PEACH}= copy resolv.conf into chroot${NC}"
cp /etc/resolv.conf ./pasta/etc/

setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
zlib-dev \
zlib-static \
zstd-dev \
zstd-static \
git \
cmake \
clang \
samurai && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
git clone https://github.com/gfunkmonk/upx upx-${UPX_VERSION} --depth=1 && \
cd upx-${UPX_VERSION}/ && \
git submodule init && git submodule update && \
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

package_output "upx" "./pasta/upx-${UPX_VERSION}/build/upx"