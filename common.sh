#!/usr/bin/env bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
CONF_FILE="${SCRIPT_DIR}"/config.sh
[[ -f "${CONF_FILE}" ]] && source "${CONF_FILE}"

##### Colors ################
AQUA="\033[38;2;18;254;202m"
BLOOD="\033[38;2;102;6;6m"
BOYSENBERRY="\033[38;2;135;50;96m"
BWHITE="\033[1;37m"
CAMEL="\033[38;2;193;154;107m"
CANARY="\033[38;2;255;255;153m"
CARIBBEAN="\033[38;2;0;204;153m"
CHARTREUSE="\033[38;2;127;255;0m"
COOLGRAY="\033[38;2;140;146;172m"
CORAL="\033[38;2;240;128;128m"
CRIMSON="\033[38;2;220;20;60m"
GOLDENROD="\033[38;2;218;165;32m"
HELIOTROPE="\033[38;2;223;115;255m"
HIGHLIGHTER="\033[38;2;248;255;15m"
HOTPINK="\033[38;2;255;105;180m"
INDIGO="\033[38;2;111;0;255m"
JUNEBUD="\033[38;2;189;218;87m"
LAGOON="\033[38;2;142;235;236m"
LEMON="\033[38;2;255;244;79m"
LTVIOLET="\033[38;2;207;159;255m"
LIME="\033[38;2;204;255;0m"
MAUVE="\033[38;2;224;175;255m"
MINT="\033[38;2;152;255;152m"
MISTYROSE="\033[38;2;255;226;223m"
MOSS="\033[38;2;138;154;91m"
NAVAJO="\033[38;2;255;222;173m"
OCHRE="\033[38;2;204;119;34m"
ORANGE="\033[38;2;255;165;0m"
PEACH="\033[38;2;246;161;146m"
PINK="\033[38;2;255;45;192m"
PURPLE_BLUE="\033[38;2;147;130;255m"
REBECCA="\033[38;2;102;51;153m"
SAND="\033[38;2;194;178;128m"
SEA="\033[38;2;32;178;170m"
SKY="\033[38;2;135;206;250m"
SLATE="\033[38;2;109;129;150m"
TAWNY="\033[38;2;204;78;0m"
TEAL="\033[38;2;0;128;128m"
TOMATO="\033[38;2;255;99;71m"
TURQUOISE="\033[38;2;64;224;208m"
UGLY="\033[38;2;122;115;115m"
VIOLET="\033[38;2;143;0;255m"
NEONPINK="\033[38;2;255;19;240m"
NEONBLUE="\033[38;2;4;218;255m"
NEONRED="\033[38;2;255;49;49m"
NEONGREEN="\033[38;2;57;255;20m"
NC="\033[0m"

######################
# Setup Validation   #
######################
# Validate required environment
for var in ALPINE_VERSION ALPINE_MAJOR_MINOR CHROOTDIR; do
  if [ -z "${!var:-}" ]; then
    echo -e "${CRIMSON}= ERROR: Required variable $var is not set${NC}" >&2
    exit 1
  fi
done

# Validate disk space (need at least 2GB free)
required_space_kb=$((2 * 1024 * 1024))
available_space_kb=$(df . -k | tail -1 | awk '{print $4}')
if [ "$available_space_kb" -lt "$required_space_kb" ]; then
  echo -e "${CRIMSON}= ERROR: Insufficient disk space${NC}" >&2
  echo -e "${CRIMSON}  Required: 2GB, Available: $((available_space_kb / 1024))MB${NC}" >&2
  exit 1
fi

##############################################
# normalize ARCH names                       #
# Map various CPU architecture names         #
# to canonical values used by Alpine Linux   #
# x86-64/amd64 → x86_64  (Intel/AMD 64-bit)  #
# i386/i486/i586/i686 → x86  (Intel 32-bit)  #
# arm64/armv8 → aarch64  (ARM 64-bit)        #
# armv7* → armv7  (ARM 32-bit with NEON)     #
# armv6/arm → armhf  (ARM 32-bit hard-float) #
##############################################
ARCH=${ARCH:-$(uname -m)}
case "${ARCH}" in
  x86-64|amd64) ARCH="x86_64" ;;
  i*86)         ARCH="x86" ;;
  arm64|armv8)  ARCH="aarch64" ;;
  armv7*)       ARCH="armv7" ;;
  armv6|arm)    ARCH="armhf" ;;
  *)    echo -e "${MAUVE}= ARCH '${ARCH}' not in normalization map, using as-is${NC}" ;;
esac

