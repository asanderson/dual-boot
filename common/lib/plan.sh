# shellcheck shell=bash
# plan.sh — determines the common installation constraints shared by every
# device flow: which operating systems to install, whether each is a clean
# (destructive) install or an in-place upgrade, whether existing boot
# devices/partitions get backed up first, the boot partition size, and the
# target disk. Source AFTER common.sh, os-catalog.env, and oses.sh.
#
# The decisions land in PLAN_* variables and can be persisted with
# plan_write; device scripts source that plan file and honor it.

# plan_select_oses — from --os (validated against the catalog) or one prompt
# per catalog OS. PLAN_DEFAULT_OSES (space-separated) seeds the interactive
# defaults and is the unattended fallback when --os was not given.
plan_select_oses() {
  PLAN_OSES=""
  local os
  if [[ -n "${OS_SELECTION:-}" ]]; then
    for os in ${OS_SELECTION//,/ }; do
      os_in_catalog "$os" || die "--os: unknown OS '${os}' (catalog: ${OS_CATALOG})"
      PLAN_OSES="${PLAN_OSES:+${PLAN_OSES} }${os}"
    done
    return 0
  fi
  local defaults=" ${PLAN_DEFAULT_OSES:-ubuntu} "
  if [[ "${DEV_SETUP_ASSUME_YES:-0}" == "1" ]]; then
    PLAN_OSES="${PLAN_DEFAULT_OSES:-ubuntu}"
    log "Unattended run without --os: planning for the default set: ${PLAN_OSES}"
    return 0
  fi
  log "Choose the operating systems to plan for:"
  for os in ${OS_CATALOG}; do
    log "  ${os}: $(os_describe "$os")"
  done
  for os in ${OS_CATALOG}; do
    local d="n"
    [[ "$defaults" == *" ${os} "* ]] && d="y"
    if confirm "Include ${os}?" "$d"; then
      PLAN_OSES="${PLAN_OSES:+${PLAN_OSES} }${os}"
    fi
  done
  [[ -n "$PLAN_OSES" ]] || die "No operating systems selected — nothing to plan."
}

# plan_select_modes — per selected OS: 'install' (clean, destructive) or
# 'upgrade' (in-place). --mode OS=MODE wins; otherwise a prompt whose
# default comes from PLAN_DEFAULT_MODE (globally, default 'upgrade') so a
# destructive mode is never reached by unattended defaults alone.
plan_select_modes() {
  local os mode suffix pair
  for os in ${PLAN_OSES}; do
    suffix="$(os_fn_suffix "$os")"
    mode=""
    for pair in ${MODE_SELECTION//,/ }; do
      if [[ "${pair%%=*}" == "$os" ]]; then
        mode="${pair#*=}"
        [[ "$mode" == "install" || "$mode" == "upgrade" ]] \
          || die "--mode ${pair}: mode must be 'install' or 'upgrade'"
      fi
    done
    if [[ -z "$mode" ]]; then
      local d="n"
      [[ "${PLAN_DEFAULT_MODE:-upgrade}" == "install" ]] && d="y"
      if confirm "${os}: CLEAN INSTALL (destructive — existing data in its target is destroyed)? 'no' = in-place upgrade of an existing install" "$d"; then
        mode="install"
      else
        mode="upgrade"
      fi
    fi
    printf -v "PLAN_MODE_${suffix}" '%s' "$mode"
    log "${os}: mode = ${mode}"
  done
}

# plan_backup_decide — whether existing boot devices/partitions get backed
# up before anything changes. --backup/--no-backup win; otherwise a prompt
# defaulting to YES (unattended runs therefore back up by default — the
# backup is non-destructive).
plan_backup_decide() {
  if [[ -n "${BACKUP:-}" ]]; then
    PLAN_BACKUP="$BACKUP"
  elif confirm "Back up the existing partition table and boot partitions before anything changes?" y; then
    PLAN_BACKUP=1
  else
    PLAN_BACKUP=0
  fi
  log "Boot-state backup: $( [[ "$PLAN_BACKUP" == "1" ]] && echo yes || echo no )"
}

# plan_secure_boot_decide — whether Secure Boot (or the device's
# verified-boot equivalent — e.g. PureBoot on the Librem 14, which
# supersedes UEFI Secure Boot) stays enforced for the installed OSes.
# --secure-boot/--no-secure-boot win; otherwise a prompt defaulting to YES
# (a plan decision only — nothing is flashed or changed here; device flows
# honor or verify it).
plan_secure_boot_decide() {
  if [[ -n "${SECURE_BOOT:-}" ]]; then
    PLAN_SECURE_BOOT="$SECURE_BOOT"
  elif confirm "Keep Secure Boot (or the device's verified-boot equivalent) enforced for the installed OSes?" y; then
    PLAN_SECURE_BOOT=1
  else
    PLAN_SECURE_BOOT=0
  fi
  log "Secure Boot: $( [[ "$PLAN_SECURE_BOOT" == "1" ]] && echo "keep enforced" || echo "not required" )"
}

# plan_encrypt_decide — whether OS disks/partitions get encrypted at install
# time (LUKS on the Linux installers, BitLocker on Windows; Qubes already
# defaults to LUKS). --encrypt/--no-encrypt win; otherwise a prompt
# defaulting to YES. A plan decision the OS installers enact — the runbooks
# and device scripts tell you where, and post-install scripts verify it.
plan_encrypt_decide() {
  if [[ -n "${ENCRYPT_DISKS:-}" ]]; then
    PLAN_ENCRYPT="$ENCRYPT_DISKS"
  elif confirm "Encrypt the OS disks/partitions at install time (LUKS / BitLocker)?" y; then
    PLAN_ENCRYPT=1
  else
    PLAN_ENCRYPT=0
  fi
  log "Disk encryption: $( [[ "$PLAN_ENCRYPT" == "1" ]] && echo yes || echo no )"
}

# plan_wifi_decide — optional Wi-Fi settings for the installed systems:
# SSID, password, security type, hidden-network. --wifi-* flags win;
# otherwise interactive runs offer prompts (default: no Wi-Fi plan). The
# password is read with echo off, never logged, and lands only in the
# mode-600 plan file. Unattended runs plan Wi-Fi only when --wifi-ssid was
# passed (password via --wifi-password or DUAL_BOOT_WIFI_PASSWORD).
plan_wifi_decide() {
  PLAN_WIFI_SSID="${WIFI_SSID:-}"
  PLAN_WIFI_SECURITY="${WIFI_SECURITY:-wpa-psk}"
  PLAN_WIFI_HIDDEN="${WIFI_HIDDEN:-0}"
  PLAN_WIFI_PASSWORD="${WIFI_PASSWORD:-${DUAL_BOOT_WIFI_PASSWORD:-}}"
  if [[ -z "$PLAN_WIFI_SSID" ]]; then
    if [[ "${DEV_SETUP_ASSUME_YES:-0}" == "1" ]]; then
      log "No --wifi-ssid given — not planning Wi-Fi configuration."
      return 0
    fi
    if ! confirm "Configure Wi-Fi on the installed systems?" n; then
      log "Wi-Fi: not configured by this plan."
      return 0
    fi
    read -r -p "Wi-Fi SSID (network name): " PLAN_WIFI_SSID || PLAN_WIFI_SSID=""
    if [[ -z "$PLAN_WIFI_SSID" ]]; then
      warn "Empty SSID — skipping Wi-Fi configuration."
      return 0
    fi
    local sec
    read -r -p "Security [wpa-psk = WPA2/WPA3 Personal | sae = WPA3 only | open] (wpa-psk): " sec || sec=""
    [[ -n "$sec" ]] && PLAN_WIFI_SECURITY="$sec"
    if confirm "Hidden network (SSID not broadcast)?" n; then
      PLAN_WIFI_HIDDEN=1
    fi
  fi
  case "$PLAN_WIFI_SECURITY" in
    wpa-psk|sae|open) ;;
    *) die "Wi-Fi security must be wpa-psk, sae, or open (got '${PLAN_WIFI_SECURITY}')." ;;
  esac
  if [[ "$PLAN_WIFI_SECURITY" != "open" && -z "$PLAN_WIFI_PASSWORD" ]]; then
    if [[ "${DEV_SETUP_ASSUME_YES:-0}" == "1" ]]; then
      warn "--wifi-ssid given without a password (--wifi-password or the"
      warn "DUAL_BOOT_WIFI_PASSWORD env var) — skipping Wi-Fi configuration."
      PLAN_WIFI_SSID=""
      return 0
    fi
    read -rs -p "Wi-Fi password (input hidden): " PLAN_WIFI_PASSWORD; echo
    if [[ -z "$PLAN_WIFI_PASSWORD" ]]; then
      warn "Empty password — skipping Wi-Fi configuration."
      PLAN_WIFI_SSID=""
      return 0
    fi
  fi
  local extra=""
  [[ "$PLAN_WIFI_HIDDEN" == "1" ]] && extra=", hidden"
  log "Wi-Fi: ${PLAN_WIFI_SSID} (${PLAN_WIFI_SECURITY}${extra}); password not shown."
}

