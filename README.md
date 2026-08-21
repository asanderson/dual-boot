# dual-boot

Dual boot installer for multiple hardware devices and operating systems:
repeatable instructions, configuration, and scripts for adding a Linux boot
option to machines that ship with another OS preinstalled.

The repo is organized as **common OS-pair runbooks** plus a **thin
device-specific overlay** per machine:

```
common/
  lib/                   Shared bash: helpers (common.sh), the flag/prompt
                           contract (args.sh), OS catalog behavior (oses.sh),
                           and the constraint planner (plan.sh)
  config/os-catalog.env  The OS catalog + latest-release pins (Ubuntu, Qubes,
                           PureOS, Rocky, RHEL, Windows 11 Pro/Home)
  scripts/00-install-plan.sh  Common entry point: decide which OSes,
                           install-vs-upgrade, backups, boot size — once
  docs/install-plan.md   The plan layer + per-OS media/verification table
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
| Purism Librem 14 v1 (i7-10710U · 64GB DDR4 · 2TB NVMe · PureBoot Anti-Interdiction) | PureOS (**wiped** — see below) | **Qubes OS 4.3.1 + PureOS 11 "Crimson"** (clean dual install) | [device page](devices/librem-14-v1/README.md) |

**The factory OS is preserved by design** — on every device except where its
page says otherwise. No file inside the preinstalled system is touched, its
boot manager is never replaced (GRUB installs alongside), and every
prep-time setting is reversible. Each pair runbook's Step 1.0 captures a
full backup (Windows system image / Time Machine) before anything changes,
and each ships a rollback runbook that returns the machine to its original
preconfigured state
([Windows](common/windows-to-ubuntu/docs/04-rollback.md) ·
[macOS](common/macos-to-ubuntu/docs/04-rollback.md)).

**The one exception is the Librem 14**: its documented flow is a
**destructive clean dual install** of Qubes OS + PureOS that replaces the
factory PureOS. Interactive runs confirm the wipe (defaulting to yes, per
that device's design); unattended runs never touch the disk without the
explicit `--destructive` flag. "Rollback" there means reinstalling PureOS
from a live USB — the device page says so up front.

## The path

1. Run the **common install plan** — it decides the shared constraints once
   (which OSes from the [catalog](common/config/os-catalog.env), clean
   install vs upgrade per OS, boot-state backup, boot partition size), runs
   the release checks, and writes a plan the device scripts honor
   ([details](common/docs/install-plan.md)):

   ```bash
   ./common/scripts/00-install-plan.sh          # unattended: --os,--mode,--backup,...
   ```

2. Open your **device page** under [`devices/`](devices) — hardware facts,
   BIOS keys, quirks.
3. Follow your **pair runbook** (prep → install → post-install, with
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

./devices/msi-raider-18-hx-ai/scripts/10-nvidia-driver.sh   # firmware/driver prechecks,
                                                            #   driver + MOK, then reboot
./common/ubuntu/scripts/20-kernel.sh             # releases, patches, 7.0+ check
                                                            #   (unattended: --check-releases)
```

Development-environment tooling (Git, Docker, JDKs, language toolchains,
Elastic, Ollama, …) is intentionally out of scope here — it lives in a
separate dev-environment repository and layers on top of a machine this repo
has finished with.

## Documentation map

**Plan first** — the decisions every device flow shares:

| Doc | What's inside |
|---|---|
| [The install plan](common/docs/install-plan.md) | The shared constraint layer: the OS catalog with its per-OS media/verification table, install-vs-upgrade semantics, the boot-state backup, the Secure Boot + disk-encryption decisions (with the per-device honoring table), Wi-Fi settings, boot-size guidance, and the flag vocabulary every script accepts |

**Pair runbooks** — the common path from factory OS to dual boot. Read the
steps in order; troubleshooting and rollback sit alongside:

| Step | Windows → Ubuntu | macOS (Intel) → Ubuntu |
|---|---|---|
| 1. Prepare the factory OS | [01-windows-prep](common/windows-to-ubuntu/docs/01-windows-prep.md) | [01-macos-prep](common/macos-to-ubuntu/docs/01-macos-prep.md) |
| 2. Install Ubuntu | [02-ubuntu-install](common/windows-to-ubuntu/docs/02-ubuntu-install.md) | [02-ubuntu-install](common/macos-to-ubuntu/docs/02-ubuntu-install.md) |
| 3. Post-install | [03-post-install](common/windows-to-ubuntu/docs/03-post-install.md) | [03-post-install](common/macos-to-ubuntu/docs/03-post-install.md) |
| 4. Rollback (undo everything) | [04-rollback](common/windows-to-ubuntu/docs/04-rollback.md) | [04-rollback](common/macos-to-ubuntu/docs/04-rollback.md) |
| Troubleshooting | [troubleshooting](common/windows-to-ubuntu/docs/troubleshooting.md) | [troubleshooting](common/macos-to-ubuntu/docs/troubleshooting.md) |

**Device pages and deep dives** — hardware facts, boot keys, quirks, then
the guides specific to that machine:

| Device | Start here | Deep dives |
|---|---|---|
| MSI Raider 18 HX AI | [device page](devices/msi-raider-18-hx-ai/README.md) | [NVIDIA driver (Blackwell, MOK/Secure Boot)](devices/msi-raider-18-hx-ai/docs/nvidia-driver.md) · [research notes](devices/msi-raider-18-hx-ai/docs/research-notes.md) |
| MacBook Pro 15" 2017 (14,3) | [device page](devices/macbook-pro-14-3/README.md) | [macOS Sequoia via OpenCore Legacy Patcher](devices/macbook-pro-14-3/docs/macos-sequoia-oclp.md) |
| Purism Librem 14 v1 | [device page](devices/librem-14-v1/README.md) | [Qubes OS + PureOS clean dual install](devices/librem-14-v1/docs/qubes-pureos-dual-install.md) |

## Testing

Every PR runs `.github/workflows/container-test.yml`: shellcheck across the
shell scripts, a PowerShell parse of the rollback script, and a fresh Ubuntu
26.04 container run asserting both unattended modes of `20-kernel.sh`
(release checks skipped without `--check-releases`; Ubuntu release check +
kernel patching with it) and the graceful no-GPU failure of the device driver
script, the Mac device scripts (wrong-hardware / wrong-OS refusal), the
Librem 14 dual-install script (wrong-hardware refusal before anything
destructive, with `--destructive` unable to bypass that gate), and the
common install-plan script (flags/defaults land in the plan, destructive is
never an unattended default, unknown OSes rejected, Rocky/Windows release
checks wired). A
separate **GPU-path job** stubs `lspci` as the MSI Raider's RTX 5090 so the
driver script's GPU-present path runs for real — actual driver package
install plus all three driver-selection branches — validating selection and
install machinery (module loading still needs the hardware). Run locally with
Docker: `./test/container-test.sh` and `./test/container-test.sh --gpu-path`.

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