####################
#   Setup tools    #
####################
for tool in jq curl upx; do
  bundled="tools/${tool}/${tool}-${ARCH}"
  if [[ -x "$bundled" ]] && "$bundled" --version &>/dev/null; then
    declare "${tool^^}=$bundled"
  elif command -v "$tool" &>/dev/null; then
    echo -e "${LIME}= bundled $tool not usable, falling back to system $tool${NC}" >&2
    declare "${tool^^}=$tool"
  else
    echo -e "${BLOOD}= ERROR: no $tool available (checked $bundled and PATH)${NC}" >&2
    exit 1
  fi
done

########################################################
# setup_arch: resolve QEMU_ARCH & ARCH_FLAGS from ARCH #
########################################################
setup_arch() {
  case "${ARCH}" in
    x86_64)
      QEMU_ARCH=""
      ARCH_FLAGS="${X8664_FLAGS}"
      RUST_TARGET="x86_64-alpine-linux-musl"
      ;;
    x86)
      QEMU_ARCH="i386"
      ARCH_FLAGS="${X86_FLAGS}"
      RUST_TARGET="i586-alpine-linux-musl"
      ;;
    aarch64)
      QEMU_ARCH="aarch64"
      ARCH_FLAGS="${AARCH64_FLAGS}"
      RUST_TARGET="aarch64-alpine-linux-musl"
      ;;
    armv7)
      QEMU_ARCH="arm"
      ARCH_FLAGS="${ARMV7_FLAGS}"
      RUST_TARGET="armv7-unknown-linux-musleabihf"
      ;;
    armhf)
      QEMU_ARCH="arm"
      ARCH_FLAGS="${ARMHF_FLAGS}"
      RUST_TARGET="arm-unknown-linux-musleabihf"
      ;;
    *)
      echo -e "${LAGOON}Unknown architecture: ${HOTPINK}${ARCH}${NC}" >&2
      exit 1
      ;;
  esac
  # ALPINE_TARBALL is the Alpine minirootfs filename (distinct from the build source tarball)
  ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MAJOR_MINOR}/releases/${ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"
  ALPINE_TARBALL="${ALPINE_URL##*/}"
}

####################################
# Helper to handle cache checks    #
# Usage: check_cache "unique_key"  #
####################################
check_cache() {
    local cache_file="${VER_CACHE_DIR}/${1}.cache"
    local lockfile="${cache_file}.lock"
    (
        flock -s 200 2>/dev/null || return 1
        if [[ -f "$cache_file" ]]; then
            local last_mod now
            last_mod=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file")
            now=$(date +%s)
            if (( now - last_mod < VER_CACHE_TTL )); then
                cat "$cache_file"
                return 0
            fi
        fi
        return 1
    ) 200>"$lockfile"
}

###########################################
# Helper to save to cache                 #
# Usage: write_cache "unique_key" "value" #
###########################################
write_cache() {
    mkdir -p "$VER_CACHE_DIR"
    local cache_file="${VER_CACHE_DIR}/${1}.cache"
    local lockfile="${cache_file}.lock"
    local temp_file="${cache_file}.tmp.$$"
    (
        flock -x 200 || return 1
        echo "$2" > "$temp_file"
        mv "$temp_file" "$cache_file"
    ) 200>"$lockfile"
}

#########################################
# Get latest release or tag from Github #
#########################################
get_version() {
  local type="$1" repo="$2" filter="$3" fallback="$4"
  local cache_key="gh_${repo//\//_}_${type}"
  local version

  if cached_val=$(check_cache "$cache_key"); then
      echo "$cached_val"
      return
  fi

  local endpoint="releases/latest" default_f=".tag_name"
  [[ "$type" == "tag" ]] && { endpoint="tags"; default_f=".[0].name"; }
  local url="https://api.github.com/repos/${repo}/${endpoint}"

  version=$("${CURL}" -fsSL --connect-timeout 10 --max-time 30 \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
    "$url" | "${JQ}" -r "${filter:-$default_f} // empty" 2>/dev/null)

  if [[ -n "$version" && "$version" != "null" ]]; then
    write_cache "$cache_key" "$version"
    echo "$version"
  else
    local name="${repo##*/}"
    echo -e "${TAWNY}= GitHub API unavailable, falling back to $name $fallback${NC}" >&2
    echo "$fallback"
  fi
}

##############################################################
# Helper to fetch latest version from cgit/gitweb interfaces #
##############################################################
get_git_version() {
    local url="$1" pattern="$2" strip_prefix="$3" fallback="$4"
    local cache_key="git_${url//[^[:alnum:]]/_}"

    local cached_val
    if cached_val=$(check_cache "$cache_key"); then
        [[ -n "$cached_val" ]] && { echo "$cached_val"; return 0; }
    fi

    local raw_output version
    raw_output=$("${CURL}" -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 30 "$url")
    version=$(echo "$raw_output" | grep -oaE "$pattern" | sort -V | tail -n 1)

    if [[ -n "$version" ]]; then
        # Strip prefix, convert underscores to dots, normalize 'p' suffix (e.g. 10.3.P1 → 10.3p1)
        version="${version#$strip_prefix}"
        version="${version//_/.}"
        version=$(echo "$version" | sed -E 's/\.[Pp]/p/; s/\.$//')

        write_cache "$cache_key" "$version"
        echo "$version"
    else
        echo "$fallback"
    fi
}

