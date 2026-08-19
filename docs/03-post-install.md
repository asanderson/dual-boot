# Step 3 — Post-install: NVIDIA driver and kernel check

You're booted into Ubuntu 26.04 with this repo cloned at `~/dual-boot`.
Two scripts, in order:

```bash
cd ~/dual-boot
./scripts/10-nvidia-driver.sh   # NVIDIA driver (then REBOOT)
./scripts/20-kernel.sh          # confirm kernel 7.0+, optional newer kernels
```

## 3.1 NVIDIA driver — `scripts/10-nvidia-driver.sh`

The RTX 5090 Laptop GPU (Blackwell) is supported **only by NVIDIA's open GPU
kernel modules** — NVIDIA states the proprietary kernel modules are
unsupported on this generation. The current production branch is **R595**
(595.58.03+, which explicitly lists the RTX 5090 Laptop GPU as supported, and
which Ubuntu 26.04 packages); the previous **580** branch (CUDA 13.x era) also
carries Blackwell support. The script:

1. Checks Secure Boot state and explains **MOK enrollment** (below).
2. Runs `ubuntu-drivers devices` and installs the recommended driver,
   preferring the `-open` variant (e.g. `nvidia-driver-595-open`).
3. Optionally installs the CUDA toolkit.

### MOK enrollment (Secure Boot only)

With Secure Boot enabled, the driver modules are signed with a Machine Owner
Key. During install you set a one-time password; on the next reboot a blue
**"Perform MOK management"** screen appears **once**:

> **Enroll MOK** → **Continue** → **Yes** → type the password → **Reboot**

Skip it and the driver silently fails to load. If that happens, re-run
`sudo update-secureboot-policy --enroll-key` and reboot again.

### Verify after reboot

```bash
nvidia-smi                     # shows "GeForce RTX 5090 Laptop GPU" + driver version
prime-select query             # hybrid graphics mode: on-demand (default) / nvidia / intel
```

`on-demand` renders the desktop on the Intel iGPU (better battery) and runs
CUDA/games on the NVIDIA dGPU per-app (`__NV_PRIME_RENDER_OFFLOAD=1
__GLX_VENDOR_LIBRARY_NAME=nvidia <app>` forces offload). `sudo prime-select
nvidia` pins everything to the dGPU — useful when external monitors are wired
to it. The Raider also has a BIOS/MSI-Center MUX ("discrete mode") that
bypasses hybrid graphics entirely; Linux is happiest in the default hybrid
mode.

## 3.2 Kernel — `scripts/20-kernel.sh`

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
   - **Mainline builds** (kernel.ubuntu.com via the `mainline` tool):
     bleeding edge (7.1+/7.2-rc). These are **unsupported, receive no
     security updates, and are unsigned** (conflicts with Secure Boot) — and
     NVIDIA DKMS modules are not expected to build against them. Say no
     unless you're chasing a specific hardware fix. The fully *patched* path
     is always the Ubuntu `-security` pocket, never mainline.

Unattended usage: `DEV_SETUP_ASSUME_YES=1 ./scripts/20-kernel.sh
--check-releases` applies kernel updates and takes every other prompt's
default; without the flag, an unattended run skips the release checks
entirely.

## 3.3 Development environment (separate repo)

With the OS, driver, and kernel in place, the interactive development-tools
installer (Git, Claude Code, Docker, JDK, Maven, C/C++, Go, Rust, Elastic
Stack, Ollama) lives in its own repository — `asanderson/dev-setup` — and its
GPU-dependent pieces (NVIDIA Container Toolkit, Ollama acceleration) key off
the driver you just installed.

Anything misbehaving → [troubleshooting](troubleshooting.md).