# wifi_apply_plan — configure Wi-Fi from the plan (--wifi-* flags on the
# calling script override it) via NetworkManager, idempotently: an existing
# profile with the same name is replaced, autoconnect is on, and activation
# is attempted only when a Wi-Fi device is visible (the profile still helps
# when the driver arrives after a reboot). No-ops honestly when the plan has
# no Wi-Fi or nmcli is absent. On Qubes OS networking lives in sys-net, so
# dom0 gets instructions instead of configuration.
wifi_apply_plan() {
  local ssid sec hidden pass
  if [[ -f "${PLAN_FILE:-}" ]]; then
    # shellcheck disable=SC1090
    source "$PLAN_FILE"
  fi
  ssid="${WIFI_SSID:-${DUAL_BOOT_PLAN_WIFI_SSID:-}}"
  sec="${WIFI_SECURITY:-${DUAL_BOOT_PLAN_WIFI_SECURITY:-wpa-psk}}"
  hidden="${WIFI_HIDDEN:-${DUAL_BOOT_PLAN_WIFI_HIDDEN:-0}}"
  pass="${WIFI_PASSWORD:-${DUAL_BOOT_WIFI_PASSWORD:-${DUAL_BOOT_PLAN_WIFI_PASSWORD:-}}}"
  if [[ -z "$ssid" ]]; then
    log "No Wi-Fi in the plan — nothing to configure."
    return 0
  fi
  if grep -qi '^NAME=.*Qubes' /etc/os-release 2>/dev/null; then
    log "Qubes OS: networking lives in sys-net, not dom0. Configure there:"
    log "  qvm-run -u root sys-net 'nmcli connection add type wifi con-name \"${ssid}\" ssid \"${ssid}\" ...'"
    log "  (or use the network applet; sys-net Wi-Fi profiles persist via qvm-features)"
    return 0
  fi
  if ! command -v nmcli >/dev/null 2>&1; then
    warn "NetworkManager (nmcli) not available — configure '${ssid}' manually."
    return 0
  fi
  if [[ "$sec" != "open" && -z "$pass" ]]; then
    warn "Wi-Fi plan for '${ssid}' has no password — skipping configuration."
    return 0
  fi
  sudo nmcli connection delete "$ssid" >/dev/null 2>&1 || true
  local -a args=(type wifi con-name "$ssid" ssid "$ssid" connection.autoconnect yes)
  [[ "$hidden" == "1" ]] && args+=(wifi.hidden yes)
  case "$sec" in
    wpa-psk) args+=(wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$pass") ;;
    sae)     args+=(wifi-sec.key-mgmt sae wifi-sec.psk "$pass") ;;
    open)    ;;
  esac
  if ! sudo nmcli connection add "${args[@]}" >/dev/null; then
    err "Could not create the NetworkManager profile for '${ssid}'."
    return 1
  fi
  ok "Wi-Fi profile '${ssid}' configured (${sec}, autoconnect on)."
  if nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep -q ':wifi$'; then
    if sudo nmcli connection up "$ssid" >/dev/null 2>&1; then
      ok "Connected to '${ssid}'."
    else
      warn "Profile saved but activation failed (out of range / wrong password?) —"
      warn "it will auto-connect when the network is reachable."
    fi
  else
    log "No Wi-Fi device visible yet — the profile will connect once the driver is up."
  fi
}

