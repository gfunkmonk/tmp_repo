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
NC="\033[0m"

ARCH=${ARCH:-x86_64}
VIM_VERSION="9.2.0119"
ALPINE_VERSION="3.23.3"
ALPINE_MAJOR_MINOR="${ALPINE_VERSION%.*}"

VIM_MIRRORS=(
  "https://github.com/vim/vim/archive/v${VIM_VERSION}/vim-${VIM_VERSION}.tar.gz"
  "https://fossies.org/linux/misc/vim-${VIM_VERSION}.tar.gz"
  "http://vim.lyn.dk/vim-${VIM_VERSION}.tar.bz2"
)

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

echo -e "${AQUA}= downloading vim-${VIM_VERSION} tarball${NC}"
VIM_TARBALL="vim-${VIM_VERSION}.tar.gz"
VIM_DOWNLOADED=false
for mirror in "${VIM_MIRRORS[@]}"; do
  echo -e "${TAWNY}= trying mirror: ${mirror}${NC}"
  if curl -fsSL --retry 3 --retry-delay 2 -o "${VIM_TARBALL}" "${mirror}"; then
    echo -e "${MINT}= downloaded from: ${mirror}${NC}"
    VIM_DOWNLOADED=true
    break
  else
    echo -e "${LEMON}= failed: ${mirror}${NC}"
    rm -f "${VIM_TARBALL}"
  fi
done
if [ "${VIM_DOWNLOADED}" = false ]; then
  echo -e "${TOMATO}= ERROR: all mirrors failed for vim-${VIM_VERSION}.tar.gz${NC}"
  exit 1
fi

echo -e "${HELIOTROPE}= download alpine rootfs${NC}"
wget -c "${ALPINE_URL}"

echo -e "${MINT}= extract rootfs${NC}"
mkdir -p pasta
tar xf "${TARBALL}" -C pasta/
echo -e "${PEACH}= copy resolv.conf and vim tarball into chroot${NC}"
cp /etc/resolv.conf ./pasta/etc/
cp "${VIM_TARBALL}" "./pasta/${VIM_TARBALL}"

echo -e "${TAWNY}= setup QEMU for cross-arch builds${NC}"
if [ -n "${QEMU_ARCH}" ]; then
  sudo mkdir -p "./pasta/usr/bin/"
  sudo cp "/usr/bin/qemu-${QEMU_ARCH}-static" "./pasta/usr/bin/"
fi

echo -e "${VIOLET}= mount, bind and chroot into dir${NC}"
sudo mount -t proc none "./pasta/proc/"
sudo mount --rbind /dev "./pasta/dev/"
sudo mount --rbind /sys "./pasta/sys/"
sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
sed \
wget \
make \
gcc \
automake \
libtool \
bison \
flex \
pkgconfig \
ncurses-dev \
ncurses-static \
autoconf \
patch \
upx \
python3-dev \
perl-dev \
perl && \
tar xf vim-${VIM_VERSION}.tar.gz && \
cd vim-${VIM_VERSION}/ && \
sed -i 's#emsg(_(e_failed_to_source_defaults));#(void)0;#g' src/main.c && \
./configure CC='gcc' --disable-channel --disable-gpm --disable-gtktest --disable-gui --disable-netbeans --disable-nls --disable-selinux --disable-smack --disable-sysmouse --disable-xsmp --enable-multibyte --with-features=huge --with-tlib=ncursesw --without-x LDFLAGS='-static' CFLAGS='-Os -static -fno-stack-protector -no-pie' && \
CC='gcc' make -j\$(nproc) && \
strip src/vim && \
upx --ultra-brute src/vim"
mkdir -p dist
cp "./pasta/vim-${VIM_VERSION}/src/vim" "dist/vim-${ARCH}"
if command -v file >/dev/null 2>&1; then echo -e "${ORANGE} File Info:  $(file "dist/vim-${ARCH}" | cut -d: -f2-)${NC}"; fi
tar -C dist -cJf "dist/vim-${ARCH}.tar.xz" "vim-${ARCH}"
echo -e "${LEMON}= All done!${NC}"
