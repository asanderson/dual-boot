# Step 1 — Prepare macOS (do this first)

Target: any Intel Mac in [`devices/`](../../../devices) with preinstalled
macOS. Model-specific details (boot keys, hardware quirks, any macOS-upgrade
step such as OpenCore Legacy Patcher) live on your device page.

> **Design contract:** this process never modifies the macOS installation.
> Ubuntu lives in its own partition carved from free space, GRUB is added to
> the EFI System Partition *alongside* the Mac's boot machinery, and every
> change is reversible — see [Rollback](04-rollback.md).
>
> | Change | Made where | Undone by |
> |---|---|---|
> | APFS container shrunk to free space for Ubuntu | Step 1.2 | Delete Ubuntu partition → grow container back |
> | `EFI\ubuntu` (GRUB) on the EFI System Partition | Ubuntu installer | [Rollback](04-rollback.md) step 2 |
> | (Device pages only) OpenCore on the ESP for a macOS upgrade | Device page | The device page's OCLP-revert section |

## 1.0 Create a recovery safety net (before touching anything)

1. **Full Time Machine backup** to an external drive — this is the
   disaster-case guarantee (Path B in [Rollback](04-rollback.md)).
2. Confirm you can reach **macOS Recovery** (hold **Cmd+R** at boot, or
   Option to pick a recovery volume) — that's where a restore starts.
3. If **FileVault** is enabled, know your password/recovery key; resizing
   works with FileVault on, but recovery operations may prompt for it.

## 1.1 Update macOS (and do any device-page OS upgrade now)

Bring macOS current for your model first. If your device page includes a
macOS *upgrade* step (e.g. Sequoia via OpenCore Legacy Patcher on Macs whose
last supported release is older), **complete it before continuing** — the
boot chain should be in its final shape before Ubuntu is added.

## 1.2 Free space for Ubuntu

macOS keeps everything in one APFS container; shrink it to leave unallocated
space (100 GB minimum, more if the disk allows):

1. Check the container: `diskutil list` — note the `Apple_APFS Container`
   identifier (usually `disk0s2`) and its size.
2. Shrink it (example: keep 350 GB for macOS on a 500 GB disk, freeing the
   rest):

```bash
sudo diskutil apfs resizeContainer disk0s2 350g
```

The freed space is left unallocated — the Ubuntu installer will use it.
If the resize fails with "not enough space", empty the Trash, prune large
snapshots (`tmutil listlocalsnapshots /` → `tmutil deletelocalsnapshots
<date>`), and retry.

## 1.3 Create the Ubuntu install USB

On any machine, with an 8GB+ USB stick (it will be erased): download the
**Ubuntu Desktop** ISO from <https://ubuntu.com/download/desktop>, verify its
SHA-256, and write it with [balenaEtcher](https://etcher.balena.io).

## 1.4 Know your boot keys (Apple)

| Action | Key (hold immediately at power-on) |
|---|---|
| Boot picker (choose USB / Ubuntu / macOS) | **Option (⌥)** |
| macOS Recovery | **Cmd+R** |
| NVRAM reset (fixes boot-entry oddities) | **Cmd+Option+P+R** |

No firmware settings need changing on Intel Macs for this process; Startup
Security Utility settings only exist on T2/Apple Silicon machines — check
your device page.

Done? Continue to [Step 2 — Install Ubuntu](02-ubuntu-install.md).