#############################
# versions from gitlab      #
#############################
get_gitlab_version() {
    local project_path="$1" fallback="$2"
    local cache_key="gitlab_${project_path//\//_}"

    # 1. Try Cache
    local cached_val
    if cached_val=$(check_cache "$cache_key"); then
        [[ -n "$cached_val" ]] && { echo "$cached_val"; return 0; }
    fi

    # 2. Fetch from API
    # We URL-encode the path and use JQ to grab the first 'name' field
    local url="https://gitlab.com/api/v4/projects/${project_path//\//%2F}/repository/tags"
    local version

    version=$("${CURL}" -fsSL --connect-timeout 10 --max-time 30 "$url" | "${JQ}" -r '.[0].name // empty' 2>/dev/null)

    # 3. Process and Save
    if [[ -n "$version" && "$version" != "null" ]]; then
        # Strip leading 'v' if present (common in GitLab tags)
        version="${version#v}"

        write_cache "$cache_key" "$version"
        echo "$version"
    else
        # If blank, return fallback
        echo "$fallback"
    fi
}

############################
# get version from the web #
############################
get_web_version() {
  local url="$1"
  local regex="$2"
  local version
  #version=$("${CURL}" -s "$url" | grep -oP "$regex" | sort -V | tail -n 1)
  version=$("${CURL}" -s "$url" | grep -oP "$regex" | sort -V | tail -n 1) || true
  if [[ -z "$version" ]]; then
    echo "FAILED"
    #return 1
    return 0
  fi
  echo "$version"
}

###############################################################
# unmount_chroot: safely unmount all bind mounts in chroot    #
# Called from the EXIT trap (setup_cleanup) and package_output#
###############################################################
unmount_chroot() {
  local max_attempts=3
  local attempt=0

  # Sync to ensure all writes are finished
  sync
  while [ $attempt -lt $max_attempts ]; do
    if ! grep -qF "$(pwd)/${CHROOTDIR}" /proc/mounts 2>/dev/null; then
      return 0  # Successfully unmounted
    fi

    if command -v findmnt >/dev/null 2>&1; then
      sudo findmnt --list --noheadings --output TARGET | grep -F "$(pwd)/${CHROOTDIR}" | tac | xargs -r sudo umount -nfR 2>/dev/null || true
    else
      grep -F "$(pwd)/${CHROOTDIR}" /proc/mounts | cut -f2 -d" " | sort -r | xargs -r sudo umount -nfR 2>/dev/null || true
    fi

    # Re-check immediately; only sleep if still mounted (exponential backoff)
    if ! grep -qF "$(pwd)/${CHROOTDIR}" /proc/mounts 2>/dev/null; then
      return 0
    fi
    sleep $(( attempt + 1 ))
    (( ++attempt ))
  done

  # Final check
  if grep -qF "$(pwd)/${CHROOTDIR}" /proc/mounts; then
    if [ "${GITHUB_ACTIONS:-}" == "true" ] || [ "${CI:-}" == "true" ]; then
      echo -e "${TOMATO}CI Environment detected. Forcing lazy unmount...${NC}"
      grep -F "$(pwd)/${CHROOTDIR}" /proc/mounts | cut -f2 -d" " | sort -r | xargs -r sudo umount -l 2>/dev/null || true
    else
      read -p "DANGER - Do you want to lazy unmount? (y/n): " yn
      case $yn in
        [yY] ) grep -F "$(pwd)/${CHROOTDIR}" /proc/mounts | cut -f2 -d" " | sort -r | xargs -r sudo umount -l 2>/dev/null || true;;
        [nN] ) echo -e "${TOMATO}ERROR: Failed to unmount all filesystems in ${CHROOTDIR} after ${max_attempts} attempts${NC}" >&2; exit;;
        * ) echo "Invalid response"; exit 1;;
      esac
    fi
  fi
}

###############################################################
# setup_cleanup: register unmount trap for chroot bind mounts #
###############################################################
setup_cleanup() {
  trap unmount_chroot EXIT INT TERM
}

#####################################################################
# install_host_deps: install required packages on the Ubuntu runner #
#####################################################################
install_host_deps() {
  echo -e "${SEA}= install dependencies${NC}"
  local DEBIAN_DEPS=(binutils coreutils patch sed)
  [ -n "${QEMU_ARCH}" ] && DEBIAN_DEPS+=(qemu-user-static)
  sudo flock /var/lib/apt/lists/lock -c "apt-get update -qq"
  sudo apt-get install -qy --no-install-recommends "${DEBIAN_DEPS[@]}"
}

