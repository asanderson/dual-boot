# dual-boot

Dual boot installer for multiple hardware devices and operating systems:
repeatable instructions, configuration, and scripts for adding a Linux boot
option to machines that ship with another OS preinstalled.

The repo is organized as **common OS-pair runbooks** plus a **thin
device-specific overlay** per machine:

```
common/
  lib/common.sh          Shared bash helpers (prompts, apt, logging)
  windows-to-ubuntu/     Pair-generic runbook + tooling:
    docs/                  Steps 1–4: Windows prep → install → post-install
                           → rollback, plus troubleshooting
    scripts/20-kernel.sh   Release checks, kernel security updates, 7.0+ check
    windows/rollback-ubuntu.ps1   Confirmation-gated Ubuntu removal
devices/
  <device>/              Device page: hardware table, BIOS keys, quirks,
    docs/ scripts/ config/  device driver guide, research notes, pins
test/  .github/          Container test harness + CI
```

## Supported configurations

| Hardware | Factory OS | Added OS | Start here |
|---|---|---|---|
| MSI Raider 18 HX AI A2XWJG-069US (Core Ultra 9 285HX · RTX 5090 Laptop GPU · 64GB · 2TB NVMe) | Windows 11 Pro | Ubuntu 26.04 LTS (kernel 7.0) | [device page](devices/msi-raider-18-hx-ai/README.md) |

**Windows is preserved by design.** The factory Windows installation is never
modified: no file in `C:\` is touched, Windows Boot Manager is never replaced
(GRUB installs alongside it), and every Windows-side prep setting is
reversible. Step 1.0 captures a full system image before anything changes,
and [the rollback runbook](common/windows-to-ubuntu/docs/04-rollback.md)
(with `common/windows-to-ubuntu/windows/rollback-ubuntu.ps1`) removes Ubuntu
and returns the machine to its original preconfigured state.

## The path

1. Open your **device page** under [`devices/`](devices) — hardware facts,
   BIOS keys, quirks.
2. Follow the **common runbook**:
   [Windows prep](common/windows-to-ubuntu/docs/01-windows-prep.md) →
   [Ubuntu install](common/windows-to-ubuntu/docs/02-ubuntu-install.md) →
   [post-install](common/windows-to-ubuntu/docs/03-post-install.md) (device
   driver step comes from your device page) —
   [troubleshooting](common/windows-to-ubuntu/docs/troubleshooting.md) and
   [rollback](common/windows-to-ubuntu/docs/04-rollback.md) as needed.

Quick start on the freshly installed Ubuntu (MSI Raider 18 example):

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/asanderson/dual-boot.git ~/dual-boot
cd ~/dual-boot
chmod +x common/windows-to-ubuntu/scripts/*.sh devices/*/scripts/*.sh

./devices/msi-raider-18-hx-ai/scripts/10-nvidia-driver.sh   # driver + MOK, then reboot
./common/windows-to-ubuntu/scripts/20-kernel.sh             # releases, patches, 7.0+ check
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
script. Run locally with Docker: `./test/container-test.sh`.

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
