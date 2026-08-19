# Rollback — remove Ubuntu, return to the original macOS setup

Ubuntu was added without modifying macOS: its partition came from free
space, and GRUB sits in its own `EFI/ubuntu` folder on the shared EFI System
Partition. Everything can be removed from within macOS.

(If your device page also upgraded macOS via OpenCore Legacy Patcher, that
is a separate, independent layer — reverting it is covered on the device
page, and you can keep it while removing Ubuntu, or vice versa.)

## Path A — remove Ubuntu in place (normal case, ~15 minutes)

### 1. Boot into macOS

Hold **Option (⌥)** at power-on and choose the macOS disk.

### 2. Remove GRUB from the EFI System Partition

```bash
diskutil list                        # find the EFI partition, usually disk0s1
sudo mkdir -p /Volumes/ESP
sudo diskutil mount -mountPoint /Volumes/ESP disk0s1
sudo rm -rf /Volumes/ESP/EFI/ubuntu
sudo diskutil unmount /Volumes/ESP
```

(Only `EFI/ubuntu` goes — Apple's boot files, and `EFI/OC` if your device
uses OpenCore, are untouched.)

### 3. Delete the Ubuntu partition and grow APFS back

```bash
diskutil list                        # find the Linux partition (type "Microsoft Basic Data" or "Linux Filesystem")
sudo diskutil eraseVolume free free /dev/disk0sN   # N = the Ubuntu partition
sudo diskutil apfs resizeContainer disk0s2 0       # 0 = grow to fill available space
```

### 4. Clean up boot entries

macOS's Startup Disk (System Settings → General) will no longer show the
Ubuntu entry once GRUB's files are gone. If the Option-key picker still
shows a stale entry, reset NVRAM: reboot holding **Cmd+Option+P+R** through
a second startup chime.

Done — disk layout and boot flow are back to the pre-Ubuntu state.

## Path B — full restore (disaster case)

Boot **macOS Recovery** (Cmd+R) → *Restore from Time Machine* → pick the
backup made in [Step 1.0](01-macos-prep.md#10-create-a-recovery-safety-net-before-touching-anything).
This is why Step 1.0 is not optional.

## What was never touched (so needs no rollback)

- The APFS container's contents — no file inside macOS is created, modified,
  or deleted by this runbook.
- Apple's boot files on the ESP (and OpenCore's, where the device page uses
  it) — GRUB was added alongside them, never in their place.
- macOS Recovery, FileVault configuration, and NVRAM (unless you chose to
  reset it above).