#######################################################
# Helper function to rank mirrors by connection speed #
#######################################################
get_fastest_mirrors() {
    local mirrors=("$@")
    if [[ ${#mirrors[@]} -le 1 ]]; then
        echo "${mirrors[@]}"
        return
    fi
    echo -e "${SKY}= Ranking ${#mirrors[@]} mirrors by latency...${NC}" >&2
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local pids=() i=0
    for url in "${mirrors[@]}"; do
        (
            latency=$("${CURL}" -o /dev/null -s -w "%{time_connect}\n" --connect-timeout 2 -I "$url" 2>/dev/null || echo "9.999")
            echo "$latency $url"
        ) > "${tmp_dir}/${i}" &
        pids+=($!)
        i=$((i + 1))
    done
    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
    cat "${tmp_dir}"/* 2>/dev/null | sort -n | awk '{print $2}'
    rm -rf "${tmp_dir}"
}

####################################################################
# download_source LABEL VERSION TARBALL mirror1 [mirror2 ...]      #
# Downloads TARBALL from the first mirror that succeeds.           #
# Skips the download if it exists and validates file is not empty. #
# Uses a .tmp file to avoid leaving corrupt partial downloads.     #
####################################################################
download_source() {
  local label="$1" version="$2" tarball="$3"
  shift 3
  if [ ! -d distfiles/ ]; then
    echo -e "${INDIGO}distfiles dir does not exist. Creating it now.${NC}"
    mkdir -p distfiles/
  fi
  # Clean up any stale partial download for this tarball
  rm -f "distfiles/${tarball}.tmp"
  if [ -f "distfiles/${tarball}" ]; then
    echo -e "${SLATE}= ${label}-${version}: distfiles/${tarball} already cached, skipping download${NC}"
    # Verify cached file is not empty
    if [ ! -s "distfiles/${tarball}" ]; then
      echo -e "${CRIMSON}= ERROR: Cached file is empty: distfiles/${tarball}${NC}" >&2
      exit 1
    fi
    return 0
  fi
  echo -e "${AQUA}= downloading ${label}-${version} tarball${NC}"
  local tmp_file="distfiles/${tarball}.tmp"
  # PID suffix avoids collisions when multiple builds run concurrently in the same workspace
  local error_log="distfiles/${tarball}.$$.err"
  local downloaded=false
  local mirror_count=0
  local total_mirrors=$#

  for mirror in "$@"; do
    mirror_count=$((mirror_count + 1))
    echo -e "${TAWNY}= trying mirror [${mirror_count}/${total_mirrors}]: ${mirror}${NC}"

    # Capture curl output (both stdout redirect and stderr to error log)
    if "${CURL}" -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
        -o "${tmp_file}" "${mirror}" 2>"${error_log}"; then
      # Verify downloaded file is not empty
      if [ ! -s "${tmp_file}" ]; then
        echo -e "${LEMON}= failed: downloaded file is empty, trying next mirror${NC}"
        rm -f "${tmp_file}"
        continue
      fi
      mv "${tmp_file}" "distfiles/${tarball}"
      echo -e "${MINT}= successfully downloaded from: ${mirror}${NC}"
      rm -f "${error_log}"
      downloaded=true
      break
    else
      local exit_code=$?
      echo -e "${LEMON}= download failed: ${mirror}${NC}"

      # Parse and display the actual error
      if [ -s "${error_log}" ]; then
        local error_msg
        error_msg=$(head -n 1 "${error_log}" | sed 's/^curl: //')
        echo -e "${TOMATO}  └─ Error: ${error_msg}${NC}" >&2
      else
        # Map common curl exit codes to human-readable messages
        case ${exit_code} in
          6)  echo -e "${CORAL}  └─ Error: Could not resolve host${NC}" >&2 ;;
          7)  echo -e "${HOTPINK}  └─ Error: Failed to connect${NC}" >&2 ;;
          22) echo -e "${ORANGE}  └─ Error: HTTP error (404, 403, etc.)${NC}" >&2 ;;
          28) echo -e "${CHARTREUSE}  └─ Error: Timeout${NC}" >&2 ;;
          35) echo -e "${TURQUOISE}  └─ Error: SSL connection error${NC}" >&2 ;;
          *)  echo -e "${LIME}  └─ Error: curl exit code ${exit_code}${NC}" >&2 ;;
        esac
      fi
      rm -f "${tmp_file}" "${error_log}"
    fi
  done
  if [ "${downloaded}" = false ]; then
    echo -e "${CRIMSON}= ERROR: all ${total_mirrors} mirror(s) failed for ${tarball}${NC}" >&2
    echo -e "${CRIMSON}= Please check your network connection or try again later${NC}" >&2
    exit 1
  fi
}

#####################################################
# setup_alpine_chroot TARBALL                       #
# Downloads Alpine rootfs, extracts it, and copies  #
# resolv.conf + source tarball inside.              #
#####################################################
setup_alpine_chroot() {
  local PREBAKED_IMAGE="alpine-base-${ARCH}.tar.zst"
  local tarball="$1"
  if [ -d "./${CHROOTDIR}" ] && [ "${KEEP_CHROOT}" = "false" ]; then
    unmount_chroot
    if grep -qF "$(pwd)/${CHROOTDIR}" /proc/mounts; then
      echo -e "${TOMATO}ERROR: Mounts still active in ${CHROOTDIR}. Deletion ${BLOOD}BLOCKED!${NC}" >&2
      exit 1
    fi
    echo -e "${GOLDENROD}= chroot dir exist! Removing it now.${NC}"
    sudo rm -fr "./${CHROOTDIR}"
  fi
  if [ -f "minirootfs/${PREBAKED_IMAGE}" ]; then
      age=$(( $(date +%s) - $(stat -c %Y "minirootfs/${PREBAKED_IMAGE}") ))
      if (( age > 2592000 )); then  # 30 days
        echo -e "${LEMON}= WARNING: prebaked image is >30 days old, consider rebuilding${NC}"
      fi
      echo -e "${CARIBBEAN}= Found pre-baked image: ${PREBAKED_IMAGE}. Extracting...${NC}"
      mkdir -p "./${CHROOTDIR}"
      tar -xf minirootfs/"${PREBAKED_IMAGE}" -C "./${CHROOTDIR}"
  else
      echo -e "${CORAL}= No pre-baked image found. Downloading official Alpine...${NC}"
      if [ ! -d minirootfs/ ]; then
        echo -e "${INDIGO}minirootfs dir does not exist. Creating it now.${NC}"
        mkdir -p minirootfs/
      fi
      if [ -f minirootfs/"${ALPINE_TARBALL}" ] && [ -f minirootfs/"${ALPINE_TARBALL}.sha256" ]; then
        echo -e "${SLATE}= Alpine rootfs ${ALPINE_TARBALL} already cached, verifying checksum...${NC}"
        if ! ( cd minirootfs && sha256sum -c "${ALPINE_TARBALL}.sha256" --status ); then
          echo -e "${CRIMSON}= ERROR: Cached Alpine rootfs failed checksum verification: minirootfs/${ALPINE_TARBALL}${NC}" >&2
          exit 1
        fi
      else
        echo -e "${CANARY}= download alpine rootfs and checksum${NC}"
        "${CURL}" -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
          -o minirootfs/"${ALPINE_TARBALL}" "${ALPINE_URL}" \
          || { echo -e "${CRIMSON}= ERROR: failed to download Alpine rootfs${NC}" >&2; exit 1; }
        "${CURL}" -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
          -o minirootfs/"${ALPINE_TARBALL}.sha256" "${ALPINE_URL}.sha256" \
          || { echo -e "${CRIMSON}= ERROR: failed to download Alpine rootfs checksum${NC}" >&2; exit 1; }
        if ! ( cd minirootfs && sha256sum -c "${ALPINE_TARBALL}.sha256" --status ); then
          echo -e "${CRIMSON}= ERROR: Downloaded Alpine rootfs failed checksum verification${NC}" >&2
          exit 1
        fi
      fi
    echo -e "${SKY}= extract rootfs${NC}"
    mkdir -p "${CHROOTDIR}"
    tar xf minirootfs/"${ALPINE_TARBALL}" -C "${CHROOTDIR}"/
  fi
  echo -e "${HELIOTROPE}= copy resolv.conf into chroot${NC}"
  cp /etc/resolv.conf "./${CHROOTDIR}/etc/" || \
    echo -e "${TAWNY}= WARNING: failed to copy resolv.conf — DNS may not work inside chroot${NC}"
  if [ "${tarball}" != "base-setup" ]; then
    echo -e "${PEACH}= copying ${tarball} into chroot${NC}"
    cp distfiles/"${tarball}" "./${CHROOTDIR}/${tarball}"
  fi
  # bundled tools
  echo -e "${SAND}= install prebuilt tools${NC}"
  local src
  #for prebuilt in 7zz upx uasm curl jq mold; do
  #  src="tools/${prebuilt}/${prebuilt}-${ARCH}"
  #  if [[ ! -f "$src" ]]; then
  #    echo -e "${CRIMSON}= ERROR: ${src} not found${NC}" >&2
  #    exit 1
  #  fi
  #  cp "$src" "./${CHROOTDIR}/usr/local/bin/${prebuilt}"
  #done
  for tool_name in 7zz upx uasm curl jq mold; do
    local tool_src="tools/${tool_name}/${tool_name}-${ARCH}"
    if [[ ! -f "$tool_src" ]]; then
      echo -e "${CRIMSON}= ERROR: ${tool_src} not found${NC}" >&2
      exit 1
    fi
    cp "$tool_src" "./${CHROOTDIR}/usr/local/bin/${tool_name}"
  done
}

#####################################################################
# copy_patches TOOL                                                 #
# Copies all patch files from patches/TOOL/ into chroot/patches/    #
#####################################################################
copy_patches() {
    mkdir -p "${CHROOTDIR}/patches/"
    sudo cp -r "patches/$1/." "${CHROOTDIR}/patches/" 2>/dev/null || true
}

############################################################
# setup_qemu: copy qemu into chroot for cross-arch builds  #
# Validates QEMU binary exists before copying.             #
############################################################
setup_qemu() {
  if [ -n "${QEMU_ARCH}" ]; then
    echo -e "${TURQUOISE}= setup QEMU for cross-arch builds${NC}"
    local qemu_bin
    if qemu_bin=$(command -v "qemu-${QEMU_ARCH}-static" 2>/dev/null); then
      echo -e "${SKY}= Found static QEMU: ${qemu_bin}${NC}"
      sudo mkdir -p "./${CHROOTDIR}/usr/bin/"
      sudo cp "${qemu_bin}" "./${CHROOTDIR}/usr/bin/"
    elif qemu_bin=$(command -v "qemu-${QEMU_ARCH}" 2>/dev/null); then
      echo -e "${CAMEL}= Found QEMU: ${qemu_bin} (copying as static)${NC}"
      sudo mkdir -p "./${CHROOTDIR}/usr/bin/"
      sudo cp "${qemu_bin}" "./${CHROOTDIR}/usr/bin/qemu-${QEMU_ARCH}-static"
    else
      echo -e "${CRIMSON}= ERROR: No QEMU binary found for ${QEMU_ARCH}${NC}" >&2
      echo -e "${PEACH}  Architecture: ${QEMU_ARCH}${NC}" >&2
      echo -e "${NAVAJO}  Current PATH: $PATH${NC}" >&2
      echo -e "${HELIOTROPE}= Install it with:${NC} ${TEAL}sudo apt-get install qemu-user-static or qemu-user-binfmt${NC}" >&2
      exit 1
    fi
  fi
}

##########################################################
# mount_chroot: bind-mount proc/dev/sys into the chroot  #
# Validates CCACHE_DIR exists before mounting.           #
##########################################################
mount_chroot() {
  echo -e "${VIOLET}= mount, bind and chroot into dir${NC}"
  sudo mount --rbind /dev "./${CHROOTDIR}/dev/"
  sudo mount --make-rslave "./${CHROOTDIR}/dev/"
  sudo mount --rbind /sys "./${CHROOTDIR}/sys/"
  sudo mount --make-rslave "./${CHROOTDIR}/sys/"
  sudo mount -t proc none "./${CHROOTDIR}/proc/"
  sudo mount -o bind /tmp "./${CHROOTDIR}/tmp/"
  sudo mount -t tmpfs -o nosuid,nodev,noexec,mode=755 none "./${CHROOTDIR}/run"
  # Mount ccache directories if CCACHE_DIR is set
  if [ -n "${CCACHE_DIR:-}" ]; then
    if [ ! -d "${CCACHE_DIR}" ]; then
      echo -e "${CRIMSON}= ERROR: CCACHE_DIR is set but directory does not exist: ${CCACHE_DIR}${NC}" >&2
      exit 1
    fi
    echo -e "${JUNEBUD}= bind mounting ccache directories${NC}"
    sudo mkdir -p "./${CHROOTDIR}/${CCACHE_CHROOT_DIR}"
    sudo mount --bind "${CCACHE_DIR}" "./${CHROOTDIR}/${CCACHE_CHROOT_DIR}"
    sudo mount --make-slave "./${CHROOTDIR}/${CCACHE_CHROOT_DIR}"
    sudo mkdir -p "./${CHROOTDIR}/${CCACHE_LOG_DIR}"
  fi
}

######################################################################################
# run_build_setup TOOL VERSION TARBALL -- MIRROR [MIRROR...]                         #
# Runs the full pre-chroot setup sequence. Patches are automatically discovered      #
# from patches/TOOL/ directory.                                                      #
#                                                                                    #
# Usage:                                                                             #
#    run_build_setup "curl" "8.19.0" "curl-8.19.0.tar.xz" -- "https://..." [...]     #
######################################################################################
run_build_setup() {
  local tool="$1" version="$2" tarball="$3"
  shift 3
  [[ $# -gt 0 && "$1" == "--" ]] && shift
  local mirrors=("$@")
  if [[ ${#mirrors[@]} -gt 0 ]]; then
      mapfile -t mirrors < <(get_fastest_mirrors "${mirrors[@]}")
      echo -e "${CANARY}= Fastest mirror: ${PEACH}${mirrors[0]}${NC}"
  fi
  setup_arch
  setup_cleanup
  install_host_deps
  download_source "${tool}" "${version}" "${tarball}" "${mirrors[@]}"
  setup_alpine_chroot "${tarball}"
  copy_patches "${tool}"
  setup_qemu
  mount_chroot
}

#######################################################################
# rust_set_cross_target: sets RUST_TARGET for ARM cross-compile,      #
# or leaves it empty (meaning: build natively in the Alpine chroot).  #
# Call after run_build_setup (which calls setup_arch internally).      #
#######################################################################
rust_set_cross_target() {
  case "${ARCH}" in
    armhf) RUST_TARGET="arm-unknown-linux-musleabihf"   ;;
    armv7) RUST_TARGET="armv7-unknown-linux-musleabihf" ;;
    *)     RUST_TARGET=""                               ;;
  esac
}

#######################################################################
# rust_host_cross_build TOOL VERSION TARBALL SRC_DIR BIN_NAME         #
# Cross-compiles a Cargo project on the host runner using             #
# cargo-zigbuild. Only call this when RUST_TARGET is non-empty        #
# (set by rust_set_cross_target).                                      #
#                                                                      #
# BIN_NAME is the filename inside target/<RUST_TARGET>/release/.       #
#######################################################################
rust_host_cross_build() {
  local tool="$1" version="$2" tarball="$3" src_dir="$4" bin_name="$5"

  echo -e "${SLATE}= Cross-compiling ${tool} on host (QEMU-arm too slow / no Alpine Rust pkg for ${ARCH})${NC}"
  echo -e "${ORANGE}= Installing zig (musl cross-linker) via pip${NC}"
  pip3 install --user --quiet ziglang
  export PATH="${HOME}/.local/bin:${PATH}"

  if ! command -v rustup >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get install -qy --no-install-recommends rustup
    else
      echo -e "${CRIMSON}= ERROR: rustup not found and apt-get unavailable${NC}" >&2
      exit 1
    fi
  fi
  # shellcheck source=/dev/null
  source "${HOME}/.cargo/env" 2>/dev/null || true

  rustup target add "${RUST_TARGET}"
  if ! command -v cargo-zigbuild >/dev/null 2>&1; then
    cargo install cargo-zigbuild@0.23.1 --locked
  fi

  echo -e "${LIME}= Extracting ${tool} source${NC}"
  local build_dir
  build_dir=$(mktemp -d)
  tar xf "distfiles/${tarball}" -C "${build_dir}"

  echo -e "${VIOLET}= Building ${tool} ${version} for ${ARCH} (cross-compilation on host)${NC}"
  pushd "${build_dir}/${src_dir}/"
  CARGO_PROFILE_RELEASE_OPT_LEVEL="z" CARGO_PROFILE_RELEASE_LTO="true" \
  CARGO_PROFILE_RELEASE_STRIP="symbols" CARGO_PROFILE_RELEASE_CODEGEN_UNITS="1" \
  RUSTFLAGS="-C target-feature=+crt-static" \
    cargo zigbuild --release --target "${RUST_TARGET}"
  popd

  package_output "${tool}" "${build_dir}/${src_dir}/target/${RUST_TARGET}/release/${bin_name}"
  rm -rf "${build_dir}"
}

#############################################################
# verify_binary_arch BINARY                                 #
# Reads the ELF Machine field and checks it matches ARCH.  #
# Emits a warning on mismatch; never aborts the build.     #
#############################################################
verify_binary_arch() {
  local binary="$1"
  if ! command -v readelf >/dev/null 2>&1; then
    echo -e "${NAVAJO}= verify_binary_arch: readelf not found, skipping ELF check${NC}"
    return 0
  fi
  local machine
  machine=$(readelf -h "${binary}" 2>/dev/null | grep -i "Machine:" | sed 's/.*Machine:[[:space:]]*//')
  if [[ -z "${machine}" ]]; then
    echo -e "${CAMEL}= verify_binary_arch: could not read ELF header from ${binary}${NC}"
    return 0
  fi
  local expected_ok=false
  case "${ARCH}" in
    x86_64)
      [[ "${machine}" =~ [Xx]86-64 ]] && expected_ok=true
      ;;
    x86)
      [[ "${machine}" =~ 80386 ]] && expected_ok=true
      ;;
    aarch64)
      [[ "${machine}" =~ [Aa][Aa]rch64 ]] && expected_ok=true
      ;;
    armv7|armhf)
      [[ "${machine}" =~ ^ARM ]] && expected_ok=true
      ;;
    *)
      echo -e "${TAWNY}= verify_binary_arch: no check defined for ARCH='${ARCH}', skipping${NC}"
      return 0
      ;;
  esac
  if "${expected_ok}"; then
    echo -e "${MINT}= ELF arch OK: ${machine} (expected for ${ARCH})${NC}"
  else
    echo -e "${TOMATO}!! WARNING: ELF arch mismatch !!${NC}" >&2
    echo -e "${TOMATO}   ARCH=${ARCH} but binary reports: ${machine}${NC}" >&2
    echo -e "${TOMATO}   Binary: ${binary}${NC}" >&2
  fi
}

