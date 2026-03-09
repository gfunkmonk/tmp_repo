#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

BASH_VERSION="5.3"
BASH_TARBALL="bash-${BASH_VERSION}.tar.gz"
BASH_MIRRORS=(
  "https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz"
  "https://mirrors.ocf.berkeley.edu/gnu/bash/bash-${BASH_VERSION}.tar.gz"
  "https://mirrors.kernel.org/gnu/bash/bash-${BASH_VERSION}.tar.gz"
  "https://mirrors.ibiblio.org/pub/mirrors/gnu/bash/bash-${BASH_VERSION}.tar.gz"
  "https://mirror.us-midwest-1.nexcess.net/gnu/bash/bash-${BASH_VERSION}.tar.gz"

)

setup_arch
setup_cleanup
install_host_deps
download_source "bash" "${BASH_VERSION}" "${BASH_TARBALL}" "${BASH_MIRRORS[@]}"
setup_alpine_chroot "${BASH_TARBALL}"
copy_patches "bash-5.3.patch"
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
patch -p1 --fuzz=4 < ../bash-5.3.patch && \
./configure CC='gcc' \
  --disable-nls --without-bash-malloc --with-curses \
  LDFLAGS='-static -Wl,--gc-sections' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector -no-pie' && \
CC='gcc' make -j\$(nproc) && \
strip bash && \
../upx --ultra-brute bash"

package_output "bash" "./pasta/bash-${BASH_VERSION}/bash"
