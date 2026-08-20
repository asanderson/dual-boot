#!/usr/bin/env bash
# 10-dual-install-prep.sh — prepare the Librem 14 v1 for a CLEAN DUAL INSTALL
# of Qubes OS + PureOS: firmware precheck, release checks, ISO download +
# verification, installer USB writing, and the (destructive) disk wipe +
# partition layout.
#
# THIS DEVICE'S DEFAULT IS DESTRUCTIVE: the factory PureOS install is wiped
# and both OSes are installed fresh. Unlike the other devices in this repo,
# nothing on the internal SSD is preserved.
#
# Usage: 10-dual-install-prep.sh [--check-releases] [--destructive]
#                                [--backup|--no-backup]
#                                [--secure-boot|--no-secure-boot]
#                                [--encrypt|--no-encrypt] [--disk DEV]
#                                [--boot-size GIB] [--download-dir DIR]
#                                [--usb-qubes DEV] [--usb-pureos DEV]
#                                [--plan-file FILE]
#
# Honors a plan written by common/scripts/00-install-plan.sh (boot size,
# backup decision, Secure Boot, disk encryption, target disk); explicit
# flags override the plan. The
# shared contract applies: interactive runs check releases first and confirm
# the wipe (default YES — this device's documented default); unattended runs
# check only with --check-releases and NEVER touch the disk without
# --destructive. Refuses to run on other hardware (DMI check) and to wipe
# the disk hosting the running system — run the destructive step from a
# live USB.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../../common/lib/common.sh
source "${REPO_ROOT}/common/lib/common.sh"
# shellcheck source=../../../common/config/os-catalog.env
source "${REPO_ROOT}/common/config/os-catalog.env"
# shellcheck source=../../../common/lib/oses.sh
source "${REPO_ROOT}/common/lib/oses.sh"
# shellcheck source=../../../common/lib/plan.sh
source "${REPO_ROOT}/common/lib/plan.sh"
# shellcheck source=../config/versions.env
source "${DEVICE_DIR}/config/versions.env"

usage() {
  echo "Usage: $0 [--check-releases] [--destructive] [--backup|--no-backup]"
  echo "          [--secure-boot|--no-secure-boot] [--encrypt|--no-encrypt]"
  echo "          [--disk DEV] [--boot-size GIB] [--download-dir DIR]"
  echo "          [--usb-qubes DEV] [--usb-pureos DEV] [--plan-file FILE]"
  usage_common_flags
}

# shellcheck disable=SC2034  # consumed by parse_common_args in common/lib/args.sh
COMMON_ARGS_ACCEPT="check-releases destructive backup secure-boot encrypt disk boot-size download-dir usb plan-file"
parse_common_args "$@"

# Honor a plan from 00-install-plan.sh: plan values become the defaults for
# anything not set explicitly by a flag on this invocation.
apply_plan() {
  [[ -f "$PLAN_FILE" ]] || return 0
  # shellcheck disable=SC1090
  source "$PLAN_FILE"
  log "Honoring plan ${PLAN_FILE} (flags on this invocation override it)."
  [[ -z "${BACKUP}" && -n "${DUAL_BOOT_PLAN_BACKUP:-}" ]] && BACKUP="${DUAL_BOOT_PLAN_BACKUP}"
  [[ -z "${SECURE_BOOT}" && -n "${DUAL_BOOT_PLAN_SECURE_BOOT:-}" ]] && SECURE_BOOT="${DUAL_BOOT_PLAN_SECURE_BOOT}"
  [[ -z "${ENCRYPT_DISKS}" && -n "${DUAL_BOOT_PLAN_ENCRYPT:-}" ]] && ENCRYPT_DISKS="${DUAL_BOOT_PLAN_ENCRYPT}"
  [[ -z "${BOOT_GIB_SET}" && -n "${DUAL_BOOT_PLAN_BOOT_GIB:-}" ]] && BOOT_GIB="${DUAL_BOOT_PLAN_BOOT_GIB}"
  [[ -z "${TARGET_DISK_SET}" && -n "${DUAL_BOOT_PLAN_DISK:-}" ]] && TARGET_DISK="${DUAL_BOOT_PLAN_DISK}"
  if [[ -n "${DUAL_BOOT_PLAN_OSES:-}" && "${DUAL_BOOT_PLAN_OSES}" != *qubes* ]]; then
    warn "The plan's OS list (${DUAL_BOOT_PLAN_OSES}) does not include qubes —"
    warn "this device flow installs Qubes OS + PureOS; re-run 00-install-plan.sh"
    warn "with '--os qubes,pureos' if that plan was meant for this machine."
  fi
}

