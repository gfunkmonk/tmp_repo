#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

echo -e "${VIOLET}= fetching latest 7zip version${NC}"
SEVENZIP_VERSION=$(curl -fsSL "https://api.github.com/repos/mcmilk/7-Zip-zstd/releases/latest" \
  | grep '"tag_name"' | sed 's/  "tag_name": "//g' | sed 's/",//g') || true
if [ -z "${SEVENZIP_VERSION}" ]; then
  echo -e "${TAWNY}= GitHub API unavailable, falling back to 7zip v25.01-v1.5.7-R4${NC}"
  SEVENZIP_VERSION="v25.01-v1.5.7-R4"
fi

PACKAGE_VERSION="${SEVENZIP_VERSION}"
SEVENZIP_SHORT="$(echo "${SEVENZIP_VERSION}" | sed 's/v2/2/g')"
SEVENZIP_TARBALL="7-Zip-zstd-${SEVENZIP_VERSION}.tar.gz"
SEVENZIP_MIRRORS=(
  "https://github.com/mcmilk/7-Zip-zstd/archive/refs/tags/${SEVENZIP_VERSION}.tar.gz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "7zip" "${SEVENZIP_VERSION}" "${SEVENZIP_TARBALL}" "${SEVENZIP_MIRRORS[@]}"
setup_alpine_chroot "${SEVENZIP_TARBALL}"
copy_patches "7z-0003-Disable-local-echo-display-when-in-input-passwords-C.patch" "7z-0004-Use-system-locale-to-select-codepage-for-legacy-zip-.patch" "7z-0005-Fix-BROTLI_MODEL-attribute-for-loongarch64.patch"
setup_qemu
mount_chroot

# Map repo ARCH to 7zip Linux makefile; source extracts flat so we wrap in a versioned dir
case "${ARCH}" in
  x86_64)  MAKE_OPTS="MY_ASM=/usr/bin/uasm -f ../../cmpl_gcc.mak 7z_asm=uasm";;
  x86)     MAKE_OPTS="MY_ASM=/usr/bin/uasm -f ../../cmpl_gcc.mak 7z_asm=uasm";;
  aarch64) MAKE_OPTS="-f ../../cmpl_gcc_arm64.mak";;
  armv7)   MAKE_OPTS="-f ../../cmpl_gcc_arm.mak";;
esac

echo $MAKE_OPTS >> ./pasta/make_opts

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
gcc \
g++ \
patch \
upx \
git \
nasm \
make && \
apk add uasm --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
export MAKE_OPTS=$(cat make_opts) && \
tar xf ${SEVENZIP_TARBALL} && \
cd 7-Zip-zstd-${SEVENZIP_SHORT}/ && \
patch -p1 --fuzz=4 < ../7z-0003-Disable-local-echo-display-when-in-input-passwords-C.patch && \
patch -p1 --fuzz=4 < ../7z-0004-Use-system-locale-to-select-codepage-for-legacy-zip-.patch && \
patch -p1 --fuzz=4 < ../7z-0005-Fix-BROTLI_MODEL-attribute-for-loongarch64.patch && \
cd CPP/7zip/Bundles/Alone2 && \
mkdir -p b/g && \
make -j\$(nproc) CFLAGS_BASE_LIST='-c -D_7ZIP_AFFINITY_DISABLE=1 -DZ7_AFFINITY_DISABLE=1 -D_GNU_SOURCE=1' CFLAGS_WARN_WALL='-Wall -Wextra' COMPL_STATIC=1 $MAKE_OPTS && \
strip b/g/7zzs && \
cp b/g/7zzs /7-Zip-zstd-${SEVENZIP_SHORT}/7zz && \
/upx --lzma /7-Zip-zstd-${SEVENZIP_SHORT}/7zz"

package_output "7zip" "./pasta/7-Zip-zstd-${SEVENZIP_SHORT}/7zz"
