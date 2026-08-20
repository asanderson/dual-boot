#!/usr/bin/env bash
# 00-install-plan.sh — the common entry point for EVERY device flow: decide
# the installation constraints once, up front, and persist them for the
# device scripts to honor.
#
# Determines: which operating systems to install (from the catalog in
# common/config/os-catalog.env — Ubuntu, Qubes OS, PureOS, Rocky Linux,
# RHEL, Windows 11 Pro/Home), whether each is a clean (destructive) install
# or an in-place upgrade, whether existing boot devices/partitions are
# backed up first, whether Secure Boot (or the device's verified-boot
# equivalent) stays enforced, whether OS disks are encrypted at install
# time, the Wi-Fi settings the installed systems should get (SSID,
# password, security type, hidden-network — applied by the device scripts
# via NetworkManager), the boot partition size, and the target disk. Then
# runs the release checks for the chosen OSes and (if selected) performs
# the non-destructive boot-state backup.
#
# Usage: 00-install-plan.sh [--check-releases] [--os LIST] [--mode OS=MODE]
#                           [--backup|--no-backup]
#                           [--secure-boot|--no-secure-boot]
#                           [--encrypt|--no-encrypt] [--wifi-ssid NAME]
#                           [--wifi-password PW] [--wifi-security T]
#                           [--wifi-hidden] [--disk DEV]
#                           [--boot-size GIB] [--plan-file FILE]
#
# Contract (same as every script here): interactive runs prompt for each
# decision and always run the release checks first; non-interactive runs
# (DEV_SETUP_ASSUME_YES=1) take defaults / the flags above, check releases
# only with --check-releases, and NOTHING destructive exists in this script
# (the backup only writes new files). Destructive steps live in the device
# scripts, behind their own gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${COMMON_DIR}/lib/common.sh"
# shellcheck source=../config/os-catalog.env
source "${COMMON_DIR}/config/os-catalog.env"
# shellcheck source=../lib/oses.sh
source "${COMMON_DIR}/lib/oses.sh"
# shellcheck source=../lib/plan.sh
source "${COMMON_DIR}/lib/plan.sh"

# shellcheck disable=SC2034  # consumed by parse_common_args in common/lib/args.sh
COMMON_ARGS_ACCEPT="check-releases os mode backup secure-boot encrypt wifi disk boot-size plan-file"

usage() {
  echo "Usage: $0 [--check-releases] [--os LIST] [--mode OS=MODE] [--backup|--no-backup]"
  echo "          [--secure-boot|--no-secure-boot] [--encrypt|--no-encrypt]"
  echo "          [--wifi-ssid NAME] [--wifi-password PW] [--wifi-security T]"
  echo "          [--wifi-hidden] [--disk DEV] [--boot-size GIB] [--plan-file FILE]"
  usage_common_flags
}

parse_common_args "$@"

main() {
  require_not_root

  section "Operating system selection"
  plan_select_oses

  section "Install vs upgrade (per OS)"
  plan_select_modes

  section "Boot-state backup"
  plan_backup_decide

  section "Secure Boot"
  plan_secure_boot_decide

  section "Disk encryption"
  plan_encrypt_decide

  section "Wi-Fi (installed systems)"
  plan_wifi_decide

  section "Boot partition size"
  plan_boot_size_decide

  # ---- Release checks for the chosen OSes ------------------------------------
  section "Release checks"
  if [[ "$CHECK_RELEASES" != "1" ]]; then
    log "Release checks skipped (non-interactive run without --check-releases)."
  else
    require_network
    local os
    for os in ${PLAN_OSES}; do
      log "--- ${os} ---"
      os_release_check "$os"
    done
  fi

  # ---- Backup (non-destructive: writes new files only) -----------------------
  if [[ "${PLAN_BACKUP}" == "1" ]]; then
    section "Backing up the existing boot state"
    require_sudo
    backup_boot_state "${TARGET_DISK:-}" "${HOME}/dual-boot-backups"
  fi

  plan_summary
  plan_write "${PLAN_FILE}"

  section "Next steps"
  log "Run your device's scripts — they read ${PLAN_FILE} and honor this plan:"
  log "  devices/msi-raider-18-hx-ai/  devices/macbook-pro-14-3/  devices/librem-14-v1/"
  log "OS notes: RHEL media needs a Red Hat login; the Windows 11 multi-edition"
  log "ISO comes from ${WIN11_DOWNLOAD_URL} (manual download); Rocky/Qubes/PureOS"
  log "images are fetched and verified by the device scripts. See"
  log "common/docs/install-plan.md for the catalog and per-OS specifics."
}

main
