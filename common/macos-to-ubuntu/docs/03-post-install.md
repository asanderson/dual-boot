# Step 3 — Post-install: device setup and kernel check

You're booted into Ubuntu with this repo cloned at `~/dual-boot`.

```bash
cd ~/dual-boot
./devices/<your-device>/scripts/...   # device hardware setup (see your device page)
./common/ubuntu/scripts/20-kernel.sh  # releases, kernel security updates, version check
```

## 3.1 Device hardware setup — see your device page

Mac-specific hardware (Wi-Fi firmware, fan control, input devices, Touch
Bar) is handled by your device page's script and notes. For the
**MacBook Pro (15-inch, 2017)** that is
[`devices/macbook-pro-14-3`](../../../devices/macbook-pro-14-3/README.md).

## 3.2 Kernel — `common/ubuntu/scripts/20-kernel.sh`

Shared with every Ubuntu-target device in this repo. Interactive runs first
check for newer Ubuntu and kernel releases and prompt to install them;
unattended runs (`DEV_SETUP_ASSUME_YES=1`) opt in with `--check-releases`.
It also offers unattended security upgrades and the HWE/mainline kernel
options. Full behavior:
[windows-to-ubuntu post-install §3.2](../../windows-to-ubuntu/docs/03-post-install.md)
(the kernel step is identical for both pairs).

## 3.3 Development environment (separate repo)

The interactive development-tools installer (Git, Claude Code, Docker, JDK,
Maven, C/C++, Go, Rust, Elastic Stack, Ollama) lives in its own repository —
`asanderson/dev-setup` — and layers on top of a machine this runbook has
finished with.

Anything misbehaving → [troubleshooting](troubleshooting.md).
