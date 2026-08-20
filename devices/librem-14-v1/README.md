# Purism Librem 14 (version 1)

> **This device's flow is DESTRUCTIVE by design.** Unlike every other device
> in this repo, the factory OS is **not** preserved: the internal SSD is
> wiped and **Qubes OS + PureOS are both installed fresh**. Interactive runs
> confirm the wipe (defaulting to yes); unattended runs require the explicit
> `--destructive` flag. Copy anything you need off the machine first.

| | |
|---|---|
| CPU | Intel Core i7-10710U @ 1.10/4.70GHz (Comet Lake, 6c/12t, x86_64) |
| GPU | Intel UHD Graphics (620-class iGPU — Qubes-recommended territory) |
| RAM / SSD | 64GB DDR4 (2×32GB SO-DIMM) / 2TB NVMe (M.2 2280) |
| Display / Wi-Fi | 14" FHD IPS matte · Atheros QCNFA222 (802.11n, free-firmware `ath9k`) + BT 4.0 |
| Battery | 4-cell 66.8Wh (covers the second M.2 slot — single-SSD config) |
| Security | 2 hardware kill switches (cam/mic, Wi-Fi/BT) · TPM · Intel ME disabled (HAP) · ITE IT8528E EC with free Librem EC firmware |
| Firmware | **PureBoot Bundle Anti-Interdiction**: coreboot + Heads ("PureBoot") + Librem Key + Vault USB, anti-interdiction shipping |
| Factory OS | PureOS (wiped by this flow) |
| Installed OSes | **Qubes OS 4.3.1 + PureOS 11 "Crimson"** — clean dual install |

## Boot behavior (PureBoot — there are no BIOS keys)

Power-on lands in the **PureBoot/Heads menu**, not a vendor BIOS. With the
Librem Key inserted, the TPM-sealed HOTP check runs first: **green blink =
firmware unmodified, red flashing = tamper warning** (TOTP on screen as the
phone fallback). Heads then verifies the GPG signatures (your key, on the
Librem Key) over every file in the unencrypted `/boot` before kexec-ing the
OS. Useful menu paths:

| Action | PureBoot menu path |
|---|---|
| Pick an OS / kernel entry | **Boot Options** (parsed from `/boot`'s grub configs; both OSes appear) |
| Boot the installer USB | **Options → Boot from USB** |
| Re-sign `/boot` after installs/updates | **Options → Update checksums and sign all files in /boot** |
| New-owner key setup / clean slate | **Options → OEM Factory Reset / Re-Ownership** |
| Change the tracked `/boot` device | Options → Change Configuration Settings (avoid — see quirks) |

## Device steps

1. **Anti-interdiction first**: before powering on, verify the tamper-evident
   tape and glitter-polish screw seals against the GPG-encrypted photos
   Purism sent; insert the Librem Key (shipped separately) and confirm the
   **green** HOTP blink on first power-on; change all default PINs.
   Runbook: [docs/qubes-pureos-dual-install.md](docs/qubes-pureos-dual-install.md).
2. On the factory PureOS (or the PureOS live USB), run the device entry
   script — it checks **firmware (PureBoot/EC) and both OS releases first**,
   downloads + verifies both ISOs, writes installer USBs, and performs the
   destructive disk layout:

```bash
./devices/librem-14-v1/scripts/10-dual-install-prep.sh
# unattended: DEV_SETUP_ASSUME_YES=1 ... [--check-releases] [--destructive]
```

3. Install **Qubes OS first** (partitions 1+2), **PureOS second** (partition
   3, reusing partition 1 as `/boot` **without reformatting**), then re-sign
   `/boot` in PureBoot — the runbook covers every prompt.

Release checks follow the repo contract: interactive runs always check
first; unattended runs check only with `--check-releases` and **never** flash
firmware or touch the disk without `--destructive`.

- Pinned versions: [`config/versions.env`](config/versions.env) (Qubes ISO +
  signing chain, PureOS image + sha256, PureBoot release, disk layout).

## Known quirks

- **Qubes upstream discourages dual boot** (dom0 trust argument), and
  Purism staff echo it — PureBoot's signed `/boot` + HOTP tamper check
  mitigates the classic bootloader-tampering vector, but the caveat stands.
  This configuration trades that risk knowingly; the runbook says where.
- **One `/boot` to rule both**: Heads tracks a single `/boot` device;
  per-OS `/boot` partitions are possible but switching is documented as
  fragile (Heads #959) — this flow uses the Purism-endorsed shared `/boot`.
- **Every kernel update in either OS dirties `/boot`** — expect the
  re-sign prompt (Librem Key + GPG PIN) at the next boot. Routine, not
  tamper — but only after an update you did yourself.
- **Wi-Fi is 802.11n only** (QCNFA222/`ath9k`, chosen for free firmware) —
  no 802.11ac/ax on the stock card.
- **Second M.2 slot is blocked by the 4-cell battery** in this config.
- The internal keyboard is **EC-attached, not USB**, so a Qubes USB qube
  won't lock you out of dom0; the iGPU is the Qubes-recommended graphics
  path. Install the `librem-ec-acpi` DKMS driver in dom0 for EC niceties.
- **Suspend under Qubes** is flaky on this model (qubes-issues #8061:
  frozen qubes after resume; AC/brightness oddities fixed by
  `librem-ec-acpi`) — test yours; worst case prefer shutdown.
