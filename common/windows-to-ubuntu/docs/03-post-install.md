# Step 3 — Post-install: NVIDIA driver and kernel check

You're booted into Ubuntu 26.04 with this repo cloned at `~/dual-boot`.
Two scripts, in order:

```bash
cd ~/dual-boot
./devices/<your-device>/scripts/...              # device driver setup (see your
                                                 #   device page), then REBOOT
./common/ubuntu/scripts/20-kernel.sh  # releases, patches, kernel 7.0+
```

## 3.1 Device driver setup — see your device page

GPU/driver installation is device-specific. Follow the driver doc on your
device page, reboot as instructed, then return here. For the
**MSI Raider 18 HX AI** that is
[the NVIDIA driver guide](../../../devices/msi-raider-18-hx-ai/docs/nvidia-driver.md)
(`devices/msi-raider-18-hx-ai/scripts/10-nvidia-driver.sh`).

## 3.2 Kernel — `common/ubuntu/scripts/20-kernel.sh`

Ubuntu 26.04's stock kernel **is already 7.0**, but the install ISO carries
the release-pocket build (**7.0.0-14** at GA) while kernel security patches
land as newer `7.0.0-xx` packages in the `-security`/`-updates` pockets
(**7.0.0-29/-30** as of mid-August 2026). The script:

1. **Checks for releases first** *(interactive runs always; unattended runs
   only with `--check-releases`)*:
   - **Newer Ubuntu release** (`do-release-upgrade -c`) — if one exists you're
     prompted to start the guided release upgrade (never started unattended;
     distro upgrades are too disruptive to run without a human).
   - **Newer packaged kernel** — checks the `-security` pocket is present in
     your apt sources, then prompts to **download and install the newest
     `7.0.0-xx` kernel** and tells you when a reboot is needed to boot it.
2. Verifies the running kernel is 7.0+.
3. Offers to enable **unattended security upgrades**, so future kernel
   patches apply automatically without re-running anything.
4. Offers the optional newer-kernel paths:
   - **HWE stack** (`linux-generic-hwe-26.04`): currently also kernel 7.0;
     rolls forward to Canonical-signed newer kernels as point releases
     arrive. Safe default — say yes.
   - **Mainline builds** (kernel.ubuntu.com via the `mainline` tool): the
     upstream releases — 7.2 is the latest upstream stable (released
     2026-08-16), and the script's release check reports the current one
     live from kernel.org. These are **unsupported, receive no security
     updates, and are unsigned** (conflicts with Secure Boot) — and NVIDIA
     DKMS modules are not expected to build against them. Say no unless
     you're chasing a specific hardware fix. The fully *patched* path is
     always the Ubuntu `-security` pocket, never mainline.

Unattended usage: `DEV_SETUP_ASSUME_YES=1
./common/ubuntu/scripts/20-kernel.sh --check-releases` applies kernel updates and takes every other prompt's
default; without the flag, an unattended run skips the release checks
entirely.

## 3.3 Development environment (separate repo)

With the OS, driver, and kernel in place, the interactive development-tools
installer (Git, Claude Code, Docker, JDK, Maven, C/C++, Go, Rust, Elastic
Stack, Ollama) lives in its own repository — `asanderson/dev-setup` — and its
GPU-dependent pieces (NVIDIA Container Toolkit, Ollama acceleration) key off
the driver you just installed.

Anything misbehaving → [troubleshooting](troubleshooting.md).
