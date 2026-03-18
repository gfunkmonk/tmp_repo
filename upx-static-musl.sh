#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

echo -e "${VIOLET}= fetching latest curl version${NC}"
UPX_VERSION=$(curl -fsSL "https://api.github.com/repos/gfunkmonk/upx/releases/latest" | grep '"tag_name"' \
  | sed 's/.*"release-\([^"]*\)".*/\1/' | sed 's/_/./g' | grep '":' | sed 's/"tag.name": "//g' \
  | sed 's/",//g' | sed 's/  //g') || true
if [ -z "${UPX_VERSION}" ]; then
  echo -e "${TAWNY}= GitHub API unavailable, falling back to upx 5.1.3${NC}"
  UPX_VERSION="5.1.3"
fi

PACKAGE_VERSION="${UPX_VERSION}"
UPX_TARBALL="curl-${UPX_VERSION}.tar.xz"
UPX_MIRRORS=(
  "https://github.com/gfunkmonk/upx/archive/refs/tags/${UPX_VERSION}.tar.gz"
  "https://github.com/gfunkmonk/upx/archive/refs/tags/${UPX_VERSION}.tar.gz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "curl" "${UPX_VERSION}" "${UPX_TARBALL}" "${UPX_MIRRORS[@]}"
setup_alpine_chroot "${UPX_TARBALL}"
setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
openssl-dev \
openssl-libs-static \
nghttp2-dev \
nghttp2-static \
libssh2-dev \
libssh2-static \
zlib-dev \
zlib-static \
zstd-dev \
zstd-static \
autoconf \
automake \
libunistring-static \
libunistring-dev \
libidn2-static \
libidn2-dev \
libpsl-static \
libpsl-dev \
git \
cmake \
clang && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf upx-${UPX_VERSION}.tar.xz && \
cd upx-${UPX_VERSION}/ && \
git submodule init && git submodule update \
mkdir build && cd build/ \
cmake -DUPX_CONFIG_DISABLE_WSTRICT=ON -DUPX_CONFIG_DISABLE_WERROR=ON -DCMAKE_VERBOSE_MAKEFILE=ON -DCMAKE_EXE_LINKER_FLAGS="-Wl,--gc-sections -static" \
  -DCMAKE_C_FLAGS="-Os -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector" -DCMAKE_CXX_FLAGS="-Os -ffunction-sections \
  -fdata-sections -fomit-frame-pointer -fno-stack-protector" ..
make -j\$(nproc) LDFLAGS='-static -all-static' && \
strip upx && \
../upx --lzma upx"

package_output "upx" "./pasta/upx-${UPX_VERSION}/build/upx"
