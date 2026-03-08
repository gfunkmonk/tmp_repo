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
LIME="\033[38;2;204;255;0m"
OCHRE="\033[38;2;204;119;34m"
NC="\033[0m"

ARCH=${ARCH:-x86_64}
DASH_VERSION="0.5.13.1"
ALPINE_VERSION="3.23.3"
ALPINE_MAJOR_MINOR="${ALPINE_VERSION%.*}"

DASH_MIRRORS=(
  "http://gondor.apana.org.au/~herbert/dash/files/dash-${DASH_VERSION}.tar.gz"
  "https://distfiles-origin.macports.org/dash/dash-${DASH_VERSION}.tar.gz"
  "https://distfiles.alpinelinux.org/distfiles/v3.23/dash-${DASH_VERSION}.tar.gz"
  "https://ftp.fr.openbsd.org/pub/OpenBSD/distfiles/dash-${DASH_VERSION}.tar.gz"
  "https://mirror-hk.koddos.net/blfs/svn/d/dash-${DASH_VERSION}.tar.gz"
  "https://mirrors.lug.mtu.edu/gentoo/distfiles/46/dash-${DASH_VERSION}.tar.gz"
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

echo -e "${AQUA}= downloading dash-${DASH_VERSION} tarball${NC}"
DASH_TARBALL="dash-${DASH_VERSION}.tar.gz"
DASH_DOWNLOADED=false
for mirror in "${DASH_MIRRORS[@]}"; do
  echo -e "${TAWNY}= trying mirror: ${mirror}${NC}"
  if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
      -o "${DASH_TARBALL}" "${mirror}"; then
    echo -e "${MINT}= downloaded from: ${mirror}${NC}"
    DASH_DOWNLOADED=true
    break
  else
    echo -e "${LEMON}= failed: ${mirror}${NC}"
    rm -f "${DASH_TARBALL}"
  fi
done
if [ "${DASH_DOWNLOADED}" = false ]; then
  echo -e "${TOMATO}= ERROR: all mirrors failed for dash-${DASH_VERSION}.tar.gz${NC}"
  exit 1
fi

echo -e "${LAGOON}= downloading patches${NC}"
DASH_PATCH_URL="https://github.com/gfunkmonk/dash-static-musl/raw/refs/heads/main/mega.patch"
if ! curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 30 \
    -o "mega.patch" \
    "${DASH_PATCH_URL}"; then
  echo -e "${TOMATO}= ERROR: failed to download patch from ${DASH_PATCH_URL}${NC}"
  exit 1
fi

echo -e "${HELIOTROPE}= download alpine rootfs${NC}"
wget -c "${ALPINE_URL}"

echo -e "${MINT}= extract rootfs${NC}"
mkdir -p pasta
tar xf "${TARBALL}" -C pasta/
echo -e "${PEACH}= copy resolv.conf and dash tarball into chroot${NC}"
cp /etc/resolv.conf ./pasta/etc/
cp "${DASH_TARBALL}" "./pasta/${DASH_TARBALL}"
cp "mega.patch" "./pasta/mega.patch"

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
make \
automake \
clang \
libtool \
bison \
flex \
pkgconfig \
readline-dev \
readline-static \
ncurses-dev \
ncurses-static \
autoconf \
patch \
libedit-dev \
libedit-static \
upx && \
tar xf dash-${DASH_VERSION}.tar.gz && \
cd dash-${DASH_VERSION}/ && \
patch -p1 --fuzz=4 < ../mega.patch && \
autoreconf -f -i && \
./configure --enable-static \
  LDFLAGS='-static' \
  PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -no-pie -fomit-frame-pointer -fstack-clash-protection' \
  CXXFLAGS='-fno-delete-null-pointer-checks -fno-schedule-insns2' && \
make -j\$(nproc) && \
strip src/dash && \
upx --lzma src/dash"
mkdir -p dist
cp "./pasta/dash-${DASH_VERSION}/src/dash" "dist/dash-${ARCH}"
if command -v file >/dev/null 2>&1; then echo -e "${ORANGE} File Info:  $(file "dist/dash-${ARCH}" | cut -d: -f2-)${NC}"; fi
tar -C dist -cJf "dist/dash-${ARCH}.tar.xz" "dash-${ARCH}"
echo -e "${LEMON}= All done! Binary: dist/dash-${ARCH} ($(du -sh "dist/dash-${ARCH}" | cut -f1))${NC}"
