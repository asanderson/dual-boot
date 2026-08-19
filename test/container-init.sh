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

echo "### [done] all assertions passed"
