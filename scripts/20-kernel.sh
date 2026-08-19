#!/usr/bin/env bash
# 20-kernel.sh — verify the kernel meets the 7.0+ requirement and apply the
# latest packaged kernel security updates.
#
# Ubuntu 26.04 LTS ships Linux 7.0 as its GA kernel (7.0 is the upstream
# release that followed 6.19), so a stock install already satisfies
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
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REQUIRED_MAJOR=7

main() {
  require_not_root
  require_ubuntu "26.04"

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

  require_sudo
  require_network

  # ---- Kernel security updates (-security / -updates pockets) --------------
  section "Kernel security updates"
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
    if confirm "Install the newest packaged kernel (${candidate}) with its security patches?" y; then
      apt_install linux-generic
      ok "Kernel packages updated to ${candidate}."
    fi
  else
    ok "Kernel packages are current (${installed})."
  fi

  local newest
  newest="$(find /boot -maxdepth 1 -name 'vmlinuz-*' 2>/dev/null | sed 's/.*vmlinuz-//' | sort -V | tail -1)"
  if [[ -n "$newest" && "$newest" != "$running" ]]; then
    warn "Running kernel ${running}, newest installed ${newest} — reboot to boot the patched kernel."
  fi
  [[ -f /run/reboot-required ]] && warn "The system reports a reboot is required."

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
