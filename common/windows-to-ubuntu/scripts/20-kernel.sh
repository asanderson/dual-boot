#!/usr/bin/env bash
# 20-kernel.sh — check for newer Ubuntu and Linux kernel releases, apply
# kernel security updates, and verify the kernel meets the 7.0+ requirement.
#
# Usage: 20-kernel.sh [--check-releases]
#
# Modes:
#   Interactive (default): FIRST checks for a newer Ubuntu release
#     (do-release-upgrade) and for newer packaged kernels, prompting before
#     downloading/installing either.
#   Non-interactive (DEV_SETUP_ASSUME_YES=1): the release checks are SKIPPED
#     unless --check-releases is passed. With the flag, prompts take their
#     defaults: kernel updates are applied (default yes); a full Ubuntu
#     release upgrade is only reported, never started (default no) — distro
#     upgrades are too disruptive to run unattended.
#
# Background: Ubuntu 26.04 LTS ships Linux 7.0 as its GA kernel (7.0 is the
# upstream release that followed 6.19), so a stock install already satisfies
# "kernel 7.0 or newer". The install ISO carries the release-pocket build
# (7.0.0-14 at GA); security patches land as newer 7.0.0-xx packages in the
# -security/-updates pockets (e.g. 7.0.0-29/-30 as of mid-August 2026) —
# this script installs the newest of those and can enable unattended
# security upgrades so future kernel patches apply automatically.
#
# Kernels NEWER than the packaged 7.0.0-xx line arrive through:
#   * linux-generic-hwe-26.04 — Canonical's HWE stack (currently also 7.0;
#     rolls forward at later point releases) and stays signed/supported.
#     Preferred.
#   * kernel.ubuntu.com mainline builds — bleeding edge (7.1+/7.2-rc), but
#     UNSIGNED (Secure Boot must be off or modules self-signed), unsupported,
#     and they receive NO security updates — the patched path is the Ubuntu
#     -security pocket, not mainline. NVIDIA DKMS modules are also not
#     expected to build against them. Only for troubleshooting very new
#     hardware.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "${SCRIPT_DIR}/../../lib/common.sh"

REQUIRED_MAJOR=7

usage() {
  echo "Usage: $0 [--check-releases]"
  echo "  --check-releases   in non-interactive mode (DEV_SETUP_ASSUME_YES=1),"
  echo "                     also check for newer Ubuntu and kernel releases"
  echo "                     (interactive mode always checks)"
}

CHECK_RELEASES=""
for arg in "$@"; do
  case "$arg" in
    --check-releases) CHECK_RELEASES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown argument: $arg"; usage; exit 2 ;;
  esac
done
# Interactive runs always check; non-interactive runs only with the flag.
[[ "${DEV_SETUP_ASSUME_YES:-0}" != "1" ]] && CHECK_RELEASES=1
CHECK_RELEASES="${CHECK_RELEASES:-0}"

check_ubuntu_release() {
  section "Ubuntu release check"
  command_exists do-release-upgrade || apt_install ubuntu-release-upgrader-core
  local out rc=0
  out="$(do-release-upgrade -c 2>&1)" || rc=$?
  sed 's/^/  /' <<<"$out"
  if [[ $rc -eq 0 ]]; then
    warn "A newer Ubuntu release is available."
    if confirm "Start the Ubuntu release upgrade now? (long, guided, ends in a reboot)" n; then
      sudo do-release-upgrade
      log "Release upgrade finished — reboot, then re-run this script on the new release."
      exit 0
    fi
    log "Skipped. Run 'sudo do-release-upgrade' whenever you're ready."
  else
    ok "No newer Ubuntu release available ($(. /etc/os-release && echo "$PRETTY_NAME") is current)."
  fi
}

update_kernel_packages() {
  section "Kernel updates (-security / -updates pockets)"
  apt_update_once
  if ! apt-cache policy | grep -q "${VERSION_CODENAME:-resolute}-security"; then
    warn "The Ubuntu -security pocket is missing from your apt sources — kernel"
    warn "security updates will NOT arrive. Check /etc/apt/sources.list.d/ubuntu.sources."
  fi

  local installed candidate
  installed="$(dpkg-query -W -f='${Version}' linux-generic 2>/dev/null || echo "none")"
  candidate="$(apt-cache policy linux-generic | awk '/Candidate:/ {print $2}')"
  log "linux-generic installed: ${installed} / newest available: ${candidate:-unknown}"
  if [[ -n "$candidate" && "$candidate" != "$installed" ]]; then
    if confirm "Download and install the newest packaged kernel (${candidate})?" y; then
      apt_install linux-generic
      ok "Kernel packages updated to ${candidate}."
    fi
  else
    ok "Kernel packages are current (${installed})."
  fi

  local running newest
  running="$(uname -r)"
  newest="$(find /boot -maxdepth 1 -name 'vmlinuz-*' 2>/dev/null | sed 's/.*vmlinuz-//' | sort -V | tail -1)"
  if [[ -n "$newest" && "$newest" != "$running" ]]; then
    warn "Running kernel ${running}, newest installed ${newest} — reboot to boot the patched kernel."
  fi
  [[ -f /run/reboot-required ]] && warn "The system reports a reboot is required."
}

main() {
  require_not_root
  require_ubuntu "26.04"
  require_sudo
  require_network

  # ---- Release checks (always interactive; opt-in via flag when unattended) -
  if [[ "$CHECK_RELEASES" == "1" ]]; then
    check_ubuntu_release
    update_kernel_packages
  else
    log "Release checks skipped (non-interactive run without --check-releases)."
  fi

  # ---- Requirement verification ---------------------------------------------
  section "Kernel check"
  local running major
  running="$(uname -r)"
  major="${running%%.*}"
  log "Running kernel: ${running}"
  if (( major >= REQUIRED_MAJOR )); then
    ok "Kernel ${running} satisfies the ${REQUIRED_MAJOR}.0+ requirement."
  else
    warn "Kernel ${running} is older than ${REQUIRED_MAJOR}.0."
    warn "On Ubuntu 26.04 that usually means you're booted into an old entry —"
    warn "run 'sudo apt full-upgrade', reboot, and pick the newest kernel in GRUB."
  fi

  if confirm "Ensure unattended security upgrades are enabled (future kernel patches apply automatically)?" y; then
    apt_install unattended-upgrades
    sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    ok "Unattended upgrades enabled (default config covers the -security pocket)."
  fi

  # ---- Newer kernel lines (optional) ---------------------------------------
  if confirm "Enable the HWE kernel stack (linux-generic-hwe-26.04) to track newer signed kernels?" y; then
    apt_install "linux-generic-hwe-26.04" || warn "HWE metapackage not available yet (it appears around 26.04.2)."
  fi

  if confirm "Install the 'mainline' tool for bleeding-edge kernel.ubuntu.com builds (unsigned — Secure Boot caveats)?" n; then
    apt_install software-properties-common
    sudo add-apt-repository -y ppa:cappelikan/ppa
    _APT_UPDATED=""
    apt_install mainline
    warn "Mainline kernels are unsigned: with Secure Boot enabled they won't boot"
    warn "unless you disable Secure Boot or sign them yourself. NVIDIA DKMS may"
    warn "also fail to build against a kernel newer than the driver supports."
    log "Usage: 'mainline --list' then 'sudo mainline --install-latest'."
  fi

  section "Current kernel status"
  ok "$(uname -sr) on $(. /etc/os-release && echo "$PRETTY_NAME")"
}

main "$@"
