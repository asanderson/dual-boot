# Qubes OS 4.3.1 + PureOS 11 "Crimson" — clean dual install (Librem 14 v1)

The full runbook for wiping the Librem 14's SSD and installing both OSes
fresh under PureBoot. Follow it top to bottom; the device
[README](../README.md) has the hardware table and PureBoot menu map.

## 0. What you're accepting

- **Everything on the internal SSD is destroyed**, including the factory
  PureOS. "Rollback" afterwards means reinstalling PureOS from a live USB
  (step 8) — there is no preserved factory state.
- **Qubes OS officially discourages multibooting**: the FAQ answers the
  dual-boot question with "You shouldn't do that, because it poses a
  security risk", and its multiboot guide names the risks — the unencrypted
  `/boot` can be maliciously modified by the other OS, and the other OS
  could infect firmware. On this machine those exact vectors are what
  PureBoot exists to *detect*: Heads GPG-verifies every file in `/boot`
  against your Librem Key on each boot, and the TPM-sealed HOTP check
  attests the firmware itself (the same role Anti Evil Maid plays in Qubes'
  guide — detection, not prevention). The residual risk is real and this
  configuration accepts it knowingly: a compromised PureOS still shares a
  machine with dom0.
- The Librem 14 v1 is **community-HCL hardware** for Qubes (4.0/4.1 reports:
  Wi-Fi, Ethernet, USB, webcam, kill switches all working; Purism sold Qubes
  preinstalls on this model), not formally Qubes-certified.

## 1. Anti-interdiction arrival checklist (before first power-on)

1. Compare the tamper-evident tape (outer + inner box) and the glitter
   nail-polish screw seals against the GPG-encrypted photos Purism sent
   out-of-band. Photograph everything yourself too. Any discrepancy: stop,
   contact ops@puri.sm with your order number.
2. The Librem Key shipped separately — have it in hand before the laptop
   powers on. Insert it, power on: **green blinking LED = HOTP passed**
   (firmware unmodified); **red flashing = tamper warning**: stop, don't
   type any secrets, contact Purism.
3. Change every default/custom PIN Purism set (Librem Key user + admin PIN,
   TPM owner password) to values only you know.
4. Defer **OEM Factory Reset / Re-Ownership** until step 6 — one reset at
   the end covers the install churn and leaves a clean, self-owned signed
   state (Purism staff suggest exactly this for multi-OS setups).