#########################################
# package_output TOOL BINARY            #
# Copies the built binary to dist/,     #
# creates an archive, and prints info.  #
#########################################
package_output() {
  local tool="$1" binary="$2"
  if [ ! -f "${binary}" ]; then
    echo -e "${CRIMSON}= ERROR: Binary not found: ${binary}${NC}" >&2
    exit 1
  fi
  local version_suffix=""
  [ -n "${PACKAGE_VERSION:-}" ] && version_suffix="-${PACKAGE_VERSION}"
  local filename="${tool}${version_suffix}-${ARCH}"
  if command -v file >/dev/null 2>&1; then
    echo -e "\n"
    echo -e "${JUNEBUD}= Verifying binary: ${binary}${NC}"
    verify_binary_arch "${binary}"
    if file "${binary}" | grep -Ei "interpreter|dynamically linked" >/dev/null; then
        echo -e "${UGLY}!! WARNING: Binary is DYNAMICALLY linked !!${NC}"
        file "${binary}"
        if [ "${REQUIRE_STATIC:-false}" = "true" ]; then
            echo -e "${CRIMSON}= ERROR: REQUIRE_STATIC=true — refusing dynamic binary${NC}" >&2
            exit 1
        fi
    else
        echo -e "${PINK}= Verified: Binary is statically linked.${NC}"
    fi
  fi
  install -D -m 755 "${binary}" "dist/${filename}"
  if [ "${USE_STRIP}" = "true" ]; then
      echo -e "${LTVIOLET}= Stripping ${filename}...${NC}"
      strip "dist/${filename}" 2>/dev/null || true
  fi
  if [ "${USE_UPX}" = "true" ]; then
      if [ -x "${UPX}" ]; then
          echo -e "${CHARTREUSE}= Compressing ${filename} with UPX...${NC}"
          ${UPX} ${UPX_FLAGS} "dist/${filename}" || true
      else
          echo -e "${TOMATO}! UPX binary not found at ${UPX}, skipping compression${NC}"
      fi
  fi
  if command -v file >/dev/null 2>&1; then
    echo -e "${HIGHLIGHTER} File Info:  $(file "dist/${filename}" | cut -d: -f2-)${NC}"
  fi
  local temp_archive="dist/${filename}.tar.xz.tmp.$$"
  if ! tar -C dist -cJf "${temp_archive}" "${filename}"; then
    echo -e "${CRIMSON}= ERROR: Failed to create archive: ${temp_archive}${NC}" >&2
    rm -f "${temp_archive}"
    exit 1
  fi
  if [ ! -s "${temp_archive}" ]; then
    echo -e "${CRIMSON}= ERROR: Archive created but is empty: ${temp_archive}${NC}" >&2
    rm -f "${temp_archive}"
    exit 1
  fi
  mv "${temp_archive}" "dist/${filename}.tar.xz"
  local raw_sz compressed_sz
  raw_sz=$(du -sh "dist/${filename}" | cut -f1)
  compressed_sz=$(du -sh "dist/${filename}.tar.xz" | cut -f1)
  echo -e "${TOMATO}= All done!${MISTYROSE} Binary: ${BWHITE}dist/${filename}: ${CARIBBEAN}${raw_sz}${NC} → ${CHARTREUSE}${compressed_sz}${NC} ${BWHITE}(xz)${NC}"
  if [ "${KEEP_CHROOT}" = "false" ]; then
    if grep -qF "$(pwd)/${CHROOTDIR}" /proc/mounts; then
      unmount_chroot
    fi
    # SAFETY CHECK: Do not rm -rf if mounts still exist
    if grep -qF "$(pwd)/${CHROOTDIR}" /proc/mounts; then
      echo -e "${CRIMSON}ERROR: Mounts still active in ${CHROOTDIR}. Skipping rm -rf for safety!${NC}" >&2
      return 1
    fi
    echo -e "${PURPLE_BLUE}= Cleaning up chroot: ${ORANGE}${CHROOTDIR}${NC}"
    sudo rm -rf "${CHROOTDIR}"
  else
    echo -e "${COOLGRAY}KEEP_CHROOT is true. ${MAUVE}Preserving: ${CHROOTDIR}${NC}"
  fi
}

# Cleanup mounts on failure
cleanup_on_fail() {
  echo -e "${TOMATO}= Build failed. Cleaning up...${NC}"
  unmount_chroot
}
trap cleanup_on_fail ERR