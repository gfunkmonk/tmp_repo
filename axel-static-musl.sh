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
LIME="\E033[38;2;204;255;0m"
NC="\033[0m"

ARCH=${ARCH:-x86_64}
AXEL_VERSION="2.17.14"
ALPINE_VERSION="3.23.3"
ALPINE_MAJOR_MINOR="${ALPINE_VERSION%.*}"

AXEL_MIRRORS=(
  "https://github.com/axel-download-accelerator/axel/releases/download/v${AXEL_VERSION}/axel-${AXEL_VERSION}.tar.xz"
  "https://bos.us.distfiles.macports.org/axel/axel-${AXEL_VERSION}.tar.xz"
  "http://download.nus.edu.sg/mirror/gentoo/distfiles/d5/axel-${AXEL_VERSION}.tar.xz"
  "https://mse.uk.distfiles.macports.org/axel/axel-${AXEL_VERSION}.tar.xz"
  "https://mirror.ismdeep.com/axel/v2.17.14/axel-${AXEL_VERSION}.tar.xz"
  "https://code.opensuse.org/package/axel/blob/master/f/axel-${AXEL_VERSION}.tar.xz"
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

case "${ARCH}" in
  x86_64)  ALPINE_SHA256="42d0e6d8de5521e7bf92e075e032b5690c1d948fa9775efa32a51a38b25460fb" ;;
  x86)     ALPINE_SHA256="918b3dd37b0014ea8571a5ae206bb2e963999e61b7bc0332deab0041d195126a" ;;
  aarch64) ALPINE_SHA256="f219bb9d65febed9046951b19f2b893b331315740af32c47e39b38fcca4be543" ;;
  armhf)   ALPINE_SHA256="9017ede7039cc8463f9bf9625d5385ad82bfc731ef629b9f86afa1dd572e4e1c" ;;
  armv7)   ALPINE_SHA256="56783112f98d59beed6bdd60329868dee4424d42a27f0660ee79691d9b7da7e0" ;;
esac

ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MAJOR_MINOR}/releases/${ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"
TARBALL="${ALPINE_URL##*/}"

verify_checksum() {
  local file="$1" expected="$2"
  local actual
  actual=$(sha256sum "$file" | cut -d' ' -f1)
  if [ "$actual" != "$expected" ]; then
    echo -e "${TOMATO}= ERROR: SHA256 mismatch for ${file}${NC}"
    echo -e "${HOTPINK}= expected: ${expected}${NC}"
    echo -e "${TOMATO}= actual:   ${actual}${NC}"
    exit 1
  fi
  echo -e "${LIME}= SHA256 verified: ${file}${NC}"
}

## unmount filesystems on exit to avoid orphaned mounts
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

echo -e "${AQUA}= downloading axel-${AXEL_VERSION} tarball${NC}"
AXEL_TARBALL="axel-${AXEL_VERSION}.tar.xz"
AXEL_DOWNLOADED=false
for mirror in "${AXEL_MIRRORS[@]}"; do
  echo -e "${TAWNY}= trying mirror: ${mirror}${NC}"
  if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
      -o "${AXEL_TARBALL}" "${mirror}"; then
    echo -e "${MINT}= downloaded from: ${mirror}${NC}"
    AXEL_DOWNLOADED=true
    break
  else
    echo -e "${LEMON}= failed: ${mirror}${NC}"
    rm -f "${AXEL_TARBALL}"
  fi
done
if [ "${AXEL_DOWNLOADED}" = false ]; then
  echo -e "${TOMATO}= ERROR: all mirrors failed for axel-${AXEL_VERSION}.tar.xz${NC}"
  exit 1
fi
verify_checksum "${AXEL_TARBALL}" "938ee7c8c478bf6fcc82359bbf9576f298033e8b13908e53e3ea9c45c1443693"

echo -e "${HELIOTROPE}= download alpine rootfs${NC}"
wget -c "${ALPINE_URL}"
verify_checksum "${TARBALL}" "${ALPINE_SHA256}"

echo -e "${MINT}= extract rootfs${NC}"
mkdir -p pasta
tar xf "${TARBALL}" -C pasta/

echo -e "${PEACH}= copy resolv.conf and axel tarball into chroot${NC}"
cp /etc/resolv.conf ./pasta/etc/
cp "${AXEL_TARBALL}" "./pasta/${AXEL_TARBALL}"

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
openssl-dev \
zlib-dev \
libidn2-dev \
libpsl-dev \
libidn2-static \
openssl-libs-static \
zlib-static \
libpsl-static \
libunistring-dev \
libunistring-static \
upx && \
tar xf axel-${AXEL_VERSION}.tar.xz && \
cd axel-${AXEL_VERSION}/ && \
./configure CC=gcc LDFLAGS='-static' PKG_CONFIG='pkg-config --static' CFLAGS='-Os -Wno-unterminated-string-initialization' && \
make -j\$(nproc) && \
strip axel && \
if [ ! -f "axel-${AXEL_VERSION}/axel" ]; then
  echo -e "${TOMATO}Error: axel binary not found after build${NC}" >&2
  exit 1
fi
upx --lzma axel"
mkdir -p dist
cp "./pasta/axel-${AXEL_VERSION}/axel" "dist/axel-${ARCH}"
if command -v file >/dev/null 2>&1; then echo -e "${ORANGE} File Info:  $(file "dist/axel-${ARCH}" | cut -d: -f2-)${NC}"; fi
tar -C dist -cJf "dist/axel-${ARCH}.tar.xz" "axel-${ARCH}"
echo -e "${LEMON}= All done! Binary: dist/axel-${ARCH} ($(du -sh "dist/axel-${ARCH}" | cut -f1))${NC}"