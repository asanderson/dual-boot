#!/usr/bin/env bash
# 10-nvidia-driver.sh — official NVIDIA driver for the RTX 5090 Laptop GPU.
#
# Blackwell (RTX 50-series) GPUs are supported ONLY by the open GPU kernel
# modules — install an "-open" driver package. R595 is the current
# production branch and explicitly lists the RTX 5090 Laptop GPU; the older
# 580 branch (CUDA 13.x era) also supports Blackwell.
#
# Usage: 10-nvidia-driver.sh [--check-releases]
#
# Firmware/driver prechecks follow the repo's release-check contract:
# interactive runs check FIRST (BIOS/firmware via fwupd, plus whether an
# installed NVIDIA driver has a newer package or branch); non-interactive
# runs (DEV_SETUP_ASSUME_YES=1) check only with --check-releases, and
# firmware is never flashed unattended.
#
# Run, reboot, then verify with: nvidia-smi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../../common/lib/common.sh
source "${REPO_ROOT}/common/lib/common.sh"
# shellcheck source=../../../common/lib/plan.sh
source "${REPO_ROOT}/common/lib/plan.sh"
# shellcheck source=../config/versions.env
source "${DEVICE_DIR}/config/versions.env"

usage() {
  echo "Usage: $0 [--check-releases] [--secure-boot|--no-secure-boot]"
  echo "          [--encrypt|--no-encrypt] [--wifi-ssid NAME] [--wifi-password PW]"
  echo "          [--wifi-security T] [--wifi-hidden] [--plan-file FILE]"
  usage_common_flags
}

# shellcheck disable=SC2034  # consumed by parse_common_args in common/lib/args.sh
COMMON_ARGS_ACCEPT="check-releases secure-boot encrypt wifi plan-file"
parse_common_args "$@"

main() {
  require_not_root
  require_ubuntu "26.04"
  require_sudo

  # Wi-Fi first (from the common plan / --wifi-* flags): on a fresh install
  # this can be exactly what brings the network up for everything below.
  section "Wi-Fi configuration (from the plan)"
  wifi_apply_plan

  require_network

  section "NVIDIA driver (RTX 5090 Laptop GPU / Blackwell)"

  if ! lspci -nn 2>/dev/null | grep -qi 'nvidia'; then
    die "No NVIDIA GPU visible on PCI. If this is the Raider, check BIOS GPU/hybrid settings."
  fi

  # ---- Firmware & driver update prechecks -----------------------------------
  if [[ "$CHECK_RELEASES" != "1" ]]; then
    log "Firmware/driver update prechecks skipped (non-interactive run without --check-releases)."
  else
    section "Firmware update precheck"
    apt_update_once
    firmware_update_check
    log "MSI publishes Raider BIOS/EC updates through MSI Center (on the Windows"
    log "side) or USB flash from msi.com — those vendor channels aren't automated"
    log "here; check them when fwupd/LVFS shows nothing."

    section "NVIDIA driver update precheck"
    local installed_pkg inst cand
    installed_pkg="$(dpkg -l 'nvidia-driver-*' 2>/dev/null | awk '/^ii/{print $2; exit}' || true)"
    if [[ -n "$installed_pkg" ]]; then
      inst="$(apt-cache policy "$installed_pkg" | awk '/Installed:/{print $2}')"
      cand="$(apt-cache policy "$installed_pkg" | awk '/Candidate:/{print $2}')"
      if [[ -n "$cand" && "$cand" != "$inst" ]]; then
        warn "${installed_pkg}: newer package available (${inst} -> ${cand}) — continuing below installs it."
      else
        ok "${installed_pkg} ${inst} is current for its branch (a newer BRANCH shows under 'Detected driver options' below)."
      fi
    else
      log "No NVIDIA driver installed yet — fresh install below."
    fi

    section "Component driver/firmware prechecks (Raider 18 HX AI)"
    pkg_update_check linux-firmware "Killer BE1750 Wi-Fi 7 (iwlwifi), Bluetooth, and GPU device firmware"
    pkg_update_check intel-microcode "Core Ultra 9 285HX CPU microcode"
    pkg_update_check libgl1-mesa-dri "Intel iGPU userspace (the other half of hybrid graphics)"
  fi

  # ---- Secure Boot ---------------------------------------------------------
  apt_install mokutil
  if mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
    warn "Secure Boot is ENABLED. Ubuntu will sign the NVIDIA modules with a"
    warn "Machine Owner Key (MOK). You will be asked to set a one-time password;"
    warn "on the next reboot a blue 'MOK management' screen appears:"
    warn "  Enroll MOK -> Continue -> Yes -> enter that password -> reboot."
    warn "If you skip enrollment the driver will NOT load."
    confirm "Understood — continue?" y || exit 1
  else
    log "Secure Boot is disabled; no MOK enrollment needed."
  fi

  # ---- Pick and install the driver ----------------------------------------
  apt_install ubuntu-drivers-common
  section "Detected driver options"
  ubuntu-drivers devices || true

  local recommended
  recommended="$(ubuntu-drivers devices 2>/dev/null | awk '/recommended/ {print $3; exit}')"

  local target=""
  if [[ -n "$recommended" ]]; then
    if [[ "$recommended" == *-open ]]; then
      target="$recommended"
    else
      # Blackwell requires the open kernel modules — prefer the -open variant
      # of the recommended branch when the recommendation isn't already open.
      if apt-cache show "${recommended}-open" >/dev/null 2>&1; then
        target="${recommended}-open"
      else
        target="$recommended"
        warn "No '-open' variant of ${recommended} found; using it as-is."
      fi
    fi
  else
    target="nvidia-driver-${NVIDIA_DRIVER_BRANCH}-open"
    warn "ubuntu-drivers made no recommendation; falling back to ${target}."
  fi

  log "Installing: ${target}"
  confirm "Proceed with ${target}?" y || die "Aborted."
  apt_install "${target}"

  # nvidia-smi & friends come with the driver metapackage; CUDA toolkit is optional.
  if confirm "Also install the CUDA toolkit (nvcc, ~3GB — for compiling GPU code)?" n; then
    apt_install nvidia-cuda-toolkit || warn "CUDA toolkit install failed; you can use NVIDIA's cuda repo instead."
  fi

  # Read-only check that this install matches the common plan's Secure Boot
  # and encryption decisions (UEFI Secure Boot works here — drivers are
  # MOK-signed; encryption is the Ubuntu installer's LUKS choice).
  section "Security plan verification (Secure Boot + encryption)"
  verify_security_plan

  section "Done — reboot required"
  ok "Driver installed: ${target}"
  log "1. sudo reboot"
  log "2. If prompted, complete MOK enrollment (see above)."
  log "3. Verify: nvidia-smi   (should list 'GeForce RTX 5090 Laptop GPU')"
  log "4. Hybrid graphics: 'prime-select query' shows the mode; 'on-demand' (default)"
  log "   renders on Intel and offloads to NVIDIA per-app; 'sudo prime-select nvidia'"
  log "   forces the dGPU (better for external displays wired to the dGPU)."
}

main "$@"
