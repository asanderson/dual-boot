#!/usr/bin/env bash
# 10-dual-install-prep.sh — prepare the Librem 14 v1 for a CLEAN DUAL INSTALL
# of Qubes OS + PureOS: release checks, ISO download + GPG verification,
# installer USB writing, and the (destructive) disk wipe + partition layout.
#
# THIS DEVICE'S DEFAULT IS DESTRUCTIVE: the factory PureOS install is wiped
# and both OSes are installed fresh. Unlike the other devices in this repo,
# nothing on the internal SSD is preserved.
#
# Usage: 10-dual-install-prep.sh [--check-releases] [--destructive]
#                                [--disk DEV] [--download-dir DIR]
#                                [--usb-qubes DEV] [--usb-pureos DEV]
#
# Modes (release checks follow the same contract as 20-kernel.sh):
#   Interactive (default): FIRST checks the latest Qubes OS and PureOS
#     releases; every step prompts. The disk wipe is the DEFAULT — the
#     confirmation prompt defaults to yes — but a human must be present.
#   Non-interactive (DEV_SETUP_ASSUME_YES=1): release checks are skipped
#     unless --check-releases is passed, and the DISK IS NEVER TOUCHED unless
#     --destructive is passed. This gate is deliberate: confirm() takes each
#     prompt's default when unattended, and a default-yes disk wipe must not
#     be reachable without an explicit flag.
#
# Refuses to run on other hardware (DMI check), and refuses to wipe a disk
# that hosts the running system — run the destructive step from a live USB.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../../common/lib/common.sh
source "${REPO_ROOT}/common/lib/common.sh"
# shellcheck source=../config/versions.env
source "${DEVICE_DIR}/config/versions.env"

usage() {
  echo "Usage: $0 [--check-releases] [--destructive] [--disk DEV] [--download-dir DIR]"
  echo "          [--usb-qubes DEV] [--usb-pureos DEV]"
  echo "  --check-releases   in non-interactive mode (DEV_SETUP_ASSUME_YES=1), also"
  echo "                     check for the latest Qubes OS and PureOS releases"
  echo "                     (interactive mode always checks first)"
  echo "  --destructive      in non-interactive mode, authorize the FULL WIPE of the"
  echo "                     target disk and creation of the dual-OS layout; without"
  echo "                     it an unattended run never touches the disk"
  echo "                     (interactive mode instead confirms, defaulting to yes)"
  echo "  --disk DEV         target disk (default: ${TARGET_DISK_DEFAULT})"
  echo "  --download-dir DIR where ISOs are downloaded (default: ~/dual-boot-isos)"
  echo "  --usb-qubes DEV    write the Qubes installer to this USB device"
  echo "  --usb-pureos DEV   write the PureOS installer to this USB device"
}

CHECK_RELEASES=""
DESTRUCTIVE=""
DISK="${TARGET_DISK_DEFAULT}"
DOWNLOAD_DIR="${HOME}/dual-boot-isos"
USB_QUBES=""
USB_PUREOS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-releases) CHECK_RELEASES=1 ;;
    --destructive)    DESTRUCTIVE=1 ;;
    --disk)           DISK="${2:?--disk needs a device}"; shift ;;
    --download-dir)   DOWNLOAD_DIR="${2:?--download-dir needs a path}"; shift ;;
    --usb-qubes)      USB_QUBES="${2:?--usb-qubes needs a device}"; shift ;;
    --usb-pureos)     USB_PUREOS="${2:?--usb-pureos needs a device}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown argument: $1"; usage; exit 2 ;;
  esac
  shift
done
[[ "${DEV_SETUP_ASSUME_YES:-0}" != "1" ]] && CHECK_RELEASES=1
CHECK_RELEASES="${CHECK_RELEASES:-0}"

