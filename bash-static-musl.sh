#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

BASH_VERSION="5.3"
BASH_TARBALL="bash-${BASH_VERSION}.tar.gz"
BASH_PATCH_PREFIX="bash${BASH_VERSION//./}"
BASH_PATCH_URL="https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}-patches/"
BASH_PATCH_PROBE_MAX=120
BASH_MIRRORS=(
  "https://ftp.gnu.org/gnu/bash/${BASH_TARBALL}"
  "https://mirrors.ocf.berkeley.edu/gnu/bash/${BASH_TARBALL}"
  "https://mirror.rackspace.com/gnu/bash/${BASH_TARBALL}"
  "https://ftpmirror.gnu.org/bash/${BASH_TARBALL}"
)

BASH_OFFICIAL_PATCHES=()

fetch_bash_patches() {
  echo -e "${AQUA}= fetching upstream bash ${BASH_VERSION} patches${NC}"
  local listing
  listing=$(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 30 "${BASH_PATCH_URL}")
  mapfile -t BASH_OFFICIAL_PATCHES < <(echo "${listing}" | grep -oE "${BASH_PATCH_PREFIX}-[0-9]{3}" | sort -u)
  if [ ${#BASH_OFFICIAL_PATCHES[@]} -eq 0 ]; then
    echo -e "${LEMON}= directory listing empty, probing sequential patches${NC}"
    local candidate
    for num in $(seq -w 1 "${BASH_PATCH_PROBE_MAX}"); do
      candidate="${BASH_PATCH_PREFIX}-${num}"
      if curl -sfI --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 30 "${BASH_PATCH_URL}${candidate}" >/dev/null; then
        BASH_OFFICIAL_PATCHES+=("${candidate}")
      else
        break
      fi
    done
  fi
  if [ ${#BASH_OFFICIAL_PATCHES[@]} -eq 0 ]; then
    echo -e "${LEMON}= no upstream patches found for bash ${BASH_VERSION}${NC}"
    return 0
  fi
  if [ ${#BASH_OFFICIAL_PATCHES[@]} -gt 1 ]; then
    mapfile -t BASH_OFFICIAL_PATCHES < <(printf '%s\n' "${BASH_OFFICIAL_PATCHES[@]}" | sort -u)
  fi
  for patch_file in "${BASH_OFFICIAL_PATCHES[@]}"; do
    if [ -f "${patch_file}" ]; then
      echo -e "${SLATE}= ${patch_file} already cached, skipping download${NC}"
      continue
    fi
    echo -e "${TAWNY}= downloading ${patch_file}${NC}"
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 \
      -o "${patch_file}" "${BASH_PATCH_URL}${patch_file}"
  done
}

setup_arch
setup_cleanup
install_host_deps
download_source "bash" "${BASH_VERSION}" "${BASH_TARBALL}" "${BASH_MIRRORS[@]}"
fetch_bash_patches
setup_alpine_chroot "${BASH_TARBALL}"
copy_patches "bash-5.3.patch"

if [ ${#BASH_OFFICIAL_PATCHES[@]} -gt 0 ]; then
  cp "${BASH_OFFICIAL_PATCHES[@]}" ./pasta/
fi

PATCH_SERIES="${BASH_OFFICIAL_PATCHES[*]:-}"

setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
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
texinfo && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf ${BASH_TARBALL} && \
cd bash-${BASH_VERSION}/ && \
for patch in ${PATCH_SERIES}; do patch -p0 < /${patch}; done && \
patch -p1 --fuzz=4 < ../bash-5.3.patch && \
./configure \
  --enable-static-link \
  --without-bash-malloc \
  --disable-nls \
  --prefix=/usr \
  LDFLAGS='-static' \
  PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -fomit-frame-pointer' && \
make -j\$(nproc) && \
strip bash && \
../upx --lzma bash"

package_output "bash" "./pasta/bash-${BASH_VERSION}/bash"
