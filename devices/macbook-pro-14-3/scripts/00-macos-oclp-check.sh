#!/bin/bash
# 00-macos-oclp-check.sh — run ON MACOS, before anything else on this device:
# check for the latest OpenCore Legacy Patcher release and macOS state, and
# prompt to start the Sequoia upgrade.
#
# Usage: 00-macos-oclp-check.sh [--check-releases]
#
# Modes (same contract as common/ubuntu/scripts/20-kernel.sh):
#   Interactive (default): FIRST checks the latest OCLP release and this
#     Mac's macOS version, prompting to download OCLP and start the Sequoia
#     upgrade.
#   Non-interactive (DEV_SETUP_ASSUME_YES=1): the checks are SKIPPED unless
#     --check-releases is passed. With the flag, everything is REPORTED but
#     the upgrade is never started unattended — the OCLP flow is a guided
#     GUI process that needs a human.
#
# Self-contained and macOS bash 3.2-compatible on purpose: it must run on a
# stock Mac with no repo tooling installed (common/lib/common.sh targets the
# Ubuntu side).

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVICE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../config/versions.env
. "${DEVICE_DIR}/config/versions.env"

RELEASES_URL="https://github.com/dortania/OpenCore-Legacy-Patcher/releases"
GUIDE="devices/macbook-pro-14-3/docs/macos-sequoia-oclp.md"

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
  echo "Usage: $0 [--check-releases]"
  echo "  --check-releases   in non-interactive mode (DEV_SETUP_ASSUME_YES=1),"
  echo "                     also check for the latest OCLP release and macOS"
  echo "                     upgrade state (interactive mode always checks)"
}

CHECK_RELEASES=""
for arg in "$@"; do
  case "$arg" in
    --check-releases) CHECK_RELEASES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown argument: $arg"; usage; exit 2 ;;
  esac
done
[ "${DEV_SETUP_ASSUME_YES:-0}" != "1" ] && CHECK_RELEASES=1
CHECK_RELEASES="${CHECK_RELEASES:-0}"

# ---- Guards ----------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "This script runs on macOS (it prepares the Mac before the Ubuntu install)."
model="$(sysctl -n hw.model 2>/dev/null || echo unknown)"
[ "$model" = "MacBookPro14,3" ] || die "This script targets the MacBook Pro (15-inch, 2017; MacBookPro14,3) — detected: ${model}."

product_version="$(sw_vers -productVersion)"
build="$(sw_vers -buildVersion)"
major="$(printf '%s' "$product_version" | cut -d. -f1)"
log "Running macOS ${product_version} (build ${build}) on ${model}."

if [ "$CHECK_RELEASES" != "1" ]; then
  log "Release checks skipped (non-interactive run without --check-releases)."
  exit 0
fi

# ---- OCLP release check ------------------------------------------------------
echo "==> OpenCore Legacy Patcher release check"
latest_oclp="$(curl -fsSL --max-time 20 \
  https://api.github.com/repos/dortania/OpenCore-Legacy-Patcher/releases/latest 2>/dev/null \
  | sed -n 's/.*"tag_name"[^"]*"\([^"]*\)".*/\1/p' | head -1)"
if [ -n "$latest_oclp" ]; then
  log "Latest OCLP release: ${latest_oclp} (pinned in config/versions.env: ${OCLP_VERSION})"
  [ "$latest_oclp" != "$OCLP_VERSION" ] && \
    warn "Pinned OCLP_VERSION (${OCLP_VERSION}) differs from the latest (${latest_oclp}) — update the pin after a successful run."
else
  warn "Could not query GitHub for the latest OCLP release; using pin ${OCLP_VERSION}."
  latest_oclp="$OCLP_VERSION"
fi
installed_oclp="$(defaults read /Applications/OpenCore-Legacy-Patcher.app/Contents/Info CFBundleShortVersionString 2>/dev/null || true)"
if [ -n "$installed_oclp" ]; then
  if [ "$installed_oclp" = "$latest_oclp" ]; then
    ok "OCLP ${installed_oclp} installed — current."
  else
    warn "OCLP ${installed_oclp} installed; ${latest_oclp} is available — update it (OCLP settings, or the releases page) before patching."
  fi
else
  log "OCLP app not installed yet."
fi

# ---- macOS upgrade state -----------------------------------------------------
echo "==> macOS upgrade check"
if [ "$major" -ge 15 ]; then
  ok "Already on macOS ${product_version} (Sequoia or newer)."
  log "Point updates (e.g. the latest 15.x) are managed through the OCLP app,"
  log "which re-applies root patches after each update."
else
  warn "macOS ${product_version} is pre-Sequoia. This model's last Apple-supported"
  warn "release is Ventura 13 — Sequoia requires OpenCore Legacy Patcher."
  if confirm "Download the latest OCLP (${latest_oclp}) to ~/Downloads and open the releases page?" n; then
    open "${RELEASES_URL}" 2>/dev/null || log "Open ${RELEASES_URL} in a browser."
    ok "Releases page opened — grab the .pkg for ${latest_oclp}."
  fi
  if confirm "Start the Sequoia upgrade now (guided, human-driven — several reboots)?" n; then
    log "Follow the guide: ${GUIDE}"
    log "Summary: Time Machine backup -> install OCLP -> Create macOS Installer"
    log "(Sequoia) -> Build & Install OpenCore -> boot installer via Option key"
    log "-> Post-Install Root Patches -> updates via OCLP thereafter."
    [ -e "/Applications/OpenCore-Legacy-Patcher.app" ] && open -a "OpenCore-Legacy-Patcher" 2>/dev/null
  else
    log "Skipped. Run the upgrade before the Ubuntu install (see ${GUIDE})."
  fi
fi

echo "==> Done"
ok "Next: common/macos-to-ubuntu/docs/01-macos-prep.md (backup, APFS resize, USB)."