# The Librem 14 pin inside Purism's own flashing utility — the vendor's
# source of truth for the currently shipped PureBoot release.
latest_pureboot_release() {
  fetch --max-time 20 "${PUREBOOT_UTIL_URL}" 2>/dev/null \
    | sed -n 's/^PUREBOOT_VERSION_14="\(.*\)"/\1/p' | head -1
}

main() {
  require_not_root

  section "Hardware check"
  local vendor product
  vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo unknown)"
  product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
  if [[ "$vendor" != "Purism"* || "$product" != *"Librem 14"* ]]; then
    die "This script targets the Librem 14 (Purism) — detected: ${vendor} ${product}."
  fi
  ok "Running on ${vendor} ${product}."

  apply_plan

  warn "THIS FLOW IS DESTRUCTIVE BY DESIGN: the internal SSD (${TARGET_DISK}) will be"
  warn "wiped and both Qubes OS and PureOS installed fresh. The factory PureOS"
  warn "install is NOT preserved. Copy anything you need off this machine first."

  require_sudo
  require_network
  apt_install curl gnupg gdisk

  # ---- Firmware precheck (PureBoot / Librem EC) -------------------------------
  section "Firmware update precheck (PureBoot / Librem EC)"
  if [[ "$CHECK_RELEASES" != "1" ]]; then
    log "Firmware precheck skipped (non-interactive run without --check-releases)."
  else
    firmware_update_check
    local latest_pb
    latest_pb="$(latest_pureboot_release || true)"
    if [[ -n "$latest_pb" ]]; then
      log "Latest PureBoot release: ${latest_pb} (pinned: ${PUREBOOT_VERSION})"
      [[ "$latest_pb" != "$PUREBOOT_VERSION" ]] && \
        warn "Pinned PUREBOOT_VERSION (${PUREBOOT_VERSION}) differs from the latest (${latest_pb}) — update config/versions.env after a successful run."
    else
      warn "Could not determine the latest PureBoot release; pinned: ${PUREBOOT_VERSION}."
    fi
    warn "PureBoot/EC firmware updates are NEVER flashed by this script: update"
    warn "via Purism's utility (${PUREBOOT_UTIL_URL}) or from the PureBoot menu"
    warn "BEFORE installing the OSes. On this anti-interdiction unit, re-verify"
    warn "tamper evidence and re-sign /boot with the Librem Key after any flash."

    section "Component driver prechecks (Librem 14)"
    log "Wi-Fi/BT (Atheros QCNFA222, ath9k): fully free in-kernel driver and"
    log "  firmware — no proprietary blob updates exist or are needed."
    log "CPU microcode (i7-10710U): delivered through PureBoot firmware updates"
    log "  (checked above), not distro packages — PureOS ships no proprietary"
    log "  microcode by design."
    log "EC-managed input/battery/fans: install the librem-ec-acpi DKMS driver"
    log "  on the installed OSes (dom0 for Qubes) — see the runbook quirks."
  fi

  # ---- Security plan (Secure Boot + disk encryption) --------------------------
  section "Security plan (Secure Boot + disk encryption)"
  if [[ -z "${SECURE_BOOT}" ]]; then
    plan_secure_boot_decide
    SECURE_BOOT="$PLAN_SECURE_BOOT"
  fi
  if [[ "${SECURE_BOOT}" == "1" ]]; then
    log "Verified boot: this device has NO UEFI Secure Boot — PureBoot/Heads"
    log "  supersedes it (TPM-sealed HOTP tamper check + GPG-signed /boot,"
    log "  verified with the Librem Key). The plan's requirement is satisfied;"
    log "  re-sign /boot in PureBoot after both installs."
  else
    warn "Plan says Secure Boot is not required — note PureBoot's verified boot"
    warn "  stays active regardless (it IS this device's firmware); disabling it"
    warn "  would mean reflashing stock coreboot, which this repo does not do."
  fi
  if [[ -z "${ENCRYPT_DISKS}" ]]; then
    plan_encrypt_decide
    ENCRYPT_DISKS="$PLAN_ENCRYPT"
  fi
  if [[ "${ENCRYPT_DISKS}" == "1" ]]; then
    log "Disk encryption: choose LUKS in BOTH installers — Qubes encrypts by"
    log "  default; in the PureOS installer explicitly select encryption for"
    log "  its partition. /boot (partition 1) stays unencrypted and is signed"
    log "  by PureBoot instead."
  else
    warn "Plan says NO disk encryption: deselect it in both installers if you"
    warn "  really want that — on an anti-interdiction unit this is strongly"
    warn "  discouraged (the runbook and partition labels assume LUKS)."
  fi

  # ---- Release checks (interactive always; unattended only with the flag) ----
  section "Qubes OS + PureOS release checks"
  if [[ "$CHECK_RELEASES" != "1" ]]; then
    log "Release checks skipped (non-interactive run without --check-releases)."
  else
    os_release_check qubes
    os_release_check pureos
  fi

  # ---- ISO download + verification ---------------------------------------
  section "Installer images (download + verification)"
  local qubes_iso="Qubes-R${QUBES_VERSION}-x86_64.iso"
  local pureos_iso="${PUREOS_IMAGE}"
  if confirm "Download and verify both installer images into ${DOWNLOAD_DIR} (~10GB)?" y; then
    os_fetch_verify_qubes "$DOWNLOAD_DIR"
    os_fetch_verify_pureos "$DOWNLOAD_DIR"
  else
    log "Skipped image downloads (re-run this script when ready)."
  fi

  # ---- Installer USB sticks ---------------------------------------------------
  section "Installer USB sticks"
  local usb _os dev iso
  for usb in "qubes:${USB_QUBES}:${qubes_iso}" "pureos:${USB_PUREOS}:${pureos_iso}"; do
    IFS=: read -r _os dev iso <<<"$usb"
    [[ -z "$dev" ]] && { log "No --usb-${_os} device given — write it later: sudo dd if=${DOWNLOAD_DIR}/${iso} of=/dev/sdX bs=4M status=progress oflag=sync"; continue; }
    [[ -b "$dev" ]] || die "--usb-${_os}: ${dev} is not a block device."
    [[ -f "${DOWNLOAD_DIR}/${iso}" ]] || die "--usb-${_os}: ${DOWNLOAD_DIR}/${iso} not downloaded yet."
    if confirm "Write ${iso} to ${dev} (ERASES that stick)?" y; then
      sudo dd if="${DOWNLOAD_DIR}/${iso}" of="$dev" bs=4M status=progress oflag=sync
      ok "${_os} installer written to ${dev}."
    fi
  done

  # ---- Destructive disk preparation -------------------------------------------
  section "Destructive disk preparation (${TARGET_DISK})"
  if destructive_gate "WIPE ${TARGET_DISK} COMPLETELY and create the Qubes+PureOS partition layout? ALL DATA ON IT IS DESTROYED"; then
    [[ -b "$TARGET_DISK" ]] || die "${TARGET_DISK} is not a block device."
    # Never wipe the disk hosting the running system: the factory PureOS lives
    # on the internal SSD, so this step runs from the PureOS live USB.
    local root_src
    root_src="$(findmnt -no SOURCE / 2>/dev/null || true)"
    if [[ -n "$root_src" ]] && [[ "$(lsblk -no PKNAME "$root_src" 2>/dev/null || true)" == "$(basename "$TARGET_DISK")" ]]; then
      die "${TARGET_DISK} hosts the running system — boot the PureOS live USB and run this step from there."
    fi
    # Back up the existing partition table and boot partitions first, per the
    # plan (or the --backup/--no-backup flags; default: prompted, yes).
    if [[ -z "${BACKUP}" ]]; then
      plan_backup_decide
      BACKUP="$PLAN_BACKUP"
    fi
    [[ "$BACKUP" == "1" ]] && backup_boot_state "$TARGET_DISK" "${HOME}/dual-boot-backups"
    log "Creating the dual-OS GPT layout on ${TARGET_DISK}:"
    log "  1  ${BOOT_GIB}GiB   shared /boot (ext4, unencrypted — PureBoot/Heads tracks ONE"
    log "            /boot device, signs its contents, and lists both OSes' entries)"
    log "  2  ${QUBES_LUKS_GIB}GiB  Qubes LUKS (root/swap via LVM, laid down by the Qubes installer)"
    log "  3  rest    PureOS LUKS (root, laid down by the PureOS installer)"
    sudo sgdisk --zap-all "$TARGET_DISK"
    sudo sgdisk -n "1:0:+${BOOT_GIB}GiB"       -t 1:8300 -c 1:boot        "$TARGET_DISK"
    sudo sgdisk -n "2:0:+${QUBES_LUKS_GIB}GiB" -t 2:8309 -c 2:qubes-luks  "$TARGET_DISK"
    sudo sgdisk -n "3:0:0"                     -t 3:8309 -c 3:pureos-luks "$TARGET_DISK"
    sudo partprobe "$TARGET_DISK" 2>/dev/null || true
    ok "Layout written. Both installers must use 'custom / manual partitioning'"
    ok "against these partitions — never 'erase disk' — and the SECOND install"
    ok "must reuse partition 1 as /boot WITHOUT reformatting it. See the runbook."
  else
    log "Disk untouched. Re-run when ready, or partition manually per the runbook."
  fi

  section "Done"
  log "Next: devices/librem-14-v1/docs/qubes-pureos-dual-install.md"
  log "  install Qubes OS first (partitions 1+2), PureOS second (partition 3,"
  log "  reusing 1 as /boot unformatted), then in PureBoot: Options -> Update"
  log "  checksums and sign all files in /boot (Librem Key + GPG PIN)."
}

main
