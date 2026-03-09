#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

BASH_VERSION="5.3"
PACKAGE_VERSION="${BASH_VERSION}"
BASH_TARBALL="bash-${BASH_VERSION}.tar.gz"
IFS='.' read -r bash_major bash_minor _ <<< "${BASH_VERSION}"
BASH_MAJOR_MINOR="${bash_major}${bash_minor}"
BASH_PATCH_DIR="bash-${BASH_VERSION}-patches"
BASH_PATCH_PREFIX="bash${BASH_MAJOR_MINOR}-"
BASH_PATCH_URL="https://ftp.gnu.org/gnu/bash/${BASH_PATCH_DIR}/"
CHROOT_DIR="./pasta"
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
  local patch_index
  if ! patch_index=$(curl -fsSL "${BASH_PATCH_URL}"); then
    echo -e "${TOMATO}= ERROR: failed to fetch patch index from ${BASH_PATCH_URL}${NC}"
    exit 1
  fi
  BASH_PATCH_FILES=()
  mapfile -t BASH_PATCH_FILES < <(
    # GNU bash patches currently use three-digit numbering (bash53-001, ...). The pattern accepts any digit length in case upstream increases the count.
    printf '%s\n' "${patch_index}" | sed -n "s/.*href=\"\(${BASH_PATCH_PREFIX}[0-9]\+\)\".*/\1/p" | sort -V
  )
  if [ "${#BASH_PATCH_FILES[@]}" -eq 0 ]; then
    echo -e "${TOMATO}= ERROR: no upstream patches found at ${BASH_PATCH_URL}${NC}"
    exit 1
  fi
  local dest
  for patch in "${BASH_PATCH_FILES[@]}"; do
    dest="${BASH_PATCH_DIR}/${patch}"
    if [ -f "${dest}" ]; then
      echo -e "${SLATE}= ${patch} already downloaded${NC}"
      continue
    fi
    if ! curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
      -o "${dest}" "${BASH_PATCH_URL}${patch}"; then
      echo -e "${TOMATO}= ERROR: failed to download ${patch} from ${BASH_PATCH_URL}${NC}"
      exit 1
    fi
  done
  for patch in "${BASH_PATCH_FILES[@]}"; do
    if [ ! -s "${BASH_PATCH_DIR}/${patch}" ]; then
      echo -e "${TOMATO}= ERROR: patch file missing after download: ${patch}${NC}"
      exit 1
    fi
  done
  printf '%s\n' "${BASH_PATCH_FILES[@]}" > "${BASH_PATCH_DIR}/.patch-list"
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

sudo chroot "${CHROOT_DIR}/" /bin/sh -s <<EOF
set -e
apk update
apk add build-base musl-dev ccache sed make gcc automake autoconf pkgconfig ncurses-dev ncurses-static python3-dev perl-dev perl gettext-dev gettext-static readline readline-static
mkdir -p /ccache
export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH
chmod 755 upx
tar xf ${BASH_TARBALL}
cd bash-${BASH_VERSION}/
while read -r patch; do
  echo -e "${NAVAJO}= applying \$patch${NC}"
  patch -p0 < ../${BASH_PATCH_DIR}/"\$patch"
done < ../${BASH_PATCH_DIR}/.patch-list
echo -e "${BOYSENBERRY}= applying bash-5.3_my.patch${NC}"
patch -p1 --fuzz=4 < ../bash-5.3_my.patch
./configure CC='gcc' \
  --disable-nls --without-bash-malloc --with-curses --enable-static-link \
  LDFLAGS='-static -Wl,--gc-sections' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector -no-pie'
CC='gcc' make -j\$(nproc)
strip bash
../upx --ultra-brute bash
EOF

package_output "bash" "${CHROOT_DIR}/bash-${BASH_VERSION}/bash"
