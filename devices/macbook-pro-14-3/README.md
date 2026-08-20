# MacBook Pro (15-inch, 2017) — MacBookPro14,3

| | |
|---|---|
| CPU | Intel Core i7-7700HQ @ 2.80GHz (Kaby Lake, x86_64) |
| GPU | AMD Radeon Pro 555/560 (dGPU) + Intel HD Graphics 630 (iGPU) |
| RAM / SSD | 16GB LPDDR3 / Apple NVMe |
| Wi-Fi / extras | Broadcom BCM43602 (802.11ac) · Touch Bar · T1 chip |
| Factory OS | macOS 13.7.8 Ventura (build 22H730) — the last natively supported release for this model |
| OS upgrade | **macOS 15 Sequoia via OpenCore Legacy Patcher** — [guide](docs/macos-sequoia-oclp.md) |
| Added OS | Ubuntu 26.04 LTS (kernel 7.0) |

The order matters: **upgrade macOS via OCLP first**, then follow the
[common macOS → Ubuntu runbook](../../common/macos-to-ubuntu/docs/01-macos-prep.md)
(steps 1–4); this page holds everything specific to this machine.

## Boot keys (Apple)

| Action | Key (hold at power-on) |
|---|---|
| Boot picker (USB / Ubuntu / macOS / OpenCore) | **Option (⌥)** |
| macOS Recovery | **Cmd+R** |
| NVRAM reset | **Cmd+Option+P+R** |

No Startup Security Utility on this model (that's T2/Apple Silicon) — USB
boot works out of the box.

## Device steps

1. **On macOS, first** — clone this repo (or copy the script) and run the
   device entry script: it checks the latest OpenCore Legacy Patcher release
   and this Mac's macOS state, and prompts to start the
   **[Sequoia upgrade via OCLP](docs/macos-sequoia-oclp.md)**:

```bash
./devices/macbook-pro-14-3/scripts/00-macos-oclp-check.sh
```

2. Common runbook steps 1–2 (prep + Ubuntu install).
3. On the installed Ubuntu — hardware setup, which finishes by offering the
   shared **Ubuntu release + kernel patch check**:

```bash
cd ~/dual-boot
./devices/macbook-pro-14-3/scripts/10-mac-setup.sh   # firmware/driver prechecks first,
                                                     #   then Wi-Fi firmware, fans, inputs,
                                                     #   then Ubuntu/kernel release check
```

The Linux-side script **prechecks firmware and driver updates first**: an
fwupd/LVFS query plus **this device's specific components** —
`linux-firmware` (BCM43602 Wi-Fi/`brcmfmac`, Bluetooth), `intel-microcode`
(i7-7700HQ), and Mesa (Radeon Pro 555/560 `amdgpu` userspace); `applespi`,
`applesmc`, and `amdgpu` itself are in-kernel and update with the kernel
check. (Apple EFI/SMC firmware ships only through macOS — boot the
OCLP-managed macOS side periodically to receive it.) Both scripts prompt interactively by default;
unattended runs (`DEV_SETUP_ASSUME_YES=1`) take each prompt's default and
skip the prechecks/release checks unless `--check-releases` is passed — the
same contract as `common/ubuntu/scripts/20-kernel.sh`. Firmware is never
flashed unattended, and the macOS Sequoia upgrade itself is never started
unattended (it's a guided GUI flow). The Linux-side script also **verifies
the [common install plan's](../../common/docs/install-plan.md) security
decisions**: disk encryption (LUKS via `lsblk`) is checkable; a Secure Boot
requirement is reported as unenforceable — pre-T2 Apple hardware has no
UEFI Secure Boot for Linux.

- Pinned versions: [`config/versions.env`](config/versions.env)
  (OpenCore Legacy Patcher release).

## Known quirks (Linux side)

Community-reported for 2016–2017 MacBook Pros — not adversarially verified
on this exact unit; confirm on your machine:

- **Keyboard/trackpad** use Apple's SPI bus — the mainline `applespi` driver
  handles both on kernel 7.0; no action expected.
- **Wi-Fi (BCM43602)** is driven by mainline `brcmfmac` with firmware from
  `linux-firmware` — normally works out of the box; the device script
  verifies it. Bluetooth rides the same module.
- **Touch Bar** has no full mainline support: expect it blank under Linux.
  Function keys work via the physical `fn` layer through `applespi`;
  community drivers (e.g. `tiny-dfr` lineage) exist but are out of scope
  here.
- **Fan control**: `applesmc` exposes sensors on pre-T2 Macs; the device
  script offers `mbpfan` for automatic fan curves.
- **Suspend/resume** is historically flaky on this generation (dGPU +
  `brcmfmac` wake issues) — test yours; worst case, prefer shutdown.
- **Graphics**: the machine boots Linux on the AMD dGPU (`amdgpu`,
  well-supported); iGPU/dGPU switching via `vga_switcheroo` is possible but
  fiddly and left as an exercise.
