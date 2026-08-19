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

1. **[macOS Sequoia via OCLP](docs/macos-sequoia-oclp.md)** — before
   touching partitions.
2. Common runbook steps 1–2 (prep + Ubuntu install).
3. On the installed Ubuntu:

```bash
cd ~/dual-boot
./devices/macbook-pro-14-3/scripts/10-mac-setup.sh   # Wi-Fi firmware, fan control, input checks
./common/ubuntu/scripts/20-kernel.sh                 # releases, patches, version check
```

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
