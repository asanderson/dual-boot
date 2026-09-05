#!/bin/bash
# backup-macos.sh — Step 1.0 of docs/01-macos-prep.md, scripted: a full Time
# Machine backup of the existing macOS install (and every other volume Time
# Machine includes) to an external drive — the backup docs/04-rollback.md
# Path B restores from ("Restore from Time Machine" in macOS Recovery).
#
# Usage: backup-macos.sh [/Volumes/BackupDrive]
#   With a mount point: it becomes the Time Machine destination first
#   (tmutil setdestination — the volume must be APFS or HFS+; Disk Utility
#   -> Erase -> APFS if it isn't). Without one: the already-configured
#   destination is used, or the script tells you to pass one.
#   Then runs one full backup and BLOCKS until it completes.
#
# Unattended (DEV_SETUP_ASSUME_YES=1) runs take the prompt's default (yes) —
# a backup is non-destructive, the same rule as the boot-state backup.
# Self-contained and macOS bash 3.2-compatible on purpose (like
# devices/macbook-pro-14-3/scripts/00-macos-oclp-check.sh): it must run on
# a stock Mac with no repo tooling installed.

set -eu

log()  { printf '[dual-boot] %s\n' "$*"; }
warn() { printf '[ warn ] %s\n' "$*" >&2; }
ok()   { printf '[  ok  ] %s\n' "$*"; }
die()  { printf '[ fail ] %s\n' "$*" >&2; exit 1; }

# confirm "Question?" default(y|n) — unattended runs take the default.
confirm() {
  prompt="$1"; default="$2"
  if [ "${DEV_SETUP_ASSUME_YES:-0}" = "1" ]; then
    log "$prompt -> ${default} (DEV_SETUP_ASSUME_YES=1, taking default)"
    [ "$default" = "y" ]; return
  fi
  if [ "$default" = "y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  while true; do
    printf '%s %s ' "$prompt" "$hint"; read -r reply || reply=""
    reply="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
    [ -z "$reply" ] && reply="$default"
    case "$reply" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) warn "Please answer y or n." ;;
    esac
  done
}

usage() {
  echo "Usage: $0 [/Volumes/BackupDrive]"
  echo "  /Volumes/...   external APFS/HFS+ volume to set as the Time Machine"
  echo "                 destination first; omit to use the configured one"
}

dest=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    -*) warn "Unknown argument: $arg"; usage; exit 2 ;;
    *) dest="$arg" ;;
  esac
done

# ---- Guards ----------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "This script runs on macOS (it backs the Mac up before the Ubuntu install)."
[ "$(id -u)" -ne 0 ] || die "Run this script as your regular user, not root. It uses sudo where needed."

# ---- Destination -------------------------------------------------------------
echo "==> Time Machine destination"
if [ -n "$dest" ]; then
  [ -d "$dest" ] || die "${dest} is not a mounted volume — plug the external drive in first."
  case "$(df -P "$dest" | awk 'NR==2 {print $NF}')" in
    /|/System/Volumes/Data)
      die "${dest} is on the startup disk — Time Machine needs a separate, external volume." ;;
  esac
  sudo tmutil setdestination "$dest" \
    || die "Could not make ${dest} the Time Machine destination — it must be an APFS or HFS+ volume (Disk Utility -> Erase -> APFS)."
  ok "Time Machine destination set to ${dest}."
fi
info="$(tmutil destinationinfo 2>/dev/null || true)"
if ! printf '%s\n' "$info" | grep -Eq '^(Mount Point|URL)'; then
  die "No Time Machine destination configured — pass the external drive's mount point: $0 /Volumes/BackupDrive"
fi
printf '%s\n' "$info" | sed 's/^/  /'

# ---- Space check -------------------------------------------------------------
echo "==> Space check"
used_k="$(df -Pk / | awk 'NR==2 {print $3}')"
mount="$(printf '%s\n' "$info" | sed -n 's/^Mount Point *: *//p' | head -1)"
if [ -n "$mount" ] && [ -d "$mount" ]; then
  avail_k="$(df -Pk "$mount" | awk 'NR==2 {print $4}')"
  log "Startup disk in use: $((used_k / 1024 / 1024)) GiB; free on ${mount}: $((avail_k / 1024 / 1024)) GiB."
  [ "$avail_k" -ge "$used_k" ] \
    || warn "The destination has less free space than the startup disk uses — the first full backup will most likely fail; use a bigger drive."
else
  log "Network destination — free space not checked here."
fi

# ---- Backup ------------------------------------------------------------------
echo "==> Backup"
if ! confirm "Start a full Time Machine backup now (blocks until it completes)?" y; then
  log "Skipped. Re-run this, or use Time Machine -> Back Up Now, before continuing."
  exit 0
fi
tmutil startbackup --block \
  || die "Time Machine reported a failure — see System Settings -> General -> Time Machine."
ok "Backup complete: $(tmutil latestbackup 2>/dev/null || echo 'see tmutil listbackups')"
log "Restore: macOS Recovery (Cmd+R) -> Restore from Time Machine (docs/04-rollback.md, Path B)."
ok "Next: docs/01-macos-prep.md step 1.1 (update macOS / any device-page upgrade)."
