# dual-boot

Dual boot installer for multiple hardware devices and operating systems:
repeatable instructions, configuration, and scripts for adding a Linux boot
option to machines that ship with another OS preinstalled.

## Supported configurations

| Hardware | Factory OS | Added OS | Runbook |
|---|---|---|---|
| MSI Raider 18 HX AI A2XWJG-069US (Core Ultra 9 285HX · RTX 5090 Laptop GPU · 64GB DDR5-6400 · 2TB NVMe) | Windows 11 Pro | Ubuntu 26.04 LTS (kernel 7.0) | [docs/01-windows-prep.md](docs/01-windows-prep.md) |

## The path (MSI Raider 18 / Ubuntu 26.04)

| Step | Where | Doc |
|---|---|---|
| 1. Prepare Windows (BitLocker, fast startup, shrink disk, USB, BIOS keys) | Windows | [docs/01-windows-prep.md](docs/01-windows-prep.md) |
| 2. Install Ubuntu 26.04 alongside Windows | Ubuntu installer | [docs/02-ubuntu-install.md](docs/02-ubuntu-install.md) |
| 3. NVIDIA driver → kernel check | Ubuntu | [docs/03-post-install.md](docs/03-post-install.md) |
| Anything broken | — | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Verified facts + sources behind this runbook | — | [docs/research-notes.md](docs/research-notes.md) |

Key facts (verified against primary sources — see the research notes):

- **Ubuntu 26.04 LTS ships Linux kernel 7.0 as its stock GA kernel** (7.0 is
  the upstream release that followed 6.19), so no custom kernel work is
  needed; `scripts/20-kernel.sh` verifies this and offers the HWE stack.
- The **RTX 5090 Laptop GPU (Blackwell) requires NVIDIA's open GPU kernel
  modules** (the proprietary flavor doesn't support this generation);
  `scripts/10-nvidia-driver.sh` installs the recommended `-open` driver with
  Secure Boot/MOK enrollment handled.

## Quick start (on the freshly installed Ubuntu)

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/asanderson/dual-boot.git ~/dual-boot
cd ~/dual-boot
chmod +x scripts/*.sh

./scripts/10-nvidia-driver.sh   # NVIDIA driver + MOK guidance, then reboot
./scripts/20-kernel.sh          # verify kernel 7.0+, optional newer kernels
```

Development-environment tooling (Git, Docker, JDKs, language toolchains,
Elastic, Ollama, …) is intentionally out of scope here — it lives in a
separate dev-environment repository and layers on top of a machine this repo
has finished with.

## Repo layout

```
docs/                    Step-by-step runbook (Windows prep → install → post-install)
scripts/
  10-nvidia-driver.sh    RTX 5090 Laptop GPU driver (open modules, Secure Boot aware)
  20-kernel.sh           Kernel 7.0+ verification, HWE / mainline options
  lib/common.sh          Shared helpers (prompts, apt, logging)
config/
  versions.env           Pinned versions (NVIDIA driver branch fallback)
```

## Adding a configuration

Each supported machine/OS pair should contribute the same shape: a numbered
docs runbook (prep the factory OS → install → post-install), scripts that are
idempotent and safe to re-run, and pins in `config/versions.env` for anything
fetched as an artifact. Model-specific firmware details (BIOS hotkeys, storage
mode quirks) belong in the runbook with an honest note about how they were
verified.

## License

[Apache 2.0](LICENSE)
