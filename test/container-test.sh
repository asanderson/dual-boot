#!/usr/bin/env bash
# container-test.sh — run this repo's scripts in a fresh Ubuntu container and
# assert the documented behavior of both unattended modes:
#
#   1. 20-kernel.sh (no flag, DEV_SETUP_ASSUME_YES=1) skips release checks
#      and installs nothing.
#   2. 20-kernel.sh --check-releases runs the Ubuntu release check and
#      installs the newest packaged kernel.
#   3. 10-nvidia-driver.sh fails gracefully when no NVIDIA GPU is present.
#
# Usage: ./test/container-test.sh [--gpu-path]
#
#   --gpu-path   instead of the default assertions, exercise the GPU-present
#                path of 10-nvidia-driver.sh with an lspci stub exposing the
#                MSI Raider's RTX 5090: real driver package install plus all
#                three driver-selection branches (see test/gpu-path-init.sh).
#
# Env:
#   DEV_SETUP_TEST_IMAGE   container image (default ubuntu:26.04)
#   https_proxy            forwarded into the container if set; a CA bundle
#                          at /root/.ccr/ca-bundle.crt is auto-mounted for
#                          CONNECT-only MITM proxies (sandbox/CI setups).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE="${DEV_SETUP_TEST_IMAGE:-ubuntu:26.04}"

INIT="container-init.sh"
for arg in "$@"; do
  case "$arg" in
    --gpu-path) INIT="gpu-path-init.sh" ;;
    *) echo "error: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

DOCKER_ARGS=(--rm --network host -v "${REPO_ROOT}:/repo:ro")
if [[ -n "${https_proxy:-}" ]]; then
  DOCKER_ARGS+=(-e https_proxy -e no_proxy)
  [[ -f /root/.ccr/ca-bundle.crt ]] && DOCKER_ARGS+=(-v /root/.ccr/ca-bundle.crt:/ccr-ca.crt:ro)
fi

echo ">>> image: ${IMAGE} (${INIT})"
docker run "${DOCKER_ARGS[@]}" "${IMAGE}" bash "/repo/test/${INIT}"
