# Step 2 — Install Ubuntu alongside macOS

Prerequisite: [Step 1 — macOS prep](01-macos-prep.md) is complete (Time
Machine backup, any device-page macOS upgrade done, APFS container shrunk,
USB written).

## 2.1 Boot the installer

1. Plug in the USB stick. Power on holding **Option (⌥)** and pick the
   USB entry (usually labeled **EFI Boot** — if your device page installed
   OpenCore, its picker may appear first; choose the USB from there).
2. Choose **Try or Install Ubuntu**.

Once the live desktop is up, connect to Wi-Fi — your device page lists the
adapter and whether extra firmware is expected. If Wi-Fi is missing, use USB
tethering for the install and see
[troubleshooting](troubleshooting.md#wi-fi-adapter-missing).

## 2.2 Run the installer

| Screen | Choice |
|---|---|
| Type of installation | **Interactive installation** |
| Applications | Default selection is fine |
| Optimise your computer | **Tick "Install third-party software / additional media formats"** — pulls firmware (Wi-Fi, media) |
| Disk setup | **"Install Ubuntu alongside macOS"** if offered — it uses the free space from Step 1.2 |

If "alongside" is not offered, choose **Manual/Something else** and in the
free space create one `ext4` partition mounted at `/` — and select the
*existing* EFI System Partition (the ~300MB FAT volume) as *EFI System
Partition* **without formatting it** (it holds the Mac's boot files, and
OpenCore if your device page installed it).

> **Never delete, format, or resize the APFS container, the EFI System
> Partition, or any Apple recovery volumes from the Ubuntu installer.**
> Ubuntu goes only into the free space you created in Step 1.2 — that's what
> keeps [rollback](04-rollback.md) trivial.

Create your user and let the installer run; reboot when prompted, removing
the USB.

## 2.3 First boot & boot selection

Hold **Option (⌥)** at the chime: you should now see the macOS disk and an
**EFI Boot**/**ubuntu** entry (plus OpenCore's picker if the device uses it —
OpenCore can also chain-load Ubuntu directly from its own menu). Check both
OSes boot.

- Boot **macOS** once to confirm it's untouched.
- Boot **Ubuntu** and confirm the kernel: `uname -r`.

To make one OS the default: in macOS, System Settings → General → Startup
Disk; or hold Option each time to choose. GRUB is also present and lists
macOS via os-prober — use whichever picker you prefer.

**No clock fix is needed** — macOS keeps the hardware clock in UTC, exactly
like Linux (unlike the Windows pair), so the two OSes agree out of the box.

## 2.4 Update and clone this repo

```bash
sudo apt update && sudo apt full-upgrade -y   # pulls the latest kernel security updates
sudo apt install -y git
git clone https://github.com/asanderson/dual-boot.git ~/dual-boot
chmod +x ~/dual-boot/common/*/scripts/*.sh ~/dual-boot/devices/*/scripts/*.sh
```

Reboot after the `full-upgrade` so you're on the patched kernel, then
continue to [Step 3 — Post-install](03-post-install.md).