## 2. Prep on the factory PureOS — run the device script

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/asanderson/dual-boot.git ~/dual-boot
cd ~/dual-boot && chmod +x devices/*/scripts/*.sh
./devices/librem-14-v1/scripts/10-dual-install-prep.sh \
    --usb-qubes /dev/sdX --usb-pureos /dev/sdY   # two ≥8GB sticks
```

The script, in order (interactive runs always; unattended only with
`--check-releases`, and the wipe only with `--destructive`):

1. **Firmware precheck first**: installed PureBoot version (from DMI, e.g.
   `PureBoot-Release-30.1`) vs the latest release Purism ships (read from
   the `PUREBOOT_VERSION_14` pin in Purism's own flashing utility), plus an
   fwupd/LVFS query. If PureBoot is behind, update it **before** installing
   the OSes — either `sudo bash coreboot_util.sh` from Linux, or PureBoot
   menu → Options → **Flash/Update the BIOS** with the ROM zip from
   `source.puri.sm/firmware/releases` on USB. After any firmware flash,
   PureBoot prompts to generate a new HOTP/TOTP secret on the next boot
   (expected — the Librem Key blinks red until you do). The Librem EC
   firmware (pin: 1.14) updates separately via Purism's dedicated
   `Librem_14_EC_Update.iso`; the script reports, never flashes.
2. **OS release checks**: latest Qubes (from the official ISO mirror) and
   latest PureOS image set vs the pins in
   [`config/versions.env`](../config/versions.env).
3. **Download + verify both ISOs**: Qubes via detached PGP signature and
   the release-key→master-key chain (pinned fingerprint
   `427F 11FD 0FAA 4B08 0123 F01C DDFA 1A3E 3687 9494`); PureOS via pinned
   SHA256 cross-checked against Purism's published checksum file (Purism
   publishes no GPG signatures for these images).
4. **Write the two installer USBs** (each write confirmed).
5. **The destructive step** — refused while the target disk hosts the
   running system, so it actually executes in step 3 below.

## 3. Wipe + partition from the PureOS live USB

Boot the PureOS stick (PureBoot menu → Options → Boot from USB), open a
terminal, clone the repo again (or mount the download dir), and run the
script once more — this time the wipe prompt is reachable:

```bash
./devices/librem-14-v1/scripts/10-dual-install-prep.sh          # confirm wipe (default yes)
# or unattended:
DEV_SETUP_ASSUME_YES=1 ./devices/librem-14-v1/scripts/10-dual-install-prep.sh --destructive
```

Resulting GPT layout on the 2TB NVMe (no ESP — PureBoot/Heads kexecs
directly and never runs UEFI/GRUB as a boot loader):

| # | Size | Label | Purpose |
|---|---|---|---|
| 1 | 2 GiB | `boot` | **Shared unencrypted `/boot`** — Heads tracks one `/boot` device, signs every file in it, and parses *both* OSes' grub configs (`grub2/grub.cfg` from Qubes, `grub/grub.cfg` from PureOS) into its Boot Options menu |
| 2 | 1000 GiB | `qubes-luks` | Qubes LUKS (root/swap laid down by its installer) |
| 3 | rest (~860 GiB) | `pureos-luks` | PureOS LUKS root |

Qubes' own multiboot guidance prefers installing Qubes last because its
installer overwrites GRUB's config and won't list other OSes (os-prober is
deliberately disabled — qubes-issues #3022). Under PureBoot that concern
doesn't gate the order: GRUB never executes, and Heads reads each OS's
config file independently from the shared `/boot`. We install **Qubes
first** because its installer is the pickier of the two about custom
layouts.

## 4. Install Qubes OS (first)

1. PureBoot menu → Options → Boot from USB → Qubes stick. (Expect `/boot`
   signature warnings throughout installs — ignore until step 6.)
2. In the installer: Installation Destination → select only the internal
   NVMe → **"I will configure partitioning"** (Blivet GUI):
   - partition 1 → mount `/boot`, ext4, **format** (first install only);
   - partition 2 → LUKS container, "Encrypt my data", root + swap inside
     (the default LVM-thin layout Qubes proposes is fine).
   Never "erase disk"/automatic — that destroys the layout.
3. Set a strong LUKS passphrase; install; reboot; finish the Qubes
   first-boot wizard (leave the default qubes; sys-usb: yes — the internal
   keyboard is EC-attached, not USB, so a USB qube won't lock you out).
4. Verify Qubes boots from the PureBoot Boot Options menu.

## 5. Install PureOS (second)

1. PureBoot menu → Options → Boot from USB → PureOS stick → run the
   installer (Calamares) → Manual partitioning:
   - partition 1 → mount `/boot`, **do NOT format** (Qubes' kernels live
     there now; the installers coexist);
   - partition 3 → LUKS root (create/encrypt, mount `/`);
   - bootloader destination: accept the default (vestigial under Heads).
2. Install, reboot. Both OSes' entries now appear in Heads' Boot Options.

## 6. Re-sign, re-own, set the default

1. PureBoot menu → **Options → Update checksums and sign all files in
   /boot** → Yes → insert Librem Key → GPG user PIN (typed blind). This
   blesses the current `/boot` (both OSes).
2. Recommended: **Options → OEM Factory Reset / Re-Ownership** now — wipes
   the Librem Key, resets the TPM, generates *your* GPG key on the key
   (3–10 min), flashes the public key into PureBoot, then re-seal the
   HOTP/TOTP secret when prompted after reboot. Re-sign `/boot` once more
   afterwards (step 6.1).
3. In Boot Options, select the OS you want as default and save it
   (**d** — the saved default is itself signed).

## 7. Living with it

- **Every kernel update in either OS** changes `/boot` → PureBoot prompts
  to re-sign at the next boot. Expected after an update you ran yourself;
  treat it as a red flag any other time.
- **Qubes updates**: dom0 + templates via the Qubes updater. **PureOS
  updates**: apt (Crimson tracks Debian 12; the PureOS Upgrade app handles
  future codename jumps). Re-run the device script any time for the
  firmware + release prechecks.
- **Firmware updates later**: same flow as step 2.1 — flash, re-seal
  HOTP/TOTP, re-sign `/boot`, and on this anti-interdiction unit re-check
  your tamper evidence first.

## 8. Rollback (factory-like state)

Boot the PureOS live USB → installer → erase disk → single PureOS install,
then PureBoot **OEM Factory Reset / Re-Ownership** and a final `/boot`
re-sign. That reproduces the factory software state (your keys instead of
factory-paired ones).

## Troubleshooting / quirks (community-reported)

- **Suspend/resume under Qubes**: qubes-issues #8061 reports all qubes
  frozen after resume on the Librem 14 (kill/restart affected VMs). Erratic
  AC-power detection and brightness after suspend are fixed by installing
  the `librem-ec-acpi` DKMS driver in dom0.
- **Audio jack** doesn't auto-switch output — select it manually.
- **Touchpad tap-to-click** may need an xorg tweak in dom0.
- **Bluetooth** (on the ath9k combo module) appears as a USB device — after
  creating sys-usb, attach it there deliberately.
- **Wi-Fi is 802.11n** (free-firmware `ath9k`) — that's the design, not a
  fault.
- **PureBoot "squirrelly" multi-`/boot` behavior** (Heads #959) is exactly
  why this layout shares one `/boot` — don't split it later.
