# Rollback — remove Ubuntu, return to the original Windows 11 Pro setup

The dual-boot process is designed so the preinstalled Windows 11 Pro is
**never modified**: Ubuntu lives in its own partition carved from free space,
GRUB is installed *alongside* Windows Boot Manager (never replacing it), and
no file inside the Windows partition is ever written. Because of that,
rollback is a bounded, well-understood procedure — everything Ubuntu added
can be removed from within Windows.

Two rollback paths, in order of preference:

## Path A — remove Ubuntu in place (normal case, ~15 minutes)

Everything happens inside Windows. Steps 2–4 are automated by
[`scripts/windows/rollback-ubuntu.ps1`](../scripts/windows/rollback-ubuntu.ps1)
(run as Administrator; it confirms before each change) — or do them by hand:

### 1. Boot into Windows

At the GRUB menu pick **Windows Boot Manager** (or press F11 at the MSI logo
and choose Windows Boot Manager directly).

### 2. Remove the `ubuntu` firmware boot entry

Admin PowerShell:

```powershell
bcdedit /enum firmware
# find the entry whose description is "ubuntu"; copy its {guid}
bcdedit /delete "{guid}"
```

The machine now boots straight into Windows again, exactly as shipped.

### 3. Clean Ubuntu's files off the EFI System Partition

GRUB's files sit in their own `EFI\ubuntu` folder on the shared EFI
partition; the Windows bootloader in `EFI\Microsoft` is untouched. Admin
PowerShell:

```powershell
mountvol S: /S
Remove-Item -Recurse -Force S:\EFI\ubuntu
mountvol S: /D
```

### 4. Undo the Windows-side prep settings (optional)

Only two Windows settings were changed during setup, both trivially
reversible:

```powershell
powercfg /h on          # re-enable hibernation + Fast Startup
Resume-BitLocker -MountPoint C:   # if protection is still suspended
```

(If you switched the BIOS storage mode from VMD/RAID to AHCI during install,
you can leave it — Windows runs fine on AHCI — or revert it with the same
safe-mode procedure from [troubleshooting](troubleshooting.md#installer-cannot-see-the-2tb-ssd-intel-vmdraid),
in reverse.)

### 5. Reclaim the disk space

Win+X → **Disk Management**:

1. Right-click the Ubuntu partition (shows with no drive letter and no file
   system label) → **Delete Volume**. It becomes unallocated space.
2. Right-click **C:** → **Extend Volume…** → accept the defaults. C: grows
   back to its original size. (This works because Ubuntu's partition was
   carved from the end of C:, so the unallocated space is adjacent.)

Done — layout, boot flow, and settings are back to the factory configuration.

## Path B — full restore from the pre-install image (disaster case)

If anything went wrong badly enough that Path A doesn't apply (partition
table damage, Windows won't boot), restore the **system image you created in
[Step 1.0](01-windows-prep.md#10-create-a-recovery-safety-net-before-touching-anything)**:
boot the Windows recovery drive → *Troubleshoot → Advanced options → System
Image Recovery* → point it at the image on your external drive. This returns
the SSD bit-for-bit to the preconfigured state, including the recovery
partitions and BitLocker setup.

This is why Step 1.0 is not optional: Path A covers every expected case, but
the image is the guarantee.

## What was never touched (so needs no rollback)

- The Windows partition's contents — no file in `C:\` is created, modified,
  or deleted by any doc, config, or script in this repo.
- Windows Boot Manager (`EFI\Microsoft` on the ESP) — GRUB chain-loads it;
  it is never replaced or edited.
- The Windows recovery partitions and the factory BitLocker configuration
  (suspension is temporary and self-re-arming).
- Windows Registry, drivers, MSI Center configuration, and licensing.
