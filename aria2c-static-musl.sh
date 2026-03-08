#!/bin/bash
set -euo pipefail

ORANGE="\033[38;2;255;165;0m"
LEMON="\033[38;2;255;244;79m"
TAWNY="\033[38;2;204;78;0m"
HELIOTROPE="\033[38;2;223;115;255m"
VIOLET="\033[38;2;143;0;255m"
MINT="\033[38;2;152;255;152m"
AQUA="\033[38;2;18;254;202m"
TOMATO="\033[38;2;255;99;71m"
NC="\033[0m"

ARCH=${ARCH:-x86_64}
ALPINE_VERSION="3.23.3"
ALPINE_MAJOR_MINOR="${ALPINE_VERSION%.*}"

case "${ARCH}" in
  x86_64)  QEMU_ARCH="" ;;
  x86)     QEMU_ARCH="i386" ;;
  aarch64) QEMU_ARCH="aarch64" ;;
  armhf)   QEMU_ARCH="arm" ;;
  armv7)   QEMU_ARCH="arm" ;;
  *)
    echo "Unknown architecture: ${ARCH}"
    exit 1
    ;;
esac

ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MAJOR_MINOR}/releases/${ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"
TARBALL="${ALPINE_URL##*/}"

## unmount bind mounts on exit to avoid leaking mounts on failure
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

echo -e "${AQUA}= fetching latest aria2 version${NC}"
ARIA2_VERSION=$(curl -fsSL "https://api.github.com/repos/aria2/aria2/releases/latest" \
  | grep '"tag_name"' | sed 's/.*"release-\([^"]*\)".*/\1/') || true
if [ -z "${ARIA2_VERSION}" ]; then
  echo -e "${TAWNY}= GitHub API unavailable, falling back to aria2 1.37.0${NC}"
  ARIA2_VERSION="1.37.0"
fi
echo -e "${MINT}= building aria2 version: ${ARIA2_VERSION}${NC}"

echo -e "${HELIOTROPE}= download alpine rootfs${NC}"
wget -c "${ALPINE_URL}"

echo -e "${MINT}= extract rootfs${NC}"
mkdir -p pasta
tar xf "${TARBALL}" -C pasta/

echo -e "${TOMATO}= copy resolv.conf into the folder${NC}"
cp /etc/resolv.conf ./pasta/etc/

if [ -n "${QEMU_ARCH}" ]; then
  echo -e "${TAWNY}= setup QEMU for cross-arch builds${NC}"
  sudo mkdir -p "./pasta/usr/bin/"
  sudo cp "/usr/bin/qemu-${QEMU_ARCH}-static" "./pasta/usr/bin/"
fi

echo -e "${VIOLET}= mount, bind and chroot into dir${NC}"
sudo mount -t proc none ./pasta/proc/
sudo mount --rbind /dev ./pasta/dev/
sudo mount --rbind /sys ./pasta/sys/
sudo chroot ./pasta/ /bin/sh -c "apk update && apk add build-base \
musl-dev \
openssl-dev \
openssl-libs-static \
zlib-dev \
zlib-static \
libpsl-dev \
libpsl-static \
libidn2-static \
c-ares-dev \
libssh2-dev \
libssh2-static \
sqlite-dev \
sqlite-static \
libxml2-dev \
libxml2-static \
util-linux-static \
curl \
patch \
pkgconfig \
upx \
xz-dev \
xz-static \
perl && curl -fsSL -O 'https://github.com/aria2/aria2/releases/download/release-${ARIA2_VERSION}/aria2-${ARIA2_VERSION}.tar.gz' && \
curl -fsSL -O 'https://github.com/gfunkmonk/aria2c-static-musl/raw/refs/heads/main/aria2-1.37.0.conf.patch' && \
tar xf aria2-${ARIA2_VERSION}.tar.gz && \
cd aria2-${ARIA2_VERSION}/ && \
patch -p1 < ../aria2-1.37.0.conf.patch && \
./configure CC=gcc ARIA2_STATIC=yes --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt --without-gnutls --with-openssl --disable-bittorrent --with-libcares --with-sqlite3 --enable-shared=no --enable-static --disable-shared LDFLAGS='-static' PKG_CONFIG='pkg-config --static' CFLAGS='-Os -Wno-unterminated-string-initialization' && \
make -j\$(nproc) && \
strip src/aria2c && \
upx --lzma src/aria2c"
if [ ! -f "./pasta/aria2-${ARIA2_VERSION}/src/aria2c" ]; then
  echo "Error: aria2c binary not found after build" >&2
  exit 1
fi
mkdir -p dist
cp "./pasta/aria2-${ARIA2_VERSION}/src/aria2c" "dist/aria2c-${ARCH}"
if command -v file >/dev/null 2>&1; then echo -e "${ORANGE} File Info:  $(file "dist/aria2c-${ARCH}" | cut -d: -f2-)${NC}"; fi
tar -C dist -cJf "dist/aria2c-${ARCH}.tar.xz" "aria2c-${ARCH}"
echo -e "${LEMON}= All done! Binary: dist/aria2c-${ARCH} ($(du -sh "dist/aria2c-${ARCH}" | cut -f1))${NC}"