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
GIT_VERSION="2.53.0"
ALPINE_VERSION="3.23.3"
ALPINE_MAJOR_MINOR="${ALPINE_VERSION%.*}"

GIT_MIRRORS=(
  "https://www.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.xz"
  "https://mirrors.slackware.com/slackware/slackware-current/source/d/git/git-2.53.0.tar.xz"
  "https://fossies.org/linux/misc/git-2.53.0.tar.xz"
  "https://mirrors.omnios.org/git/git-2.53.0.tar.xz"
  "https://source.ipfire.org/source-2.x/git-2.53.0.tar.xz"
  "https://ftp2.osuosl.org/pub/blfs/conglomeration/git/git-2.53.0.tar.xz"
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

echo -e "${AQUA}= downloading git-${GIT_VERSION} tarball${NC}"
GIT_TARBALL="git-${GIT_VERSION}.tar.xz"
GIT_DOWNLOADED=false
for mirror in "${GIT_MIRRORS[@]}"; do
  echo -e "${TAWNY}= trying mirror: ${mirror}${NC}"
  if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
      -o "${GIT_TARBALL}" "${mirror}"; then
    echo -e "${MINT}= downloaded from: ${mirror}${NC}"
    GIT_DOWNLOADED=true
    break
  else
    echo -e "${LEMON}= failed: ${mirror}${NC}"
    rm -f "${GIT_TARBALL}"
  fi
done
if [ "${GIT_DOWNLOADED}" = false ]; then
  echo -e "${TOMATO}= ERROR: all mirrors failed for git-${GIT_VERSION}.tar.xz${NC}"
  exit 1
fi

echo -e "${HELIOTROPE}= download alpine rootfs${NC}"
wget -c "${ALPINE_URL}"

echo -e "${MINT}= extract rootfs${NC}"
mkdir -p pasta
tar xf "${TARBALL}" -C pasta/
echo -e "${PEACH}= copy resolv.conf and git tarball into chroot${NC}"
cp /etc/resolv.conf ./pasta/etc/
cp "${GIT_TARBALL}" "./pasta/${GIT_TARBALL}"

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
curl-dev \
curl-static \
openssl-dev \
openssl-libs-static \
zstd-dev \
zstd-static \
perl \
zlib-dev \
zlib-static \
expat-dev \
expat-static \
upx && \
tar xf git-${GIT_VERSION}.tar.xz && \
cd git-${GIT_VERSION}/ && \
mkdir -p output/ && \
./configure CC=clang --without-tcltk --with-curl --with-openssl \
  --with-expat --sysconfdir=/etc --with-editor=nano --prefix=output/ \
  LDFLAGS='-static -Wl,--gc-sections -lcurl' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -ffunction-sections -fdata-sections -Wno-unterminated-string-initialization' && \
CC=clang make NO_PERL=1 RUNTIME_PREFIX=1 -j\$(nproc) && \
strip output/git && \
upx --lzma output/git"
mkdir -p dist
cp "./pasta/git-${GIT_VERSION}/git" "dist/git-${ARCH}"
if command -v file >/dev/null 2>&1; then echo -e "${ORANGE} File Info:  $(file "dist/git-${ARCH}" | cut -d: -f2-)${NC}"; fi
tar -C dist -cJf "dist/git-${ARCH}.tar.xz" "git-${ARCH}"
echo -e "${LEMON}= All done! Binary: dist/git-${ARCH} ($(du -sh "dist/git-${ARCH}" | cut -f1))${NC}"