# latest_qubes_version / latest_pureos_imageset — best-effort scrape of the
# official download endpoints; empty output means "could not determine".
latest_qubes_version() {
  fetch --max-time 20 "${QUBES_ISO_DIR_URL}/" 2>/dev/null \
    | grep -oE 'Qubes-R[0-9]+\.[0-9]+(\.[0-9]+)?-x86_64\.iso' \
    | grep -oE 'R[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -uV | tail -1
}
latest_pureos_imageset() {
  # PureOS publishes dated image sets per codename (e.g. crimson/2026.05/).
  fetch --max-time 20 "${PUREOS_IMAGES_ROOT_URL}/" 2>/dev/null \
    | grep -oE '20[0-9]{2}\.[0-9]{2}' | sort -uV | tail -1
}
latest_pureboot_release() {
  # The Librem 14 pin inside Purism's own flashing utility — the vendor's
  # source of truth for the currently shipped PureBoot release.
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

  warn "THIS FLOW IS DESTRUCTIVE BY DESIGN: the internal SSD (${DISK}) will be"
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
  fi

  # ---- Release checks (interactive always; unattended only with the flag) ----
  section "Qubes OS + PureOS release checks"
  if [[ "$CHECK_RELEASES" != "1" ]]; then
    log "Release checks skipped (non-interactive run without --check-releases)."
  else
    local latest_q latest_p
    latest_q="$(latest_qubes_version || true)"
    if [[ -n "$latest_q" ]]; then
      log "Latest Qubes OS release: ${latest_q} (pinned: R${QUBES_VERSION})"
      [[ "$latest_q" != "R${QUBES_VERSION}" ]] && \
        warn "Pinned QUBES_VERSION (R${QUBES_VERSION}) differs from the latest (${latest_q}) — update config/versions.env after a successful run."
    else
      warn "Could not determine the latest Qubes release; using pin R${QUBES_VERSION}."
    fi
    latest_p="$(latest_pureos_imageset || true)"
    if [[ -n "$latest_p" ]]; then
      log "Latest PureOS ${PUREOS_VERSION} '${PUREOS_CODENAME}' image set: ${latest_p} (pinned: ${PUREOS_RELEASE_DIR})"
      [[ "$latest_p" != "$PUREOS_RELEASE_DIR" ]] && \
        warn "Pinned PUREOS_RELEASE_DIR (${PUREOS_RELEASE_DIR}) differs from the latest (${latest_p}) — update config/versions.env after a successful run."
    else
      warn "Could not determine the latest PureOS image set; using pin ${PUREOS_RELEASE_DIR}."
    fi
    log "(a successor codename to '${PUREOS_CODENAME}' would appear on pureos.net/download — check there too)"
  fi

  # ---- ISO download + signature verification ---------------------------------
  section "Installer images (download + GPG verification)"
  local qubes_iso="Qubes-R${QUBES_VERSION}-x86_64.iso"
  local pureos_iso="${PUREOS_IMAGE}"
  if confirm "Download and verify both installer images into ${DOWNLOAD_DIR} (~10GB)?" y; then
    mkdir -p "$DOWNLOAD_DIR"; cd "$DOWNLOAD_DIR"

    # Qubes: detached .asc by the release signing key, which must itself be
    # signed by the Qubes Master Signing Key (pinned fingerprint) — the chain
    # of trust from the Qubes verification docs. Hard-fail on any mismatch.
    log "Qubes OS R${QUBES_VERSION}:"
    [[ -f "$qubes_iso" ]] || fetch -O "${QUBES_ISO_DIR_URL}/${qubes_iso}"
    fetch -O "${QUBES_ISO_DIR_URL}/${qubes_iso}.asc"
    fetch -o qubes-master-key.asc "${QUBES_MASTER_KEY_URL}"
    fetch -o qubes-release-key.asc "${QUBES_RELEASE_KEY_URL}"
    export GNUPGHOME="${DOWNLOAD_DIR}/.gnupg-qubes"
    mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
    gpg -q --import qubes-master-key.asc qubes-release-key.asc
    gpg --fingerprint --with-colons 2>/dev/null | grep -q "fpr:::::::::${QUBES_MASTER_KEY_FPR}:" \
      || die "Qubes Master Signing Key fingerprint mismatch — expected ${QUBES_MASTER_KEY_FPR}. Do not proceed."
    echo "${QUBES_MASTER_KEY_FPR}:6:" | gpg -q --import-ownertrust
    gpg --check-sigs --with-colons "Qubes OS Release" 2>/dev/null \
      | grep -q "^sig:!:.*${QUBES_MASTER_KEY_FPR: -16}" \
      || die "Qubes release key is NOT signed by the pinned master key. Do not proceed."
    gpg --verify "${qubes_iso}.asc" "$qubes_iso" 2>&1 | grep -q "Good signature" \
      || die "BAD SIGNATURE on ${qubes_iso} — do not use this image."
    unset GNUPGHOME
    ok "Qubes ISO signature verified (release key chained to the pinned master key)."

    # PureOS publishes no GPG signatures — only SHA256/BLAKE2 checksum files
    # over HTTPS. Check the ISO against the sha256 pinned in versions.env AND
    # the published checksum file; hard-fail on mismatch with the pin.
    log "PureOS ${PUREOS_VERSION} '${PUREOS_CODENAME}':"
    [[ -f "$pureos_iso" ]] || fetch -O "${PUREOS_DL_BASE_URL}/${pureos_iso}"
    local iso_sha remote_sha
    iso_sha="$(sha256sum "$pureos_iso" | cut -d' ' -f1)"
    [[ "$iso_sha" == "$PUREOS_ISO_SHA256" ]] \
      || die "PureOS ISO sha256 mismatch — expected ${PUREOS_ISO_SHA256}, got ${iso_sha}. Do not use this image."
    remote_sha="$(fetch --max-time 20 "${PUREOS_DL_BASE_URL}/${pureos_iso%.iso}.checksums_sha256.txt" 2>/dev/null \
      | grep -oE '^[0-9a-f]{64}' | head -1 || true)"
    if [[ -n "$remote_sha" && "$remote_sha" != "$PUREOS_ISO_SHA256" ]]; then
      die "Published PureOS checksum (${remote_sha}) disagrees with the pin — investigate before proceeding."
    fi
    ok "PureOS ISO sha256 verified against the pin$( [[ -n "$remote_sha" ]] && echo ' and the published checksum file' )."
    cd - >/dev/null
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
  section "Destructive disk preparation (${DISK})"
  local do_wipe=""
  if [[ "${DEV_SETUP_ASSUME_YES:-0}" == "1" ]]; then
    if [[ "$DESTRUCTIVE" == "1" ]]; then
      log "--destructive passed: proceeding with the unattended wipe of ${DISK}."
      do_wipe=1
    else
      log "Unattended run without --destructive: leaving ${DISK} untouched."
      log "(pass --destructive to authorize the full wipe unattended)"
    fi
  else
    # Destructive dual install is this device's documented default: default yes.
    if confirm "WIPE ${DISK} COMPLETELY and create the Qubes+PureOS partition layout? ALL DATA ON IT IS DESTROYED" y; then
      do_wipe=1
    else
      log "Disk untouched. Re-run when ready, or partition manually per the runbook."
    fi
  fi

  if [[ -n "$do_wipe" ]]; then
    [[ -b "$DISK" ]] || die "${DISK} is not a block device."
    # Never wipe the disk hosting the running system: the factory PureOS lives
    # on the internal SSD, so this step runs from the PureOS live USB.
    local root_src
    root_src="$(findmnt -no SOURCE / 2>/dev/null || true)"
    if [[ -n "$root_src" ]] && [[ "$(lsblk -no PKNAME "$root_src" 2>/dev/null || true)" == "$(basename "$DISK")" ]]; then
      die "${DISK} hosts the running system — boot the PureOS live USB and run this step from there."
    fi
    log "Creating the dual-OS GPT layout on ${DISK}:"
    log "  1  ${BOOT_GIB}GiB   shared /boot (ext4, unencrypted — PureBoot/Heads tracks ONE"
    log "            /boot device, signs its contents, and lists both OSes' entries)"
    log "  2  ${QUBES_LUKS_GIB}GiB  Qubes LUKS (root/swap via LVM, laid down by the Qubes installer)"
    log "  3  rest    PureOS LUKS (root, laid down by the PureOS installer)"
    sudo sgdisk --zap-all "$DISK"
    sudo sgdisk -n "1:0:+${BOOT_GIB}GiB"       -t 1:8300 -c 1:boot        "$DISK"
    sudo sgdisk -n "2:0:+${QUBES_LUKS_GIB}GiB" -t 2:8309 -c 2:qubes-luks  "$DISK"
    sudo sgdisk -n "3:0:0"                     -t 3:8309 -c 3:pureos-luks "$DISK"
    sudo partprobe "$DISK" 2>/dev/null || true
    ok "Layout written. Both installers must use 'custom / manual partitioning'"
    ok "against these partitions — never 'erase disk' — and the SECOND install"
    ok "must reuse partition 1 as /boot WITHOUT reformatting it. See the runbook."
  fi

  section "Done"
  log "Next: devices/librem-14-v1/docs/qubes-pureos-dual-install.md"
  log "  install Qubes OS first (partitions 1+2), PureOS second (partition 3,"
  log "  reusing 1 as /boot unformatted), then in PureBoot: Options -> Update"
  log "  checksums and sign all files in /boot (Librem Key + GPG PIN)."
}

main "$@"
