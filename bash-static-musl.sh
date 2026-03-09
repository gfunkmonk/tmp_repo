#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

BASH_VERSION="5.3"
BASH_TARBALL="bash-${BASH_VERSION}.tar.gz"
BASH_PATCH_DIR="bash-${BASH_VERSION}-patches"
BASH_PATCH_PREFIX="bash${BASH_VERSION/./}-"
BASH_PATCH_URL="https://ftp.gnu.org/gnu/bash/${BASH_PATCH_DIR}/"
BASH_MIRRORS=(
  "https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz"
  "https://mirrors.ocf.berkeley.edu/gnu/bash/bash-${BASH_VERSION}.tar.gz"
  "https://mirrors.kernel.org/gnu/bash/bash-${BASH_VERSION}.tar.gz"
  "https://mirrors.ibiblio.org/pub/mirrors/gnu/bash/bash-${BASH_VERSION}.tar.gz"
  "https://mirror.us-midwest-1.nexcess.net/gnu/bash/bash-${BASH_VERSION}.tar.gz"

)

download_bash_upstream_patches() {
  echo -e "${AQUA}= download bash ${BASH_VERSION} upstream patches${NC}"
  mkdir -p "${BASH_PATCH_DIR}"
  mapfile -t bash_patch_files < <(
    curl -fsSL "${BASH_PATCH_URL}" | grep -Eo "${BASH_PATCH_PREFIX}[0-9]{3}" | sort -u || true
  )
  if [ "${#bash_patch_files[@]}" -eq 0 ]; then
    echo -e "${TOMATO}= ERROR: no upstream patches found at ${BASH_PATCH_URL}${NC}"
    exit 1
  fi
  for patch in "${bash_patch_files[@]}"; do
    local dest="${BASH_PATCH_DIR}/${patch}"
    if [ -f "${dest}" ]; then
      echo -e "${SLATE}= ${patch} already downloaded${NC}"
      continue
    fi
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
      -o "${dest}" "${BASH_PATCH_URL}${patch}"
  done
}

setup_arch
setup_cleanup
install_host_deps
download_source "bash" "${BASH_VERSION}" "${BASH_TARBALL}" "${BASH_MIRRORS[@]}"
download_bash_upstream_patches
setup_alpine_chroot "${BASH_TARBALL}"
cp -r "${BASH_PATCH_DIR}" ./pasta/
copy_patches "bash-5.3_my.patch"
setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
sed \
make \
gcc \
automake \
autoconf \
pkgconfig \
libtool \
bison \
flex \
patch \
texinfo \
ncurses-dev \
ncurses-static \
python3-dev \
perl-dev \
perl \
gettext-dev \
gettext-static \
readline \
readline-static && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf ${BASH_TARBALL} && \
cd bash-${BASH_VERSION}/ && \
for patch in ../${BASH_PATCH_DIR}/${BASH_PATCH_PREFIX}*; do patch -p0 < "${patch}"; done && \
patch -p1 --fuzz=4 < ../bash-5.3_my.patch && \
./configure CC='gcc' \
  --disable-nls --without-bash-malloc --with-curses --enable-static-link \
  LDFLAGS='-static -Wl,--gc-sections' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector -no-pie' && \
CC='gcc' make -j\$(nproc) && \
strip bash && \
../upx --ultra-brute bash"

package_output "bash" "./pasta/bash-${BASH_VERSION}/bash"
