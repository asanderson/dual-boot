#!/usr/bin/env bash
# 10-mac-setup.sh — Linux-side hardware setup for the MacBook Pro
# (15-inch, 2017; MacBookPro14,3): verify Wi-Fi firmware, check the Apple
# SPI input devices, and offer fan control. Run on the installed Ubuntu.
#
# Refuses to run on other hardware (DMI product check) so a copy-paste on
# the wrong machine changes nothing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../../common/lib/common.sh
source "${REPO_ROOT}/common/lib/common.sh"

usage() {
  echo "Usage: $0 [--check-releases]"
  usage_common_flags
}

# shellcheck disable=SC2034  # consumed by parse_common_args in common/lib/args.sh
COMMON_ARGS_ACCEPT="check-releases"
parse_common_args "$@"

main() {
  require_not_root
  require_ubuntu "26.04"

  section "Hardware check"
  local product
  product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
  if [[ "$product" != "MacBookPro14,3" ]]; then
    die "This script targets the MacBook Pro (15-inch, 2017; MacBookPro14,3) — detected: ${product}."
  fi
  ok "Running on ${product}."

  require_sudo
  require_network

  # ---- Firmware & driver update prechecks ------------------------------------
  if [[ "$CHECK_RELEASES" != "1" ]]; then
    log "Firmware/driver update prechecks skipped (non-interactive run without --check-releases)."
  else
    section "Firmware update precheck"
    apt_update_once
    firmware_update_check
    log "Apple EFI/SMC firmware updates ship only through macOS — boot the"
    log "OCLP-managed macOS side periodically so it can receive them."
    if apt list --upgradable 2>/dev/null | grep -q '^linux-firmware/'; then
      warn "A newer linux-firmware package is available (Wi-Fi/GPU device firmware)."
      if confirm "Update linux-firmware now?" y; then apt_install linux-firmware; fi
    else
      ok "linux-firmware is current (drivers themselves update with the kernel — checked at the end)."
    fi
  fi

  # ---- Wi-Fi / Bluetooth (Broadcom BCM43602 via brcmfmac) -------------------
  section "Wi-Fi firmware (BCM43602 / brcmfmac)"
  if ls /lib/firmware/brcm/brcmfmac43602* >/dev/null 2>&1; then
    ok "brcmfmac43602 firmware present (shipped by linux-firmware)."
  else
    warn "brcmfmac43602 firmware not found — updating linux-firmware."
    apt_install linux-firmware
  fi
  if sudo dmesg | grep -iq 'brcmfmac.*firmware.*fail'; then
    warn "dmesg shows brcmfmac firmware errors — see the device page quirks."
  else
    ok "No brcmfmac firmware errors in dmesg."
  fi

  # ---- Input devices (Apple SPI keyboard/trackpad) ---------------------------
  section "Keyboard / trackpad (applespi)"
  if grep -rqs applespi /proc/bus/input/devices /sys/bus/spi/drivers 2>/dev/null; then
    ok "applespi driver active — internal keyboard/trackpad handled in-kernel."
  else
    warn "applespi not detected; if the internal keyboard works you can ignore this,"
    warn "otherwise check 'sudo dmesg | grep -i applespi'."
  fi
  log "Touch Bar: expect it blank under Linux (no full mainline support);"
  log "the physical fn layer provides function keys."

  # ---- Fan control -----------------------------------------------------------
  section "Fan control"
  if confirm "Install mbpfan (automatic fan curves via applesmc sensors)?" y; then
    apt_install mbpfan
    sudo systemctl enable --now mbpfan 2>/dev/null || true
    ok "mbpfan installed and enabled."
  fi

  # ---- Ubuntu release & kernel updates (shared script) -----------------------
  section "Ubuntu release & kernel updates"
  local kernel_script="${REPO_ROOT}/common/ubuntu/scripts/20-kernel.sh"
  if [[ "$CHECK_RELEASES" != "1" ]]; then
    log "Ubuntu/kernel release check skipped (non-interactive run without --check-releases)."
  elif confirm "Check for the latest Ubuntu release and kernel patches now (common/ubuntu/scripts/20-kernel.sh)?" y; then
    "$kernel_script" --check-releases
  fi

  section "Done"
  ok "Mac hardware setup complete."
  warn "Suspend/resume is historically flaky on this generation — test yours"
  warn "before relying on it (see the device page quirks)."
}

main "$@"
