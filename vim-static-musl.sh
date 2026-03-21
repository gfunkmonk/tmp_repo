#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

setup_tools

echo -e "${VIOLET}= fetching latest vim version${NC}"
VIM_VERSION=$(gh_latest_tag "vim/vim" '.[0].name | ltrimstr("v")') || true
if [ -z "${VIM_VERSION}" ]; then
  echo -e "${TAWNY}= GitHub API unavailable, falling back to vim 9.2.0119${NC}"
  VIM_VERSION="9.2.0119"
fi

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
copy_patches "vim.patch"
setup_qemu
mount_chroot

sudo chroot "./${CHROOTDIR}/" /bin/sh -c "set -e && apk update && apk add build-base \
musl-dev \
ccache \
sed \
patch \
pkgconfig \
ncurses-dev \
ncurses-static && \
mkdir -p /ccache && export CCACHE_DIR=${CCACHE_CHROOT_DIR} CCACHE_BASEDIR=/ PATH=/usr/lib/ccache/bin:\$PATH && \
chmod 755 upx && \
tar xf ${VIM_TARBALL} && \
cd vim-${VIM_VERSION}/ && \
patch -p1 --fuzz=4 < ../vim.patch && \
sed -i 's#emsg(_(e_failed_to_source_defaults));#(void)0;#g' src/main.c && \
./configure CC='gcc' \
  --disable-channel --disable-gpm --disable-gtktest --disable-gui \
  --disable-netbeans --disable-nls --disable-selinux --disable-smack \
  --disable-sysmouse --disable-xsmp \
  --enable-multibyte \
  --with-features=huge --with-tlib=ncursesw --without-x \
  LDFLAGS='-static -Wl,--gc-sections' PKG_CONFIG='pkg-config --static' \
  CFLAGS='-Os -static -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-stack-protector -no-pie' && \
CC='gcc' make -j\$(nproc) && \
strip src/vim && \
../upx --ultra-brute src/vim"

package_output "vim" "./${CHROOTDIR}/vim-${VIM_VERSION}/src/vim"
