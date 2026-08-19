#!/usr/bin/env bash
# gpu-path-init.sh — runs INSIDE a fresh Ubuntu container (as root).
# Exercises the GPU-present path of the Raider's 10-nvidia-driver.sh that the
# default assertions (no GPU -> graceful refusal) can never reach, using an
# lspci stub that exposes the MSI Raider 18's RTX 5090 Laptop GPU. The driver
# packages install for real from the Ubuntu archive; this validates driver
# selection and install machinery, not module loading — that still needs the
# real machine (the container has no GPU and no matching kernel headers, so
# DKMS skips or builds without loading).
#
# Three runs cover every driver-selection branch (B and C are fast — the
# packages are already installed after A):
#   run A  ubuntu-drivers makes no recommendation -> versions.env fallback
#   run B  ubuntu-drivers recommends the non-open branch -> '-open' variant
#   run C  ubuntu-drivers recommends the -open package -> taken as-is
#
# Invoked by test/container-test.sh --gpu-path — not meant for a real machine.
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
# The driver pulls GB-scale packages; ride out transient download hiccups.
echo 'Acquire::Retries "5";' >/etc/apt/apt.conf.d/80-retries
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

# shellcheck source=../devices/msi-raider-18-hx-ai/config/versions.env
source /repo/devices/msi-raider-18-hx-ai/config/versions.env
BRANCH_PKG="nvidia-driver-${NVIDIA_DRIVER_BRANCH}"
TARGET="${BRANCH_PKG}-open"

echo "### [init] lspci stub exposing the RTX 5090 Laptop GPU (no GPU in this container)"
cat >/usr/local/bin/lspci <<'STUB'
#!/bin/bash
# Test stub simulating the MSI Raider's GPU on the PCI bus.
echo "0000:01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GB203M [GeForce RTX 5090 Laptop GPU] [10de:2c58] (rev a1)"
exit 0
STUB
chmod +x /usr/local/bin/lspci

# Rewrite the ubuntu-drivers stub between runs; /usr/local/bin shadows the
# real binary that run A installs at /usr/bin/ubuntu-drivers.
stub_recommendation() {
  {
    echo '#!/bin/bash'
    echo '# Test stub: canned ubuntu-drivers recommendation.'
    echo '[[ "${1:-}" == "devices" ]] || exit 0'
    echo "echo 'driver   : $1 - distro non-free recommended'"
    echo "echo 'driver   : xserver-xorg-video-nouveau - distro free builtin'"
  } >/usr/local/bin/ubuntu-drivers
  chmod +x /usr/local/bin/ubuntu-drivers
}

as_dev() {
  sudo -u dev -H env \
    https_proxy="${https_proxy:-}" no_proxy="${no_proxy:-}" \
    DEV_SETUP_ASSUME_YES=1 \
    bash -c "cd ~/dual-boot && $*"
}

run_driver() { as_dev ./devices/msi-raider-18-hx-ai/scripts/10-nvidia-driver.sh 2>&1; }

echo "### [run A] no ubuntu-drivers recommendation -> versions.env fallback (${TARGET})"
out="$(run_driver)" || { echo "$out" | tail -30; fail "run A: script exited non-zero"; }
grep -q "Secure Boot is disabled" <<<"$out" || fail "run A: Secure Boot no-EFI branch not taken"
grep -q "ubuntu-drivers made no recommendation; falling back to ${TARGET}" <<<"$out" \
  || fail "run A: fallback warning missing"
grep -q "Installing: ${TARGET}" <<<"$out" || fail "run A: did not select ${TARGET}"
grep -q "Proceed with ${TARGET}.*-> y" <<<"$out" || fail "run A: install prompt did not take default yes"
grep -q "Also install the CUDA toolkit.*-> n" <<<"$out" || fail "run A: CUDA prompt did not take default no"
dpkg -s "${TARGET}" >/dev/null 2>&1 || fail "run A: ${TARGET} package not installed"
dpkg -s nvidia-cuda-toolkit >/dev/null 2>&1 && fail "run A: CUDA toolkit installed despite default no"
command -v nvidia-smi >/dev/null 2>&1 || fail "run A: nvidia-smi missing after driver install"
grep -q "Driver installed: ${TARGET}" <<<"$out" || fail "run A: final success line missing"
echo "  PASS: fallback pin installed ${TARGET}; CUDA prompt defaulted to no"

echo "### [run B] recommendation is the non-open branch -> '-open' variant preferred"
stub_recommendation "${BRANCH_PKG}"
out="$(run_driver)" || { echo "$out" | tail -30; fail "run B: script exited non-zero"; }
grep -q "Installing: ${TARGET}" <<<"$out" || fail "run B: non-open recommendation was not upgraded to ${TARGET}"
grep -q "made no recommendation" <<<"$out" && fail "run B: fallback fired despite a recommendation"
grep -q "No '-open' variant" <<<"$out" && fail "run B: '-open' variant lookup failed"
echo "  PASS: ${BRANCH_PKG} recommendation upgraded to ${TARGET}"

echo "### [run C] recommendation is already the -open package -> taken as-is"
stub_recommendation "${TARGET}"
out="$(run_driver)" || { echo "$out" | tail -30; fail "run C: script exited non-zero"; }
grep -q "Installing: ${TARGET}" <<<"$out" || fail "run C: -open recommendation not taken as-is"
grep -q "made no recommendation" <<<"$out" && fail "run C: fallback fired despite a recommendation"
echo "  PASS: ${TARGET} recommendation taken directly"

echo "### [done] GPU-present driver path verified (selection + install; module load needs hardware)"
