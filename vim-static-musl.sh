#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

VIM_VERSION="9.2.0119"
PACKAGE_VERSION="${VIM_VERSION}"
VIM_TARBALL="vim-${VIM_VERSION}.tar.gz"
VIM_MIRRORS=(
  "https://github.com/vim/vim/archive/v${VIM_VERSION}/vim-${VIM_VERSION}.tar.gz"
  "https://fossies.org/linux/misc/vim-${VIM_VERSION}.tar.gz"
)

setup_arch
setup_cleanup
install_host_deps
download_source "vim" "${VIM_VERSION}" "${VIM_TARBALL}" "${VIM_MIRRORS[@]}"
setup_alpine_chroot "${VIM_TARBALL}"
setup_qemu
mount_chroot

sudo chroot ./pasta/ /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
sed \
make \
gcc \
pkgconfig \
ncurses-dev \
ncurses-static \
python3-dev \
perl-dev \
perl && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR:-/ccache} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf ${VIM_TARBALL} && \
cd vim-${VIM_VERSION}/ && \
sed -i 's#emsg(_(e_failed_to_source_defaults));#(void)0;#g' src/main.c && \
./configure CC='gcc' \
  --disable-channel --disable-gpm --disable-gtktest --disable-gui \
  --disable-netbeans --disable-nls --disable-selinux --disable-smack \
  --disable-sysmouse --disable-xsmp \
  --enable-multibyte \
  --with-features=huge --with-tlib=ncursesw --without-x \
  LDFLAGS='-static' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -static -fno-stack-protector -no-pie' && \
CC='gcc' make -j\$(nproc) && \
strip src/vim && \
../upx --ultra-brute src/vim"

package_output "vim" "./pasta/vim-${VIM_VERSION}/src/vim"
