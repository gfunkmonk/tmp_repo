#!/bin/bash
# build-all.sh - Orchestrator for building all (or selected) static-musl tools.
#
# Usage: build-all.sh [OPTIONS] [TOOL...]
#
# Options:
#   -a ARCH[,ARCH,...]  Architectures to build (default: x86_64,x86,aarch64,armv7)
#   -j N                Number of parallel jobs (default: 1)
#   -l                  List available tools and exit
#   -h                  Show this help message and exit
#
# Examples:
#   ./build-all.sh                          # build all tools for all architectures
#   ./build-all.sh curl wget                # build only curl and wget for all architectures
#   ./build-all.sh -a x86_64 -j 4          # build all tools for x86_64 with 4 parallel jobs
#   ./build-all.sh -a aarch64,armv7 curl   # build curl for aarch64 and armv7

set -euo pipefail
cd "$(dirname "$0")"

ALL_TOOLS=(7zz aria2c axel bash bsdtar curl dash htop less lftp nano oksh openssh pigz tar upx vim wget xz)
ALL_ARCHS=(x86_64 x86 aarch64 armv7)

SELECTED_TOOLS=()
SELECTED_ARCHS=()
JOBS=1
LIST_ONLY=false

usage() {
  sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'
}

while getopts ":a:j:lh" opt; do
  case "${opt}" in
    a) IFS=',' read -ra SELECTED_ARCHS <<< "${OPTARG}" ;;
    j) JOBS="${OPTARG}" ;;
    l) LIST_ONLY=true ;;
    h) usage; exit 0 ;;
    :) echo "Option -${OPTARG} requires an argument." >&2; usage; exit 1 ;;
    \?) echo "Unknown option: -${OPTARG}" >&2; usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

[[ ${#SELECTED_ARCHS[@]} -eq 0 ]] && SELECTED_ARCHS=("${ALL_ARCHS[@]}")
[[ $# -gt 0 ]] && SELECTED_TOOLS=("$@") || SELECTED_TOOLS=("${ALL_TOOLS[@]}")

if "${LIST_ONLY}"; then
  echo "Available tools: ${ALL_TOOLS[*]}"
  echo "Available architectures: ${ALL_ARCHS[*]}"
  exit 0
fi

PASS=()
FAIL=()
PIDS=()
LOGDIR="$(mktemp -d /tmp/build-all-logs.XXXXXX)"

run_build() {
  local tool="$1" arch="$2"
  local logfile="${LOGDIR}/${tool}-${arch}.log"
  ARCH="${arch}" GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
    bash "./${tool}-static-musl.sh" > "${logfile}" 2>&1
}

echo "Building: ${SELECTED_TOOLS[*]}"
echo "Architectures: ${SELECTED_ARCHS[*]}"
echo "Parallel jobs: ${JOBS}"
echo

for tool in "${SELECTED_TOOLS[@]}"; do
  script="./${tool}-static-musl.sh"
  if [[ ! -f "${script}" ]]; then
    echo "WARNING: ${script} not found, skipping '${tool}'" >&2
    continue
  fi

  for arch in "${SELECTED_ARCHS[@]}"; do
    label="${tool}/${arch}"
    if [[ "${JOBS}" -le 1 ]]; then
      echo "==> Building ${label} ..."
      if run_build "${tool}" "${arch}"; then
        PASS+=("${label}")
        echo "    OK: ${label}"
      else
        FAIL+=("${label}")
        echo "    FAILED: ${label} (see ${LOGDIR}/${tool}-${arch}.log)"
      fi
    else
      # Parallel mode: launch job, throttle to JOBS concurrent processes.
      while [[ ${#PIDS[@]} -ge ${JOBS} ]]; do
        new_pids=()
        for pid in "${PIDS[@]}"; do
          if kill -0 "${pid}" 2>/dev/null; then
            new_pids+=("${pid}")
          fi
        done
        PIDS=("${new_pids[@]+"${new_pids[@]}"}")
        [[ ${#PIDS[@]} -ge ${JOBS} ]] && sleep 1
      done

      echo "==> Starting ${label} (background) ..."
      (
        if run_build "${tool}" "${arch}"; then
          echo "PASS ${label}" >> "${LOGDIR}/results.txt"
        else
          echo "FAIL ${label}" >> "${LOGDIR}/results.txt"
        fi
      ) &
      PIDS+=($!)
    fi
  done
done

# Wait for remaining parallel jobs.
if [[ "${JOBS}" -gt 1 ]]; then
  echo "Waiting for background jobs to complete..."
  wait
  while IFS=' ' read -r status label; do
    if [[ "${status}" == "PASS" ]]; then
      PASS+=("${label}")
    else
      FAIL+=("${label}")
    fi
  done < <(sort "${LOGDIR}/results.txt" 2>/dev/null || true)
fi

echo
echo "===== Build Summary ====="
echo "Passed: ${#PASS[@]}"
for l in "${PASS[@]}"; do echo "  OK  ${l}"; done
echo "Failed: ${#FAIL[@]}"
for l in "${FAIL[@]}"; do echo "  ERR ${l}  (log: ${LOGDIR}/${l//\//-}.log)"; done

[[ ${#FAIL[@]} -eq 0 ]]
