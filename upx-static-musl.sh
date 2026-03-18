#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

echo -e "${VIOLET}= fetching latest upx version${NC}"
UPX_VERSION=$(curl -fsSL "https://api.github.com/repos/gfunkmonk/upx/releases/latest" | grep '"tag_name"' \
  | sed 's/.*"release-\([^"]*\)".*/\1/' | sed 's/_/./g' | grep '":' | sed 's/"tag.name": "//g' \
  | sed 's/",//g' | sed 's/  //g') || true
if [ -z "${UPX_VERSION}" ]; then
  echo -e "${TAWNY}= GitHub API unavailable, falling back to upx 5.1.3${NC}"
  UPX_VERSION="5.1.3"
fi

PACKAGE_VERSION="${UPX_VERSION}"
UPX_TARBALL="upx-${UPX_VERSION}.tar.gz"
UPX_MIRRORS=(
  "https://github.com/gfunkmonk/upx/archive/refs/tags/${UPX_VERSION}.tar.gz"
  "https://github.com/gfunkmonk/upx/archive/refs/tags/${UPX_VERSION}.tar.gz"
)

case "${ARCH}" in
  x86_64)  QEMU_ARCH="" ;;
  x86)     QEMU_ARCH="i386" ;;
  aarch64) QEMU_ARCH="aarch64" ;;
  armhf)   QEMU_ARCH="arm" ;;
  armv7)   QEMU_ARCH="arm" ;;
  *)
    echo -e "${LAGOON}Unknown architecture: ${HOTPINK}${ARCH}${NC}"
    exit 1
    ;;
esac

ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MAJOR_MINOR}/releases/${ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"
TARBALL="${ALPINE_URL##*/}"

cleanup() {
  sudo umount -lf "./pasta/proc" 2>/dev/null || true
  sudo umount -lf "./pasta/dev"  2>/dev/null || true
  sudo umount -lf "./pasta/sys"  2>/dev/null || true
}
trap cleanup EXIT

echo -e "${AQUA}= install dependencies${NC}"
DEBIAN_DEPS=(wget curl binutils)
[ -n "${QEMU_ARCH}" ] && DEBIAN_DEPS+=(qemu-user-static)
sudo apt-get update -qy && sudo apt-get install -y "${DEBIAN_DEPS[@]}"

echo -e "${HELIOTROPE}= download alpine rootfs${NC}"
wget -c "${ALPINE_URL}"

echo -e "${MINT}= extract rootfs${NC}"
mkdir -p pasta
tar xf "${TARBALL}" -C pasta/
echo -e "${PEACH}= copy resolv.conf and tools into chroot${NC}"
cp /etc/resolv.conf ./pasta/etc/
cp tools/upx/upx-${ARCH} pasta/upx

if [ -n "${QEMU_ARCH}" ]; then
  echo -e "${TAWNY}= setup QEMU for cross-arch builds${NC}"
  sudo mkdir -p "./pasta/usr/bin/"
  sudo cp "/usr/bin/qemu-${QEMU_ARCH}-static" "./pasta/usr/bin/"
fi

echo -e "${VIOLET}= mount, bind and chroot into dir${NC}"
sudo mount -t proc none "./pasta/proc/"
sudo mount --rbind /dev "./pasta/dev/"
sudo mount --rbind /sys "./pasta/sys/"

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
git clone http://github.com/gfunkmonk/upx upx-${UPX_VERSION} --depth=1 && \
cd upx-${UPX_VERSION}/ && \
git submodule init && git submodule update && \
mkdir build && cd build/ && \
cmake -DUPX_CONFIG_DISABLE_WSTRICT=ON -DUPX_CONFIG_DISABLE_WERROR=ON -DCMAKE_VERBOSE_MAKEFILE=ON -DCMAKE_EXE_LINKER_FLAGS='-Wl,--gc-sections -static' -DCMAKE_C_FLAGS='-Os -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector' -DCMAKE_CXX_FLAGS='-Os -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector' .. && \
make -j\$(nproc) LDFLAGS='-static -all-static' && \
strip upx && \
../upx --lzma upx"

package_output "upx" "./pasta/upx-${UPX_VERSION}/build/upx"
