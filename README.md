# dual-boot

Dual boot installer for multiple hardware devices and operating systems:
repeatable instructions, configuration, and scripts for adding a Linux boot
option to machines that ship with another OS preinstalled.

The repo is organized as **common OS-pair runbooks** plus a **thin
device-specific overlay** per machine:

```
common/
  lib/common.sh          Shared bash helpers (prompts, apt, logging)
  ubuntu/                Target-OS commons shared by every Ubuntu pair:
    scripts/20-kernel.sh   Release checks, kernel security updates, 7.0+ check
  windows-to-ubuntu/     Pair runbook (steps 1–4 + troubleshooting) and
    docs/ windows/         the Windows-side rollback script
  macos-to-ubuntu/       Pair runbook for Intel Macs (steps 1–4 +
    docs/                  troubleshooting; APFS resize, Option-boot, rollback)
devices/
  <device>/              Device page: hardware table, boot keys, quirks,
    docs/ scripts/ config/  device guides (drivers, OS upgrades), pins
test/  .github/          Container test harness + CI
```

## Supported configurations

| Hardware | Factory OS | Added OS | Start here |
|---|---|---|---|
| MSI Raider 18 HX AI A2XWJG-069US (Core Ultra 9 285HX · RTX 5090 Laptop GPU · 64GB · 2TB NVMe) | Windows 11 Pro | Ubuntu 26.04 LTS (kernel 7.0) | [device page](devices/msi-raider-18-hx-ai/README.md) |
| MacBook Pro 15" 2017, MacBookPro14,3 (i7-7700HQ · Radeon Pro 555/560 · 16GB) | macOS 13.7.8 Ventura → **Sequoia via OCLP** | Ubuntu 26.04 LTS (kernel 7.0) | [device page](devices/macbook-pro-14-3/README.md) |

**The factory OS is preserved by design.** No file inside the preinstalled
system is touched, its boot manager is never replaced (GRUB installs
alongside), and every prep-time setting is reversible. Each pair runbook's
Step 1.0 captures a full backup (Windows system image / Time Machine) before
anything changes, and each ships a rollback runbook that returns the machine
to its original preconfigured state
([Windows](common/windows-to-ubuntu/docs/04-rollback.md) ·
[macOS](common/macos-to-ubuntu/docs/04-rollback.md)).

## The path

1. Open your **device page** under [`devices/`](devices) — hardware facts,
   BIOS keys, quirks.
2. Follow your **pair runbook** (prep → install → post-install, with
   troubleshooting and rollback alongside):
   [Windows → Ubuntu](common/windows-to-ubuntu/docs/01-windows-prep.md) ·
   [macOS → Ubuntu](common/macos-to-ubuntu/docs/01-macos-prep.md).
   The device-specific steps (drivers, OS upgrades such as OCLP) come from
   your device page.

Quick start on the freshly installed Ubuntu (MSI Raider 18 example):

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/asanderson/dual-boot.git ~/dual-boot
cd ~/dual-boot
chmod +x common/*/scripts/*.sh devices/*/scripts/*.sh

./devices/msi-raider-18-hx-ai/scripts/10-nvidia-driver.sh   # driver + MOK, then reboot
./common/ubuntu/scripts/20-kernel.sh             # releases, patches, 7.0+ check
                                                            #   (unattended: --check-releases)
```

Development-environment tooling (Git, Docker, JDKs, language toolchains,
Elastic, Ollama, …) is intentionally out of scope here — it lives in a
separate dev-environment repository and layers on top of a machine this repo
has finished with.

## Testing

Every PR runs `.github/workflows/container-test.yml`: shellcheck across the
shell scripts, a PowerShell parse of the rollback script, and a fresh Ubuntu
26.04 container run asserting both unattended modes of `20-kernel.sh`
(release checks skipped without `--check-releases`; Ubuntu release check +
kernel patching with it) and the graceful no-GPU failure of the device driver
script and the Mac device script (wrong-hardware refusal). Run locally
with Docker: `./test/container-test.sh`.

## Adding a configuration

Add a directory under `devices/<device-slug>/` with the same shape as the
existing one: a README (hardware table, BIOS keys with an honest note about
how they were verified, quirks), device-specific scripts and docs, and pins
in `config/versions.env` for anything fetched as an artifact. Device pages
document only the **deltas** — link into the common runbook rather than
copying it. Reusable pieces (an OS-pair runbook for a new pair, a GPU-family
driver script) graduate into `common/` when a second consumer appears. If a
device gains a second OS pair, nest per-pair subdirectories under that device
then — not before.

## License

[Apache 2.0](LICENSE)
