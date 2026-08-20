#!/usr/bin/env bash
# container-init.sh — runs INSIDE a fresh Ubuntu container (as root).
# Exercises this repo's scripts in both unattended modes and asserts the
# documented behavior. Invoked by test/container-test.sh.
#
# Mounts expected: /repo (this repository, read-only).
# Optional proxy support: if $https_proxy is set, apt sources switch to
# HTTPS and route through it; if /ccr-ca.crt is mounted, it is trusted
# (for CONNECT-only MITM proxies, e.g. sandboxed CI environments).
set -euo pipefail

fail() { echo "ASSERTION FAILED: $*" >&2; exit 1; }

echo "### [init] apt bootstrap$( [[ -n "${https_proxy:-}" ]] && echo ' (via proxy)' )"
unset http_proxy HTTP_PROXY   # CONNECT-only proxies reject plain-HTTP proxying
if [[ -n "${https_proxy:-}" ]]; then
  sed -i 's|http://\(archive\|security\).ubuntu.com|https://\1.ubuntu.com|g' \
    /etc/apt/sources.list.d/ubuntu.sources
  {
    echo "Acquire::https::Proxy \"${https_proxy}\";"
    [[ -f /ccr-ca.crt ]] && echo 'Acquire::https::CAInfo "/ccr-ca.crt";'
  } >/etc/apt/apt.conf.d/95proxy
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates sudo curl gnupg >/dev/null
if [[ -f /ccr-ca.crt ]]; then
  cp /ccr-ca.crt /usr/local/share/ca-certificates/agent-proxy.crt
  update-ca-certificates >/dev/null
fi

echo "### [init] create test user 'dev' with passwordless sudo"
useradd -m -s /bin/bash dev
echo 'dev ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dev
echo 'Defaults env_keep += "https_proxy no_proxy HTTPS_PROXY NO_PROXY DEBIAN_FRONTEND"' >/etc/sudoers.d/proxy-env
chmod 440 /etc/sudoers.d/dev /etc/sudoers.d/proxy-env
cp -r /repo /home/dev/dual-boot
chown -R dev:dev /home/dev/dual-boot

as_dev() {
  sudo -u dev -H env \
    https_proxy="${https_proxy:-}" no_proxy="${no_proxy:-}" \
    DEV_SETUP_ASSUME_YES=1 \
    bash -c "cd ~/dual-boot && $*"
}

echo "### [test 1] 20-kernel.sh unattended WITHOUT --check-releases: must skip"
out="$(as_dev ./common/ubuntu/scripts/20-kernel.sh 2>&1)" || fail "test 1: script exited non-zero"
grep -q "Release checks skipped" <<<"$out" || fail "test 1: missing 'Release checks skipped'"
dpkg -s linux-generic >/dev/null 2>&1 && fail "test 1: kernel installed despite skipped checks"
echo "  PASS: checks skipped, nothing installed"

echo "### [test 2] 20-kernel.sh unattended WITH --check-releases: must check + patch"
out="$(as_dev ./common/ubuntu/scripts/20-kernel.sh --check-releases 2>&1)" || { echo "$out" | tail -20; fail "test 2: script exited non-zero"; }
grep -Eq "No newer Ubuntu release available|A newer Ubuntu release is available" <<<"$out" \
  || fail "test 2: Ubuntu release check did not run"
grep -Eq "Latest upstream stable kernel|Could not determine the latest upstream" <<<"$out" \
  || fail "test 2: upstream kernel.org check did not run"
dpkg-query -W -f='  PASS: kernel ${Version} installed\n' linux-generic \
  || fail "test 2: linux-generic not installed"

echo "### [test 3] 10-nvidia-driver.sh without a GPU: must fail gracefully"
set +e
out="$(as_dev ./devices/msi-raider-18-hx-ai/scripts/10-nvidia-driver.sh 2>&1)"; rc=$?
set -e
[[ $rc -ne 0 ]] || fail "test 3: expected non-zero exit without an NVIDIA GPU"
grep -q "No NVIDIA GPU visible" <<<"$out" || fail "test 3: missing graceful no-GPU message"
echo "  PASS: exited ${rc} with the documented no-GPU message"

echo "### [test 4] 10-mac-setup.sh on non-Apple hardware: must refuse gracefully"
set +e
out="$(as_dev ./devices/macbook-pro-14-3/scripts/10-mac-setup.sh 2>&1)"; rc=$?
set -e
[[ $rc -ne 0 ]] || fail "test 4: expected non-zero exit on non-Apple hardware"
grep -q "This script targets the MacBook Pro" <<<"$out" || fail "test 4: missing wrong-hardware message"
echo "  PASS: exited ${rc} with the wrong-hardware message"

