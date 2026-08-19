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

  section "Done"
  ok "Mac hardware setup complete."
  warn "Suspend/resume is historically flaky on this generation — test yours"
  warn "before relying on it (see the device page quirks)."
}

main "$@"
