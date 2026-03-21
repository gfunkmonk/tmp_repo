#!/bin/bash
# common.sh - Shared functions and variables for all *-static-musl.sh scripts.
# Source this file at the top of each build script: . "$(dirname "$0")/common.sh"

######### Variables ###########
CHROOTDIR=${CHROOTDIR:-.chrootbuild}
ARCH=${ARCH:-x86_64}
ALPINE_VERSION="3.23.3"
ALPINE_MAJOR_MINOR="${ALPINE_VERSION%.*}"
JQ="tools/jq/jq-${ARCH}"
CURL="tools/curl/curl-${ARCH}"

# CCACHE_CHROOT_DIR: path inside the chroot where ccache stores its cache.
# Set this to a host-mounted path (e.g. via CI cache) to persist ccache across builds.
# Defaults to /ccache (ephemeral, inside the chroot).
CCACHE_CHROOT_DIR="${CCACHE_CHROOT_DIR:-/ccache}"

##### Colors ################
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
CORAL="\033[38;2;240;128;128m"
CAMEL="\033[38;2;193;154;107m"
INDIGO="\033[38;2;111;0;255m"
NC="\033[0m"

setup_tools() {
  if [[ -x "${JQ}" ]]; then
    : # use bundled jq
  elif command -v jq >/dev/null 2>&1; then
    echo -e "${LEMON}= bundled jq binary not found, falling back to system jq${NC}" >&2
    JQ="jq"
  else
    echo -e "${TOMATO}= ERROR: no jq binary available (checked ${JQ} and PATH)${NC}" >&2
    exit 1
  fi
  if [[ -x "${CURL}" ]]; then
    : # use bundled curl
  elif command -v curl >/dev/null 2>&1; then
    echo -e "${LEMON}= bundled curl not found, falling back to system curl${NC}" >&2
    CURL="curl"
  else
    echo -e "${TOMATO}= ERROR: no curl available (checked ${CURL} and PATH)${NC}" >&2
    exit 1
  fi
}

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

# gh_latest_release REPO [JQ_FILTER]
# Fetches .tag_name from the GitHub releases/latest API, applies optional jq filter.
# Defaults to returning .tag_name as-is.
gh_latest_release() {
    local repo="$1" filter="${2:-.tag_name}"
    "${CURL}" -fsSL --connect-timeout 10 --max-time 30 \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
        "https://api.github.com/repos/${repo}/releases/latest" \
        | "${JQ}" -r "${filter} // empty"
}

# gh_latest_tag REPO [JQ_FILTER]
# Fetches the first entry from the GitHub tags API, applies optional jq filter.
gh_latest_tag() {
    local repo="$1" filter="${2:-.[0].name}"
    "${CURL}" -fsSL --connect-timeout 10 --max-time 30 \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
        "https://api.github.com/repos/${repo}/tags" \
        | "${JQ}" -r "${filter} // empty"
}

# setup_cleanup: register unmount trap for chroot bind mounts
setup_cleanup() {
  cleanup() {
    echo -e "${CAMEL}Unmounting filesystems from chroot -- $CHROOTDIR${NC}"
    grep "$(pwd)/${CHROOTDIR}" /proc/mounts | cut -f2 -d" " | sort -r | xargs -r sudo umount -nl || true
  }
  trap cleanup EXIT
}

# install_host_deps: install required packages on the Ubuntu runner
install_host_deps() {
  echo -e "${AQUA}= install dependencies${NC}"
  local DEBIAN_DEPS=(binutils)
  [ -n "${QEMU_ARCH}" ] && DEBIAN_DEPS+=(qemu-user-static)
  sudo apt-get update -qy && sudo apt-get install -y "${DEBIAN_DEPS[@]}"
}

