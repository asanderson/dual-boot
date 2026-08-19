# Step 2 — Install Ubuntu 26.04 LTS alongside Windows

Prerequisite: [Step 1 — Windows prep](01-windows-prep.md) is complete
(BitLocker suspended, fast startup off, unallocated space carved out, USB
written).

Ubuntu 26.04 LTS ships with **Linux kernel 7.0** as its GA kernel — the
upstream release that followed 6.19 — so a stock install already satisfies the
"kernel 7.0 or newer" requirement. No custom kernel work is needed.

## 2.1 Boot the installer

1. Plug in the USB stick. Power on and tap your device's **one-time
   boot-menu key** at the vendor logo (see your device page).
2. Pick the USB entry listed under **UEFI** (not "Legacy"/"MBR").
3. Choose **Try or Install Ubuntu**.

> Black screen or a hang on first boot is usually the very new dGPU meeting
> the stock display driver: reboot, press `e` on the GRUB entry, append
> `nomodeset` to the line starting with `linux`, and boot with F10. This is
> only for the installer session — the proper NVIDIA driver fixes it
> permanently in Step 3.

Once the live desktop is up, connect to Wi-Fi. Modern Intel Wi-Fi 6E/7
adapters are driven by `iwlwifi` and work out of the box on kernel 7.0 with
26.04's linux-firmware — your device page lists the exact adapter and any
caveats. If Wi-Fi doesn't appear, use USB tethering for the install and see
[troubleshooting](troubleshooting.md#wi-fi-adapter-missing).

**If the installer cannot see the SSD**, stop — that's Intel VMD/RAID
mode. Follow
[the VMD procedure](troubleshooting.md#installer-cannot-see-the-ssd-intel-vmdraid)
(it involves a Windows-side step first), then come back here.

## 2.2 Run the installer

Walk through the installer with these choices:

| Screen | Choice |
|---|---|
| Type of installation | **Interactive installation** |
| Applications | Default selection is fine (post-install tooling adds the rest) |
| Optimise your computer | **Tick "Install third-party software / additional media formats"** — this pulls firmware and, when offered, the NVIDIA driver |
| Disk setup | **"Install Ubuntu alongside Windows Boot Manager"** — it uses the unallocated space from Step 1 |

If "alongside Windows" is not offered, choose **Manual/Something else** and in
the unallocated space create:

1. `ext4` mount point `/` — all remaining space (a separate `/home` is
   optional), and
2. **no new EFI partition** — select the *existing* ~300MB EFI System
   Partition and set it to be used as *EFI System Partition* **without
   formatting it** (it holds the Windows bootloader).

> **Never delete, format, or resize the Windows, EFI, or recovery partitions
> from the Ubuntu installer.** Ubuntu goes only into the unallocated space
> you created in Step 1.4 — that's what keeps
> [rollback](04-rollback.md) trivial.

Swap is unnecessary to pre-create; Ubuntu uses a swapfile by default.

3. Create your user, keep **"Require my password to log in"**, and let the
   installer run. Reboot when prompted, removing the USB.

## 2.3 First boot & GRUB

You should land in **GRUB** with entries for both *Ubuntu* and *Windows Boot
Manager*. Check both boot:

- Boot **Windows** once — this also lets BitLocker resume cleanly.
- Boot **Ubuntu**, log in, and confirm the kernel:

```bash
uname -r        # expect 7.0.x (or newer)
```

If GRUB doesn't list Windows, or the machine boots straight into one OS, see
[troubleshooting](troubleshooting.md#grub-doesnt-show-windows--machine-boots-straight-to-windows).

## 2.4 Fix the dual-boot clock skew (one command)

Windows keeps the hardware clock in local time; Linux defaults to UTC, so the
two OSes fight over it and one always shows the wrong time. Simplest durable
fix, on Ubuntu:

```bash
sudo timedatectl set-local-rtc 1 --adjust-system-clock
```

## 2.5 Update and clone this repo

The ISO installs the GA release-pocket kernel (7.0.0-14); the
`-security`/`-updates` pockets already carry newer patched `7.0.0-xx` builds
(7.0.0-29/-30 as of mid-August 2026). The `full-upgrade` below pulls them in
— **reboot afterwards** so you're running the patched kernel
(`common/ubuntu/scripts/20-kernel.sh` in Step 3 verifies this
and keeps it that way).

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y git
git clone https://github.com/asanderson/dual-boot.git ~/dual-boot
chmod +x ~/dual-boot/common/*/scripts/*.sh ~/dual-boot/devices/*/scripts/*.sh
```

Continue to [Step 3 — Post-install: NVIDIA driver and kernel check](03-post-install.md).