# plan_boot_size_decide — boot partition size in GiB (per OS boot partition
# where the device uses one). --boot-size wins; interactive runs may edit.
plan_boot_size_decide() {
  if [[ "${DEV_SETUP_ASSUME_YES:-0}" != "1" ]]; then
    local r
    read -r -p "Boot partition size in GiB [${BOOT_GIB}]: " r || r=""
    [[ -n "$r" ]] && BOOT_GIB="$r"
  fi
  [[ "$BOOT_GIB" =~ ^[0-9]+$ && "$BOOT_GIB" -ge 1 ]] \
    || die "Boot partition size must be a whole number of GiB >= 1 (got '${BOOT_GIB}')."
  PLAN_BOOT_GIB="$BOOT_GIB"
  log "Boot partition size: ${PLAN_BOOT_GIB} GiB"
}

# backup_boot_state <disk-or-empty> <dest-dir> — non-destructive backup of
# the current boot state: GPT partition table (when a disk is known), a full
# block-device inventory, and tarballs of the mounted /boot and /boot/efi.
# Full-disk image backups remain a runbook step — this is the boot-specific
# safety net the plan promises.
backup_boot_state() {
  local disk="$1" dest="$2" stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  dest="${dest}/boot-backup-${stamp}"
  mkdir -p "$dest"
  log "Backing up boot state to ${dest}"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL,MOUNTPOINTS > "${dest}/lsblk.txt" 2>/dev/null || true
  if [[ -n "$disk" && -b "$disk" ]]; then
    sudo sgdisk --backup="${dest}/$(basename "$disk")-gpt.bak" "$disk" \
      && ok "GPT partition table of ${disk} backed up." \
      || warn "Could not back up the partition table of ${disk}."
  else
    log "No target disk known — skipping the partition-table backup."
  fi
  local mp
  for mp in /boot/efi /boot; do
    if mountpoint -q "$mp" 2>/dev/null; then
      sudo tar -C / -czf "${dest}/$(echo "${mp#/}" | tr / -).tar.gz" "${mp#/}" \
        && ok "${mp} backed up." \
        || warn "Could not back up ${mp}."
    fi
  done
  ok "Boot-state backup complete: ${dest} (copy it OFF this machine before destructive steps)."
}

# verify_security_plan [--no-uefi-sb] — post-install, read-only check that
# the installed system matches the plan's Secure Boot and disk-encryption
# decisions (plan file supplies defaults; --secure-boot/--encrypt flags on
# the calling script override). --no-uefi-sb marks hardware with no UEFI
# Secure Boot support for Linux (pre-T2 Apple), where the intent cannot be
# enforced. Warns only — never changes anything.
verify_security_plan() {
  local no_uefi_sb=""
  [[ "${1:-}" == "--no-uefi-sb" ]] && no_uefi_sb=1
  if [[ -f "${PLAN_FILE:-}" ]]; then
    # shellcheck disable=SC1090
    source "$PLAN_FILE"
    [[ -z "${SECURE_BOOT:-}" && -n "${DUAL_BOOT_PLAN_SECURE_BOOT:-}" ]] && SECURE_BOOT="${DUAL_BOOT_PLAN_SECURE_BOOT}"
    [[ -z "${ENCRYPT_DISKS:-}" && -n "${DUAL_BOOT_PLAN_ENCRYPT:-}" ]] && ENCRYPT_DISKS="${DUAL_BOOT_PLAN_ENCRYPT}"
  fi
  if [[ -z "${SECURE_BOOT:-}" && -z "${ENCRYPT_DISKS:-}" ]]; then
    log "No security plan found (run common/scripts/00-install-plan.sh first, or"
    log "  pass --secure-boot/--no-secure-boot / --encrypt/--no-encrypt) — skipping."
    return 0
  fi
  if [[ "${SECURE_BOOT:-}" == "1" ]]; then
    if [[ -n "$no_uefi_sb" ]]; then
      log "Secure Boot plan: this hardware has no UEFI Secure Boot support for"
      log "  Linux (pre-T2 Apple) — the plan's intent cannot be enforced here."
    elif command -v mokutil >/dev/null 2>&1; then
      if mokutil --sb-state 2>/dev/null | grep -qi enabled; then
        ok "Secure Boot: enabled (matches the plan)."
      else
        warn "The plan wants Secure Boot but it is NOT enabled — enable it in the"
        warn "  firmware setup (drivers in this flow are MOK-signed, so it can stay on)."
      fi
    else
      log "mokutil not installed — cannot verify Secure Boot state (sudo apt install mokutil)."
    fi
  else
    log "Plan does not require Secure Boot — skipping that check."
  fi
  if [[ "${ENCRYPT_DISKS:-}" == "1" ]]; then
    if lsblk -no FSTYPE 2>/dev/null | grep -q crypto_LUKS; then
      ok "Disk encryption: LUKS volume(s) present (matches the plan)."
    else
      warn "The plan wants disk encryption but no LUKS volume is visible — this"
      warn "  install is unencrypted. Encryption is chosen at OS install time;"
      warn "  retrofitting means a reinstall or a full backup/restore cycle."
    fi
  else
    log "Plan does not require disk encryption — skipping that check."
  fi
}

# plan_summary + plan_write — show and persist the decisions for device
# scripts to consume.
plan_summary() {
  section "Installation plan"
  local os suffix var
  log "Operating systems: ${PLAN_OSES}"
  for os in ${PLAN_OSES}; do
    suffix="$(os_fn_suffix "$os")"
    var="PLAN_MODE_${suffix}"
    log "  ${os}: ${!var:-unset}"
  done
  log "Boot-state backup first: $( [[ "${PLAN_BACKUP}" == "1" ]] && echo yes || echo no )"
  log "Secure Boot: $( [[ "${PLAN_SECURE_BOOT}" == "1" ]] && echo "keep enforced" || echo "not required" )"
  log "Disk encryption: $( [[ "${PLAN_ENCRYPT}" == "1" ]] && echo yes || echo no )"
  if [[ -n "${PLAN_WIFI_SSID:-}" ]]; then
    log "Wi-Fi: ${PLAN_WIFI_SSID} (${PLAN_WIFI_SECURITY}$( [[ "${PLAN_WIFI_HIDDEN}" == "1" ]] && echo ", hidden" ); password in the plan file only)"
  else
    log "Wi-Fi: not configured by this plan"
  fi
  log "Boot partition size: ${PLAN_BOOT_GIB} GiB"
  log "Target disk: ${TARGET_DISK:-not set (device scripts use their default)}"
}

plan_write() {
  local file="$1" os suffix var
  {
    echo "# dual-boot installation plan — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# by common/scripts/00-install-plan.sh; consumed by device scripts."
    echo "DUAL_BOOT_PLAN_OSES=\"${PLAN_OSES}\""
    for os in ${PLAN_OSES}; do
      suffix="$(os_fn_suffix "$os")"
      var="PLAN_MODE_${suffix}"
      echo "DUAL_BOOT_PLAN_MODE_${suffix}=\"${!var}\""
    done
    echo "DUAL_BOOT_PLAN_BACKUP=\"${PLAN_BACKUP}\""
    echo "DUAL_BOOT_PLAN_SECURE_BOOT=\"${PLAN_SECURE_BOOT}\""
    echo "DUAL_BOOT_PLAN_ENCRYPT=\"${PLAN_ENCRYPT}\""
    echo "DUAL_BOOT_PLAN_BOOT_GIB=\"${PLAN_BOOT_GIB}\""
    echo "DUAL_BOOT_PLAN_DISK=\"${TARGET_DISK:-}\""
    if [[ -n "${PLAN_WIFI_SSID:-}" ]]; then
      # %q so SSIDs/passwords with spaces or shell metacharacters survive
      # the round trip through `source`.
      printf 'DUAL_BOOT_PLAN_WIFI_SSID=%q\n' "$PLAN_WIFI_SSID"
      printf 'DUAL_BOOT_PLAN_WIFI_SECURITY=%q\n' "$PLAN_WIFI_SECURITY"
      printf 'DUAL_BOOT_PLAN_WIFI_HIDDEN=%q\n' "$PLAN_WIFI_HIDDEN"
      printf 'DUAL_BOOT_PLAN_WIFI_PASSWORD=%q\n' "$PLAN_WIFI_PASSWORD"
    fi
  } > "$file"
  # The plan can carry a Wi-Fi password — owner-only, always.
  chmod 600 "$file"
  ok "Plan written to ${file} (mode 600)"
}
