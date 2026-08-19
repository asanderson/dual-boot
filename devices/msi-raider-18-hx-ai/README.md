# MSI Raider 18 HX AI (A2XWJG-069US)

| | |
|---|---|
| CPU | Intel Core Ultra 9 285HX ("Arrow Lake-HX") |
| GPU | NVIDIA GeForce RTX 5090 Laptop GPU (Blackwell) + Intel iGPU (hybrid) |
| RAM / SSD | 64GB DDR5-6400 / 2TB NVMe |
| Display / Wi-Fi | 18" 120Hz / Intel Killer BE1750 (Wi-Fi 7, BE200-class) |
| Factory OS → added OS | Windows 11 Pro → Ubuntu 26.04 LTS (kernel 7.0) |

Follow the [common Windows → Ubuntu runbook](../../common/windows-to-ubuntu/docs/01-windows-prep.md)
(steps 1–4); this page holds everything specific to this machine.

## BIOS keys

| Action | Key (press repeatedly at the MSI logo) |
|---|---|
| BIOS setup | **Del** (then **F7** toggles Advanced mode) |
| One-time boot menu | **F11** |

> These keys come from MSI's support documentation and community reports for
> this laptop family, but were not independently verified on the A2XWJG
> specifically — if one doesn't respond, try the other, or use Windows:
> Settings → System → Recovery → Advanced startup → *UEFI Firmware Settings*.

## Device steps (after the common install, steps 1–2)

```bash
cd ~/dual-boot
./devices/msi-raider-18-hx-ai/scripts/10-nvidia-driver.sh   # driver + MOK, then REBOOT
./common/windows-to-ubuntu/scripts/20-kernel.sh             # releases, patches, 7.0+ check
```

- **[NVIDIA driver guide](docs/nvidia-driver.md)** — Blackwell requires the
  open kernel modules (R595 branch); covers MOK enrollment, verification, and
  PRIME/MUX behavior.
- **[Research notes](docs/research-notes.md)** — cited, verified findings
  behind this device's runbook, with unverified items marked.
- Pinned versions: [`config/versions.env`](config/versions.env)
  (NVIDIA driver branch fallback).

## Known quirks

- **Storage ships in Intel VMD/RAID mode** — the Ubuntu installer may not see
  the SSD until it's switched to AHCI via the
  [safe-mode procedure](../../common/windows-to-ubuntu/docs/troubleshooting.md#installer-cannot-see-the-ssd-intel-vmdraid)
  (reversible).
- **Wi-Fi (Killer BE1750)** — `iwlwifi`-supported since kernel 6.5; works out
  of the box on 26.04's kernel 7.0 with current linux-firmware. If missing:
  [troubleshooting](../../common/windows-to-ubuntu/docs/troubleshooting.md#wi-fi-adapter-missing).
- **Suspend/resume** — RTX 50-series s2idle resume hangs on kernel 7.0 are a
  known NVIDIA tracker issue; see
  [troubleshooting](../../common/windows-to-ubuntu/docs/troubleshooting.md#suspendresume-hangs-rtx-50-series--kernel-70).
