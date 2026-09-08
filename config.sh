#!/usr/bin/env bash

################################################################################
#     .oooooo.     .oooooo.   ooooo      ooo oooooooooooo ooooo   .oooooo.     #
#    d8P'  `Y8b   d8P'  `Y8b  `888b.     `8' `888'     `8 `888'  d8P'  `Y8b    #
#   888          888      888  8 `88b.    8   888          888  888            #
#   888          888      888  8   `88b.  8   888oooo8     888  888            #
#   888          888      888  8     `88b.8   888    "     888  888     ooooo  #
#   `88b    ooo  `88b    d88'  8       `888   888          888  `88.    .88'   #
#    `Y8bood8P'   `Y8bood8P'  o8o        `8  o888o        o888o  `Y8bood8P'    #
################################################################################

# Compiler Flags
BCFLAGS="-Os -static -ffunction-sections -fdata-sections -fno-stack-protector"
EXTRA="-fshort-enums -fno-ident -fno-unwind-tables -fno-asynchronous-unwind-tables"
LTO="-flto=auto -ffat-lto-objects"

# PIE Flags
### CFLAGS
CPIE="-fPIE"
CNOPIE="-fno-PIE"
### LDFLAGS
LPIE="-static-pie"
LNOPIE="-no-pie"

# Linker Flags
MOLD="-fuse-ld=mold"
BFD="-fuse-ld=bfd"
LDSTRIP="-w -Wl,-s"
BLDFLAGS="-static -Wl,--gc-sections"

# Compilers
CC="${CC:-gcc}"
CXX="${CXX:-g++}"

# Pkg-config
PKGCFG="pkg-config --static"

# ARCH_FLAGS
X8664_FLAGS="-march=x86-64 -mtune=generic"
X86_FLAGS="-march=pentium-m -mtune=generic"
AARCH64_FLAGS="-march=armv8-a"
ARMV7_FLAGS="-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard -marm"
ARMHF_FLAGS="-march=armv6kz -mfloat-abi=hard -mfpu=vfp -marm"

######### Variables ###########
# Alpine minirootfs version   #
###############################
ALPINE_VERSION="3.24.1"
ALPINE_MAJOR_MINOR="${ALPINE_VERSION%.*}"

# Set directory name for the target chroot
CHROOTDIR="${CHROOTDIR:-potato}"

# CCACHE_CHROOT_DIR: path inside the chroot where ccache stores its cache. Set this to a host-mounted path
CCACHE_CHROOT_DIR="${CCACHE_CHROOT_DIR:-/ccache}"

# Determine ccache's log_file directory so mount_chroot can pre-create it inside the chroot.
_ccache_log_file=$(ccache -k log_file 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
[[ -n ${_ccache_log_file} && ${_ccache_log_file} != "null" ]] && CCACHE_LOG_DIR=$(dirname "${_ccache_log_file}")
unset _ccache_log_file
CCACHE_LOG_DIR="${CCACHE_LOG_DIR:-/var/log/ccache}"

# Preserve chroot after failed builds
KEEP_CHROOT="${KEEP_CHROOT:-false}"

# Strip binaries
USE_STRIP="${USE_STRIP:-true}"

# Use UPX Compression
USE_UPX="${USE_UPX:-true}"
UPX_FLAGS="--lzma"

# Fail if binary is dynamically linked
REQUIRE_STATIC="${REQUIRE_STATIC:-true}"

##############################################################################
# Cache results from 'get_version' 'get_git_version' & 'get_gitlab_version'  #
# to save time and to keep from getting rate limited or temp blocked         #
#                                                                            #
# defaults to 3600 minutes  1 hour.                                       #
##############################################################################
VER_CACHE_TTL="${VER_CACHE_TTL:-3600}"
VER_CACHE_DIR="/tmp/script_version_cache"

#################################
# Program versions for fallback #
#                               #
#################################
FALLBACK_SEVENZIP="v26.02-v1.5.7-R2"
FALLBACK_ARIA2C="1.37.0"
FALLBACK_AXEL="2.17.14"
FALLBACK_BASH="5.3"
FALLBACK_BAT="0.26.1"
FALLBACK_BSDTAR="3.8.9"
FALLBACK_CURL="8.22.0"
FALLBACK_DASH="0.5.13.5"
FALLBACK_DROPBEAR="2026.94"
FALLBACK_ENVX="0.6.2"
FALLBACK_FPING="5.5"
FALLBACK_GAWK="5.4.1"
FALLBACK_HEXCURSE="1.70.0"
FALLBACK_HTOP="3.5.3"
FALLBACK_LESS="709"
FALLBACK_LFTP="4.9.3"
FALLBACK_MC="4.8.33"
FALLBACK_NANO="9.2"
FALLBACK_NETCAT="1.238-1"
FALLBACK_NMAP="7.991"
FALLBACK_OKSH="7.9"
FALLBACK_OPENSSH="10.5p1"
FALLBACK_PIGZ="2.8"
FALLBACK_RIPGREP="15.2.0"
FALLBACK_RSYNC="3.5.0"
FALLBACK_SCREEN="5.0.2"
FALLBACK_SED="4.10"
FALLBACK_SOCAT="1.8.1.3"
FALLBACK_SYSTEMCTL_TUI="0.8.0"
FALLBACK_TAR="1.35"
FALLBACK_TMUX="3.7c"
FALLBACK_TNFTP="20260211"
FALLBACK_UPX="5.2.1"
FALLBACK_VIM="9.2.1046"
FALLBACK_WGET="1.25.0"
FALLBACK_WGET2="2.2.1"
FALLBACK_XZ="5.8.3"
FALLBACK_ZSH="5.9.2"
FALLBACK_ZSTD="1.5.7"
