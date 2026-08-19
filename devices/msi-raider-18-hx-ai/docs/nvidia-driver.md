# NVIDIA driver — RTX 5090 Laptop GPU (Blackwell)

Device driver step for the MSI Raider 18 HX AI, run from the repo root on
the freshly installed Ubuntu:

```bash
./devices/msi-raider-18-hx-ai/scripts/10-nvidia-driver.sh   # then REBOOT
```

This is Step 3.1 of the
[common post-install runbook](../../../common/windows-to-ubuntu/docs/03-post-install.md) —
return there for the kernel step once the driver is verified.


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

