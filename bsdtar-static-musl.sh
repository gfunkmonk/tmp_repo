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
PEACH="\033[38;2;246;161;146m"
LAGOON="\033[38;2;142;235;236m"
HOTPINK="\033[38;2;255;105;180m"
NC="\033[0m"

ARCH=${ARCH:-x86_64}
BSDTAR_VERSION="3.8.5"
ALPINE_VERSION="3.23.3"
ALPINE_MAJOR_MINOR="${ALPINE_VERSION%.*}"

BSDTAR_MIRRORS=(
  "https://github.com/libarchive/libarchive/releases/download/v${BSDTAR_VERSION}/libarchive-${BSDTAR_VERSION}.tar.xz"
  "https://mirror.fcix.net/slackware/slackware-current/source/l/libarchive/libarchive-${BSDTAR_VERSION}.tar.xz"
  "https://sources.voidlinux.org/libarchive-${BSDTAR_VERSION}/libarchive-${BSDTAR_VERSION}.tar.xz"
  "https://ftp2.osuosl.org/pub/blfs/svn/l/libarchive-${BSDTAR_VERSION}.tar.xz"
  "https://ftp.fau.de/macports/distfiles/libarchive/libarchive-${BSDTAR_VERSION}.tar.xz"
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
DEBIAN_DEPS=(wget curl binutils libxml2-dev)
[ -n "${QEMU_ARCH}" ] && DEBIAN_DEPS+=(qemu-user-static)
sudo apt-get update -qy && sudo apt-get install -y "${DEBIAN_DEPS[@]}"

echo -e "${AQUA}= downloading libarchive-${BSDTAR_VERSION} tarball${NC}"
BSDTAR_TARBALL="libarchive-${BSDTAR_VERSION}.tar.xz"
BSDTAR_DOWNLOADED=false
for mirror in "${BSDTAR_MIRRORS[@]}"; do
  echo -e "${TAWNY}= trying mirror: ${mirror}${NC}"
  if curl -fsSL --retry 3 --retry-delay 2 -o "${BSDTAR_TARBALL}" "${mirror}"; then
    echo -e "${MINT}= downloaded from: ${mirror}${NC}"
    BSDTAR_DOWNLOADED=true
    break
  else
    echo -e "${LEMON}= failed: ${mirror}${NC}"
    rm -f "${BSDTAR_TARBALL}"
  fi
done
if [ "${BSDTAR_DOWNLOADED}" = false ]; then
  echo -e "${TOMATO}= ERROR: all mirrors failed for libarchive-${BSDTAR_VERSION}.tar.xz${NC}"
  exit 1
fi

echo -e "${HELIOTROPE}= download alpine rootfs${NC}"
wget -c "${ALPINE_URL}"

echo -e "${MINT}= extract rootfs${NC}"
mkdir -p pasta
tar xf "${TARBALL}" -C pasta/
echo -e "${PEACH}= copy resolv.conf and libarchive tarball into chroot${NC}"
cp /etc/resolv.conf ./pasta/etc/
cp "${BSDTAR_TARBALL}" "./pasta/${BSDTAR_TARBALL}"

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
clang \
make \
pkgconfig \
git \
automake \
autoconf \
libtool \
bison \
flex \
python3 \
perl \
wget \
texinfo \
gettext \
gettext-dev \
gettext-static \
gettext-libs \
xz-dev \
xz-static \
xz-libs \
zlib \
zlib-dev \
zlib-static \
zlib-ng \
zlib-ng-dev \
bzip2-dev \
bzip2-static \
lz4-dev \
lz4-static \
zstd-dev \
zstd-static \
openssl \
openssl-dev \
openssl-libs-static \
openssl-misc \
libssl3 \
libintl \
libbsd \
libbsd-dev \
libbsd-static \
libselinux-dev \
sqlite \
sqlite-dev \
pcre-dev \
libxml2 \
libxml2-dev \
libxml2-static \
docbook-xsl \
libxslt \
docbook2x \
upx && \
tar xf libarchive-${BSDTAR_VERSION}.tar.xz && \
cd libarchive-${BSDTAR_VERSION}/ && \
./configure CC=gcc --disable-shared --enable-bsdtar=static --disable-bsdcat --disable-bsdcpio --with-zlib --without-bz2lib --disable-maintainer-mode --disable-dependency-tracking LDFLAGS='-static' CFLAGS='-Os -no-pie' && \
LDFLAGS='-static' make -j\$(nproc) && \
gcc -static -o bsdtar tar/bsdtar-bsdtar.o tar/bsdtar-cmdline.o tar/bsdtar-creation_set.o tar/bsdtar-read.o tar/bsdtar-subst.o tar/bsdtar-util.o tar/bsdtar-write.o .libs/libarchive.a .libs/libarchive_fe.a -lz -llzma -lzstd -lxml2 -lcrypto -lssl && \
strip bsdtar && \
if [ ! -f "./pasta/bsdtar-${BSDTAR_VERSION}/bsdtar" ]; then
  echo -e "${TOMATO}Error: bsdtar binary not found after build${NC}" >&2
  exit 1
fi
upx --lzma bsdtar"
mkdir -p dist
cp "./pasta/libarchive-${BSDTAR_VERSION}/bsdtar" "dist/bsdtar-${ARCH}"
if command -v file >/dev/null 2>&1; then echo -e "${ORANGE} File Info:  $(file "dist/bsdtar-${ARCH}" | cut -d: -f2-)${NC}"; fi
tar -C dist -cJf "dist/bsdtar-${ARCH}.tar.xz" "bsdtar-${ARCH}"
echo -e "${LEMON}= All done!${NC}"