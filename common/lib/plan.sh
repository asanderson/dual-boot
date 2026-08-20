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
    echo "DUAL_BOOT_PLAN_BOOT_GIB=\"${PLAN_BOOT_GIB}\""
    echo "DUAL_BOOT_PLAN_DISK=\"${TARGET_DISK:-}\""
  } > "$file"
  ok "Plan written to ${file}"
}
