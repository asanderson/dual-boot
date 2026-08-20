# The installation plan — `common/scripts/00-install-plan.sh`

Every device flow starts the same way: decide the **common installation
constraints** once, up front, then let the device scripts honor them. The
plan script asks (or takes flags for) exactly those decisions:

| Constraint | Interactive | Unattended (`DEV_SETUP_ASSUME_YES=1`) |
|---|---|---|
| Which operating systems | one prompt per catalog OS | `--os LIST` (else the default set) |
| Clean install vs upgrade, per OS | prompt, **defaults to upgrade** | `--mode OS=install\|upgrade` (else upgrade — a destructive mode is never an unattended default) |
| Back up existing boot devices/partitions first | prompt, defaults to **yes** | `--backup` / `--no-backup` (else yes — the backup only writes new files) |
| Boot partition size | editable, default 2 GiB | `--boot-size GIB` |
| Target disk | device default | `--disk DEV` |

The decisions are written to a plan file (default `~/.dual-boot-plan.env`,
`--plan-file` to change) that the device scripts read; explicit flags on a
device script always override the plan. Release checks for every chosen OS
run first, under the repo contract: interactive runs always check,
unattended runs only with `--check-releases`, and nothing is ever installed,
flashed, or wiped by the plan script itself — destructive steps live in
device scripts behind their own gate (`--destructive` unattended; a
confirmed prompt interactively).

The same flag vocabulary is shared by every script in the repo
(`common/lib/args.sh`); each script's `--help` lists the subset it accepts.

## The boot-state backup

When selected, the plan backs up — non-destructively, into
`~/dual-boot-backups/boot-backup-<stamp>/` — the GPT partition table of the
target disk (`sgdisk --backup`), a full block-device inventory (`lsblk`),
and tarballs of the mounted `/boot` and `/boot/efi`. Copy that directory
**off the machine** before any destructive step. Full-disk image backups
(Windows system image, Time Machine) remain Step 1.0 of the pair runbooks —
this is the boot-specific safety net, not a replacement.

## The OS catalog

Pins live in [`common/config/os-catalog.env`](../config/os-catalog.env);
per-OS behavior in `common/lib/oses.sh`. Release checks report drift against
the pins; media handling varies honestly by vendor:

| OS | Release check | Install media | Verification |
|---|---|---|---|
| **Ubuntu** (Raider/MacBook pair target) | via `20-kernel.sh` on the installed system | pair runbooks | (runbook) |
| **Qubes OS** | official ISO mirror listing | fetched by the Librem script | detached PGP signature, release key chained to the pinned Qubes Master Signing Key |
| **PureOS** | image-set listing on Purism's storage | fetched by the Librem script | pinned SHA256 + Purism's published checksum file (Purism ships no GPG signatures) |
| **Rocky Linux** | release directory listing on `download.rockylinux.org` | fetchable (`os_fetch_verify_rocky`) | GPG-signed CHECKSUM file against the pinned Rocky key |
| **RHEL** | release detection only | **requires a Red Hat login** — customer subscription or the no-cost [Developer Subscription](https://developers.redhat.com/products/rhel/download); no unauthenticated official channel exists | via the authenticated portal |
| **Windows 11 Pro / Home** | Microsoft's release-information page (silicon-targeted versions like 26H1 are flagged, not trusted) | **manual**: [microsoft.com/software-download/windows11](https://www.microsoft.com/software-download/windows11) generates time-limited (24h) links — one **multi-edition ISO** covers Pro and Home (edition chosen by product key or `EI.cfg`) | SHA256 hashes published on the download page — compare after downloading |

Windows notes: Pro and Home are separate catalog entries so a plan states
which edition is intended, but they share media; a Home→Pro change is a
license/key change, not different install media. Windows installs are
UEFI/GPT (ESP-based — no separate `/boot` concept), so the boot-size
constraint applies to the ESP on Windows-bearing layouts.

RHEL notes: minor updates are `dnf`; supported major upgrades use `leapp`
(consecutive majors only, e.g. 9.8 → 10.2) — those are the "upgrade" mode.
Rocky supports minor-to-minor updates in place; major-version upgrades are
officially reinstalls ("install" mode).

Boot-size guidance behind the 2 GiB default: EL10 (RHEL 10 / Rocky 10) docs
recommend **/boot ≥ 2 GiB** as a standard partition (not LVM) and a
**600 MiB ESP**; Microsoft requires an ESP of only ≥ 200–300 MB (plus a
16 MB MSR and a ≥ 300 MB WinRE partition), so the EL-sized ESP covers
Windows-bearing layouts too; PureBoot devices use the shared-`/boot` layout
from the Librem runbook. Raise `--boot-size` if extra firmware/initramfs
bloat is expected.

## Adding an OS to the catalog

Add its pins to `os-catalog.env`, an `os_release_check_<os>` (and, if an
unauthenticated official channel exists, `os_fetch_verify_<os>`) to
`oses.sh`, a row to the table above, and a container-test assertion. Keys
use hyphens; function suffixes use underscores.
