# macOS Sequoia on the 2017 MacBook Pro via OpenCore Legacy Patcher

Apple ended this model's macOS support at **Ventura 13** (you're on 13.7.8,
build 22H730). [OpenCore Legacy Patcher](https://dortania.github.io/OpenCore-Legacy-Patcher/)
(OCLP) by Dortania boots newer macOS on unsupported Macs by inserting the
OpenCore bootloader ahead of macOS and patching the installed system.
**Sequoia (macOS 15) is the newest release OCLP supports** — 15.7.9 was
current in mid-August 2026 with 15.8 at release candidate; macOS 26 "Tahoe"
is *not* supported for this machine. The OCLP release is pinned in
[`../config/versions.env`](../config/versions.env) (2.4.1 at the time of
writing — use the newest from the
[releases page](https://github.com/dortania/OpenCore-Legacy-Patcher/releases)).

> **Do this before the Ubuntu install** (common runbook step 1.1): OpenCore
> lands in the EFI System Partition, and the boot chain should be in its
> final shape before GRUB joins it. Ubuntu coexists fine with OpenCore —
> both live in their own ESP folders (`EFI/OC`, `EFI/ubuntu`).

> **Understand the trade-offs first** (Dortania documents these): OCLP
> lowers SIP/security settings to allow root patches, system updates must go
> through OCLP-aware flows (the app watches for OS updates and re-patches),
> and this is a community project — a Time Machine backup is mandatory, and
> Ventura remains a supported fallback you can restore to.

## Steps

1. **Back up** — full Time Machine backup (this doubles as common-runbook
   Step 1.0).
2. **Download OCLP** — grab the `.pkg`/app from the official
   [GitHub releases](https://github.com/dortania/OpenCore-Legacy-Patcher/releases)
   (Dortania is the only official source) and open it on the Mac.
3. **Create the Sequoia installer** — in OCLP: *Create macOS Installer* →
   *Download macOS Installer* → pick the newest **macOS 15 Sequoia** → let it
   write a 16GB+ USB stick.
4. **Install OpenCore** — in OCLP: *Build and Install OpenCore* → install to
   the **USB** first (safer trial) or directly to the internal disk's EFI.
5. **Boot through OpenCore** — reboot holding **Option (⌥)**, pick the
   **EFI Boot** entry (OpenCore), and from OpenCore's picker choose the
   Sequoia installer. Complete the installation (several reboots — always
   let OpenCore drive them).
6. **Post-install root patches** — first boot into Sequoia, OCLP prompts (or
   run it → *Post-Install Root Patch*) to install the graphics patches this
   model needs (Kaby Lake iGPU + Radeon dGPU stacks). Reboot.
7. **Move OpenCore to the internal disk** if you trialed from USB (*Build
   and Install OpenCore* → internal EFI), so the machine boots patched macOS
   without the stick.
8. **Updates from now on**: let the OCLP app manage macOS point updates
   (e.g. 15.8) — it re-applies root patches after each one. Update OCLP
   itself from the releases page before major macOS updates.

## Verify

- ** → About This Mac** shows macOS Sequoia 15.x.
- Graphics acceleration works (smooth UI, Maps/screensavers render) —
  if not, re-run *Post-Install Root Patch*.
- Reboot once more via the Option picker and confirm the default boot path
  lands in Sequoia without the USB attached.

## Reverting

OCLP is a layer, not a one-way door: to return to the factory state, restore
the Ventura Time Machine backup (or reinstall Ventura from Apple's full
installer), then mount the ESP and delete `EFI/OC`, and reset NVRAM
(**Cmd+Option+P+R**). Removing Ubuntu later is independent — see the
[common rollback](../../../common/macos-to-ubuntu/docs/04-rollback.md).
