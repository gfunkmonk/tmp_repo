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
ALPINE_VERSION="3.23.3"
ALPINE_MAJOR_MINOR="${ALPINE_VERSION%.*}"

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
ARIA2_VERSION=$(curl -fsSL --connect-timeout 10 --max-time 30 \
  "https://api.github.com/repos/aria2/aria2/releases/latest" \
  | grep '"tag_name"' | sed 's/.*"release-\([^"]*\)".*/\1/') || true
if [ -z "${ARIA2_VERSION}" ]; then
  echo -e "${TAWNY}= GitHub API unavailable, falling back to aria2 1.37.0${NC}"
  ARIA2_VERSION="1.37.0"
fi
echo -e "${MINT}= building aria2 version: ${ARIA2_VERSION}${NC}"

ARIA2_MIRRORS=(
  "https://github.com/aria2/aria2/releases/download/release-${ARIA2_VERSION}/aria2-${ARIA2_VERSION}.tar.gz"
  "https://distfiles.alpinelinux.org/distfiles/v3.21/aria2-${ARIA2_VERSION}.tar.gz"
  "https://sources.voidlinux.org/aria2-${ARIA2_VERSION}/aria2-${ARIA2_VERSION}.tar.gz"
  "https://mirrors.lug.mtu.edu/gentoo/distfiles/aria2-${ARIA2_VERSION}.tar.gz"
)

echo -e "${AQUA}= downloading aria2-${ARIA2_VERSION} tarball${NC}"
ARIA2_TARBALL="aria2-${ARIA2_VERSION}.tar.gz"
ARIA2_DOWNLOADED=false
for mirror in "${ARIA2_MIRRORS[@]}"; do
  echo -e "${TAWNY}= trying mirror: ${mirror}${NC}"
  if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
      -o "${ARIA2_TARBALL}" "${mirror}"; then
    echo -e "${MINT}= downloaded from: ${mirror}${NC}"
    ARIA2_DOWNLOADED=true
    break
  else
    echo -e "${LEMON}= failed: ${mirror}${NC}"
    rm -f "${ARIA2_TARBALL}"
  fi
done
if [ "${ARIA2_DOWNLOADED}" = false ]; then
  echo -e "${TOMATO}= ERROR: all mirrors failed for aria2-${ARIA2_VERSION}.tar.gz${NC}"
  exit 1
fi

ARIA2_KNOWN_SHA256_1_37_0="8e7021c6d5e8f8240c9cc19482e0c8589540836747744724d86bf8af5a21f0e8"
if [ "${ARIA2_VERSION}" = "1.37.0" ]; then
  verify_checksum "${ARIA2_TARBALL}" "${ARIA2_KNOWN_SHA256_1_37_0}"
else
  echo -e "${TOMATO}= ERROR: no hardcoded checksum for aria2-${ARIA2_VERSION}, cannot verify integrity${NC}"
  exit 1
fi

echo -e "${AQUA}= downloading patch for aria2${NC}"
ARIA2_PATCH_URL="https://github.com/gfunkmonk/aria2c-static-musl/raw/refs/heads/main/aria2-1.37.0.conf.patch"
ARIA2_PATCH_SHA256="e65836beefe8c1f07a75ce1b663a45c36678106dba9cc9876ee23d72f15ba2c4"
if ! curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 30 \
    -o aria2-1.37.0.conf.patch \
    "${ARIA2_PATCH_URL}"; then
  echo -e "${TOMATO}= ERROR: failed to download patch from ${ARIA2_PATCH_URL}${NC}"
  exit 1
fi
verify_checksum "aria2-1.37.0.conf.patch" "${ARIA2_PATCH_SHA256}"

echo -e "${HELIOTROPE}= download alpine rootfs${NC}"
wget -c "${ALPINE_URL}"
verify_checksum "${TARBALL}" "${ALPINE_SHA256}"

echo -e "${MINT}= extract rootfs${NC}"
mkdir -p pasta
tar xf "${TARBALL}" -C pasta/

echo -e "${PEACH}= copy resolv.conf, tarball and patch into chroot${NC}"
cp /etc/resolv.conf ./pasta/etc/
cp "${ARIA2_TARBALL}" "./pasta/${ARIA2_TARBALL}"
cp aria2-1.37.0.conf.patch ./pasta/aria2-1.37.0.conf.patch

if [ -n "${QEMU_ARCH}" ]; then
  echo -e "${TAWNY}= setup QEMU for cross-arch builds${NC}"
  sudo mkdir -p "./pasta/usr/bin/"
  sudo cp "/usr/bin/qemu-${QEMU_ARCH}-static" "./pasta/usr/bin/"
fi

echo -e "${VIOLET}= mount, bind and chroot into dir${NC}"
sudo mount -t proc none ./pasta/proc/
sudo mount --rbind /dev ./pasta/dev/
sudo mount --rbind /sys ./pasta/sys/
sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
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
upx && \
tar xf aria2-${ARIA2_VERSION}.tar.gz && \
cd aria2-${ARIA2_VERSION}/ && \
patch -p1 < ../aria2-1.37.0.conf.patch && \
./configure CC=gcc ARIA2_STATIC=yes \
  --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
  --without-gnutls --with-openssl \
  --disable-bittorrent \
  --with-libcares --with-sqlite3 \
  --enable-shared=no --enable-static --disable-shared \
  LDFLAGS='-static' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -Wno-unterminated-string-initialization' && \
make -j\$(nproc) && \
strip src/aria2c && \
if [ ! -f "aria2-${ARIA2_VERSION}/src/aria2c" ]; then
  echo -e "${TOMATO}Error: aria2c binary not found after build${NC}" >&2
  exit 1
fi
upx --lzma src/aria2c"
mkdir -p dist
cp "./pasta/aria2-${ARIA2_VERSION}/src/aria2c" "dist/aria2c-${ARCH}"
if command -v file >/dev/null 2>&1; then echo -e "${ORANGE} File Info:  $(file "dist/aria2c-${ARCH}" | cut -d: -f2-)${NC}"; fi
tar -C dist -cJf "dist/aria2c-${ARCH}.tar.xz" "aria2c-${ARCH}"
echo -e "${LEMON}= All done! Binary: dist/aria2c-${ARCH} ($(du -sh "dist/aria2c-${ARCH}" | cut -f1))${NC}"