# Troubleshooting (macOS → Ubuntu)

Device-specific quirks (Wi-Fi model, Touch Bar, fan control, suspend) are on
your device page; this covers the pair-generic issues.

## Wi-Fi adapter missing

Intel Macs use Broadcom adapters driven by `brcmfmac` (newer) or `wl`/
`broadcom-sta` (older) — your device page says which. First try:

```bash
sudo apt update && sudo apt full-upgrade -y     # newest linux-firmware
sudo dmesg | grep -iE 'brcm|firmware'           # look for firmware load errors
```

A missing `brcmfmac*.bin`/`.txt` message means the firmware isn't shipped for
your exact board — see the device page. Bluetooth usually follows the Wi-Fi
firmware.

## Option-key picker doesn't show Ubuntu / boots straight to macOS

- GRUB's files must exist on the ESP (`EFI/ubuntu`) — verify from Ubuntu
  (`ls /boot/efi/EFI`) or macOS (mount the ESP per
  [rollback step 2](04-rollback.md#2-remove-grub-from-the-efi-system-partition)).
- Reset NVRAM (**Cmd+Option+P+R** through a second chime) — stale boot
  entries are the usual cause.
- In macOS, System Settings → General → Startup Disk re-blesses the default;
  after changing it, the Option picker still offers everything else.

## GRUB doesn't list macOS

```bash
sudo os-prober                                   # should print the macOS EFI path
echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub
sudo update-grub
```

Booting macOS from GRUB's entry is hit-or-miss on some models — the
Option-key picker (or OpenCore's menu, where present) is the reliable path.

## macOS partition not visible from Ubuntu

APFS is read-only third-party territory on Linux (`apfs-linux` drivers are
experimental). Don't write to the macOS container from Linux; exchange files
via a shared exFAT partition/USB or the network instead.

## Clocks wrong after switching OSes

Shouldn't happen in this pair — macOS and Linux both keep the hardware clock
in UTC. If you see skew, check that nothing set Linux to local time:
`timedatectl` should show `RTC in local TZ: no`.

## Installer can't see the free space

Confirm the space is truly unallocated (`diskutil list` in macOS shows a gap,
not a volume). If you created a placeholder volume instead of shrinking the
container, delete it: the space must be outside any APFS container for the
Ubuntu installer to claim it.