# download_source LABEL VERSION TARBALL mirror1 [mirror2 ...]
# Downloads TARBALL from the first mirror that succeeds.
# Skips the download if TARBALL already exists (e.g. restored from cache).
download_source() {
  local label="$1" version="$2" tarball="$3"
  shift 3
  if [ ! -d distfiles/ ]; then
    echo -e "${INDIGO}distfiles dir does not exist. Creating it now.${NC}"
    mkdir -p distfiles/
  fi
  if [ -f "distfiles/${tarball}" ]; then
    echo -e "${SLATE}= ${label}-${version}: distfiles/${tarball} already cached, skipping download${NC}"
    return 0
  fi
  echo -e "${AQUA}= downloading ${label}-${version} tarball${NC}"
  local downloaded=false
  for mirror in "$@"; do
    echo -e "${TAWNY}= trying mirror: ${mirror}${NC}"
    if "${CURL}" -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
        -o distfiles/"${tarball}" "${mirror}"; then
      echo -e "${MINT}= downloaded from: ${mirror}${NC}"
      downloaded=true
      break
    else
      echo -e "${LEMON}= failed: ${mirror}${NC}"
      rm -f distfiles/"${tarball}"
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
  if [ -d "./${CHROOTDIR}/" ]; then
    echo -e "${CORAL}chroot dir exist! Removing it now.${NC}"
    rm -fr "./${CHROOTDIR}/"
  fi
  if [ ! -d chrootfiles/ ]; then
    echo -e "${INDIGO}chrootfiles dir does not exist. Creating it now.${NC}"
    mkdir -p chrootfiles/
  fi
  if [ -f chrootfiles/"${TARBALL}" ]; then
    echo -e "${SLATE}= Alpine rootfs ${TARBALL} already cached, skipping download${NC}"
  else
    echo -e "${HELIOTROPE}= download alpine rootfs${NC}"
    "${CURL}" -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
      -o chrootfiles/"${TARBALL}" "${ALPINE_URL}" \
      || { echo -e "${TOMATO}= ERROR: failed to download Alpine rootfs${NC}" >&2; exit 1; }
  fi
  echo -e "${SKY}= extract rootfs${NC}"
  mkdir -p "${CHROOTDIR}"
  tar xf chrootfiles/"${TARBALL}" -C "${CHROOTDIR}"/
  echo -e "${PEACH}= copy resolv.conf and ${tarball} into chroot${NC}"
  cp /etc/resolv.conf ./${CHROOTDIR}/etc/
  cp distfiles/"${tarball}" "./${CHROOTDIR}/${tarball}"
  if [[ ! -f "tools/upx/upx-${ARCH}" ]]; then
    echo -e "${TOMATO}= ERROR: tools/upx/upx-${ARCH} not found${NC}"
    exit 1
  else
    cp "tools/upx/upx-${ARCH}" "./${CHROOTDIR}/upx"
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
    cp "patches/${patch}" "./${CHROOTDIR}/${patch}"
  done
}

# setup_qemu: copy qemu static binary into chroot for cross-arch builds
setup_qemu() {
  if [ -n "${QEMU_ARCH}" ]; then
    echo -e "${OCHRE}= setup QEMU for cross-arch builds${NC}"
    sudo mkdir -p "./${CHROOTDIR}/usr/bin/"
    sudo cp "/usr/bin/qemu-${QEMU_ARCH}-static" "./${CHROOTDIR}/usr/bin/"
  fi
}

# mount_chroot: bind-mount proc/dev/sys into the chroot directory
mount_chroot() {
  echo -e "${VIOLET}= mount, bind and chroot into dir${NC}"
  ccachelogdir=$(ccache -p | grep log_file | cut -d "=" -f2 | rev | cut -d'/' -f2- | rev)
  sudo mount --rbind /dev "./${CHROOTDIR}/dev/"
  sudo mount --make-rslave "./${CHROOTDIR}/dev/"
  sudo mount -t proc none "./${CHROOTDIR}/proc/"
  sudo mount --rbind /sys "./${CHROOTDIR}/sys/"
  sudo mount --make-rslave "./${CHROOTDIR}/sys/"
  if [ -n "${CCACHE_DIR:-}" ] && [ -d "${CCACHE_DIR}" ]; then
    sudo mkdir -p "./${CHROOTDIR}/${CCACHE_CHROOT_DIR}"
    sudo mount --bind "${CCACHE_DIR}" "./${CHROOTDIR}/${CCACHE_CHROOT_DIR}"
    if [ -n "$ccachelogdir" ]; then
      sudo mkdir -p "./${CHROOTDIR}/var/log/ccache/"
    fi
  fi
}

# run_build_setup TOOL VERSION TARBALL [PATCH...] -- MIRROR [MIRROR...]
# Runs the full pre-chroot setup sequence. Patches and mirrors are separated by --.
# Usage: run_build_setup "curl" "8.19.0" "curl-8.19.0.tar.xz" -- "https://..." [...]
# Usage (with patches): run_build_setup "wget" "1.25.0" "wget.tar.gz" "wget.patch" -- "https://..." [...]
run_build_setup() {
  local tool="$1" version="$2" tarball="$3"
  shift 3
  local patches=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    patches+=("$1")
    shift
  done
  [[ $# -gt 0 && "$1" == "--" ]] && shift
  local mirrors=("$@")
  setup_arch
  setup_cleanup
  install_host_deps
  download_source "${tool}" "${version}" "${tarball}" "${mirrors[@]}"
  setup_alpine_chroot "${tarball}"
  [[ ${#patches[@]} -gt 0 ]] && copy_patches "${patches[@]}"
  setup_qemu
  mount_chroot
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