echo "### [test 5] 00-macos-oclp-check.sh on Linux: must refuse gracefully"
set +e
out="$(as_dev ./devices/macbook-pro-14-3/scripts/00-macos-oclp-check.sh 2>&1)"; rc=$?
set -e
[[ $rc -ne 0 ]] || fail "test 5: expected non-zero exit on non-macOS"
grep -q "This script runs on macOS" <<<"$out" || fail "test 5: missing wrong-OS message"
echo "  PASS: exited ${rc} with the wrong-OS message"

echo "### [test 6] 10-dual-install-prep.sh on non-Purism hardware: must refuse"
set +e
out="$(as_dev ./devices/librem-14-v1/scripts/10-dual-install-prep.sh 2>&1)"; rc=$?
set -e
[[ $rc -ne 0 ]] || fail "test 6: expected non-zero exit on non-Librem hardware"
grep -q "This script targets the Librem 14" <<<"$out" || fail "test 6: missing wrong-hardware message"
grep -qE "WIPE|sgdisk|GPT layout" <<<"$out" && fail "test 6: destructive path reached despite wrong hardware"
echo "  PASS: exited ${rc} with the wrong-hardware message, nothing destructive reached"

echo "### [test 7] 10-dual-install-prep.sh --destructive on wrong hardware: gate still wins"
set +e
out="$(as_dev ./devices/librem-14-v1/scripts/10-dual-install-prep.sh --destructive 2>&1)"; rc=$?
set -e
[[ $rc -ne 0 ]] || fail "test 7: --destructive must not bypass the hardware gate"
grep -q "This script targets the Librem 14" <<<"$out" || fail "test 7: missing wrong-hardware message"
out="$(as_dev ./devices/librem-14-v1/scripts/10-dual-install-prep.sh --help 2>&1)" || fail "test 7: --help exited non-zero"
grep -q -- "--destructive" <<<"$out" || fail "test 7: --help does not document --destructive"
grep -q -- "--check-releases" <<<"$out" || fail "test 7: --help does not document --check-releases"
echo "  PASS: hardware gate precedes --destructive; --help documents both flags"

echo "### [test 8] 00-install-plan.sh unattended: defaults + flags land in the plan"
out="$(as_dev ./common/scripts/00-install-plan.sh --os ubuntu,rocky --mode rocky=install --no-backup --boot-size 3 2>&1)" \
  || { echo "$out" | tail -20; fail "test 8: plan script exited non-zero"; }
grep -q "Release checks skipped" <<<"$out" || fail "test 8: unattended run without --check-releases must skip release checks"
plan="$(cat /home/dev/.dual-boot-plan.env 2>/dev/null)" || fail "test 8: plan file not written"
grep -q 'DUAL_BOOT_PLAN_OSES="ubuntu rocky"' <<<"$plan" || fail "test 8: planned OS list wrong"
grep -q 'DUAL_BOOT_PLAN_MODE_ubuntu="upgrade"' <<<"$plan" || fail "test 8: ubuntu must default to 'upgrade' — destructive is never an unattended default"
grep -q 'DUAL_BOOT_PLAN_MODE_rocky="install"' <<<"$plan" || fail "test 8: --mode rocky=install not honored"
grep -q 'DUAL_BOOT_PLAN_BACKUP="0"' <<<"$plan" || fail "test 8: --no-backup not honored"
grep -q 'DUAL_BOOT_PLAN_BOOT_GIB="3"' <<<"$plan" || fail "test 8: --boot-size not honored"
out="$(as_dev ./common/scripts/00-install-plan.sh --help 2>&1)" || fail "test 8: --help exited non-zero"
for flag in "--os LIST" "--mode OS=MODE" "--backup" "--boot-size GIB" "--plan-file FILE"; do
  grep -q -- "$flag" <<<"$out" || fail "test 8: --help does not document ${flag}"
done
echo "  PASS: plan honors defaults + flags; unattended checks skipped; help documents the vocabulary"

echo "### [test 9] 00-install-plan.sh: catalog validation + release-check wiring"
set +e
out="$(as_dev ./common/scripts/00-install-plan.sh --os bogus 2>&1)"; rc=$?
set -e
[[ $rc -ne 0 ]] || fail "test 9: unknown OS must be rejected"
grep -q "unknown OS 'bogus'" <<<"$out" || fail "test 9: missing catalog rejection message"
out="$(as_dev ./common/scripts/00-install-plan.sh --check-releases --os rocky,windows-11-pro --no-backup 2>&1)" \
  || { echo "$out" | tail -20; fail "test 9: release-check run exited non-zero"; }
grep -qE "Latest Rocky Linux release|Could not determine the latest Rocky" <<<"$out" \
  || fail "test 9: Rocky release check did not run"
grep -qE "Newest Windows 11 version|Could not determine the latest Windows 11" <<<"$out" \
  || fail "test 9: Windows 11 release check did not run"
echo "  PASS: unknown OS rejected; Rocky + Windows 11 release checks wired"

echo "### [done] all assertions passed"
