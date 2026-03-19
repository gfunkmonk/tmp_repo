#!/bin/bash
# common.sh - Shared functions and variables for all *-static-musl.sh scripts.
# Source this file at the top of each build script: . "$(dirname "$0")/common.sh"

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
SLATE="\033[38;2;109;129;150m"
SKY="\033[38;2;135;206;250m"
JUNEBUD="\033[38;2;189;218;87m"
NAVAJO="\033[38;2;255;222;173m"
BOYSENBERRY="\033[38;2;135;50;96m"
NC="\033[0m"

ARCH=${ARCH:-x86_64}
ALPINE_VERSION="3.23.3"
ALPINE_MAJOR_MINOR="${ALPINE_VERSION%.*}"

# setup_arch: resolve QEMU_ARCH, ALPINE_URL, and TARBALL from ARCH
setup_arch() {
  case "${ARCH}" in
    x86_64)  QEMU_ARCH="" ;;
    x86)     QEMU_ARCH="i386" ;;
    aarch64) QEMU_ARCH="aarch64" ;;
    armv7)   QEMU_ARCH="arm" ;;
    *)
      echo -e "${LAGOON}Unknown architecture: ${HOTPINK}${ARCH}${NC}"
      exit 1
      ;;
  esac
  ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MAJOR_MINOR}/releases/${ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"
  TARBALL="${ALPINE_URL##*/}"
}

# setup_cleanup: register unmount trap for chroot bind mounts
setup_cleanup() {
  cleanup() {
    sudo umount -lf "./pasta/proc" 2>/dev/null || true
    sudo umount -lf "./pasta/dev/pts"  2>/dev/null || true
    sudo umount -lf "./pasta/dev"  2>/dev/null || true
    sudo umount -lf "./pasta/sys"  2>/dev/null || true
    sudo umount -lf "./pasta/sys"  2>/dev/null || true
	  }
  trap cleanup EXIT
}

# install_host_deps: install required packages on the Ubuntu runner
install_host_deps() {
  echo -e "${AQUA}= install dependencies${NC}"
  local DEBIAN_DEPS=(wget curl binutils)
  [ -n "${QEMU_ARCH}" ] && DEBIAN_DEPS+=(qemu-user-static)
  sudo apt-get update -qy && sudo apt-get install -y "${DEBIAN_DEPS[@]}"
}

# download_source LABEL VERSION TARBALL mirror1 [mirror2 ...]
# Downloads TARBALL from the first mirror that succeeds.
# Skips the download if TARBALL already exists (e.g. restored from cache).
download_source() {
  local label="$1" version="$2" tarball="$3"
  shift 3
  if [ -f "${tarball}" ]; then
    echo -e "${SLATE}= ${label}-${version}: ${tarball} already cached, skipping download${NC}"
    return 0
  fi
  echo -e "${AQUA}= downloading ${label}-${version} tarball${NC}"
  local downloaded=false
  for mirror in "$@"; do
    echo -e "${TAWNY}= trying mirror: ${mirror}${NC}"
    if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
        -o "${tarball}" "${mirror}"; then
      echo -e "${MINT}= downloaded from: ${mirror}${NC}"
      downloaded=true
      break
    else
      echo -e "${LEMON}= failed: ${mirror}${NC}"
      rm -f "${tarball}"
    fi
  done
  if [ "${downloaded}" = false ]; then
    echo -e "${TOMATO}= ERROR: all mirrors failed for ${tarball}${NC}"
    exit 1
  fi
}

# setup_alpine_chroot TARBALL
# Downloads Alpine rootfs, extracts it, and copies resolv.conf + source tarball inside.
setup_alpine_chroot() {
  local tarball="$1"
  echo -e "${HELIOTROPE}= download alpine rootfs${NC}"
  wget -c "${ALPINE_URL}"
  echo -e "${SKY}= extract rootfs${NC}"
  mkdir -p pasta
  tar xf "${TARBALL}" -C pasta/
  echo -e "${PEACH}= copy resolv.conf and ${tarball} into chroot${NC}"
  cp /etc/resolv.conf ./pasta/etc/
  cp "${tarball}" "./pasta/${tarball}"
  if [[ ! -f "tools/upx/upx-${ARCH}" ]]; then
      echo -e "${TOMATO}= ERROR: tools/upx/upx-${ARCH} not found${NC}"
      exit 1
  else
      cp "tools/upx/upx-${ARCH}" "./pasta/upx"
  fi

}

# copy_patches patch1 [patch2 ...]
# Copies named patch files from the local patches/ directory into the chroot root.
copy_patches() {
  for patch in "$@"; do
    if [ ! -f "patches/${patch}" ]; then
      echo -e "${TOMATO}= ERROR: patch file not found: patches/${patch}${NC}"
      exit 1
    fi
    cp "patches/${patch}" "./pasta/${patch}"
  done
}

# setup_qemu: copy qemu static binary into chroot for cross-arch builds
setup_qemu() {
  if [ -n "${QEMU_ARCH}" ]; then
    echo -e "${OCHRE}= setup QEMU for cross-arch builds${NC}"
    sudo mkdir -p "./pasta/usr/bin/"
    sudo cp "/usr/bin/qemu-${QEMU_ARCH}-static" "./pasta/usr/bin/"
  fi
}

# mount_chroot: bind-mount proc/dev/sys into the chroot directory
mount_chroot() {
  echo -e "${VIOLET}= mount, bind and chroot into dir${NC}"
  sudo mount -t proc none "./pasta/proc/"
  sudo mount --rbind /dev "./pasta/dev/"
  sudo mount -t devpts devpts "./pasta/dev/pts" -o nosuid,noexec
  #sudo mount --rbind /dev/pts "./pasta/dev/pts"
  #sudo mount -t sysfs sys "./pasta/sys/"
  sudo mount --rbind /sys "./pasta/sys/"
}

# package_output TOOL BINARY
# Copies the built binary to dist/, creates a tar.xz archive, and prints info.
package_output() {
  local tool="$1" binary="$2"
  local version_suffix=""
  if [ -n "${PACKAGE_VERSION:-}" ]; then
    version_suffix="-${PACKAGE_VERSION}"
  fi
  local filename="${tool}${version_suffix}-${ARCH}"
  mkdir -p dist
  cp "${binary}" "dist/${filename}"
  if command -v file >/dev/null 2>&1; then
    echo -e "${ORANGE} File Info:  $(file "dist/${filename}" | cut -d: -f2-)${NC}"
  fi
  tar -C dist -cJf "dist/${filename}.tar.xz" "${filename}"
  echo -e "${JUNEBUD}= All done! Binary: dist/${filename} ($(du -sh "dist/${filename}" | cut -f1))${NC}"
}
