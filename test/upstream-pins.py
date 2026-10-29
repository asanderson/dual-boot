#!/usr/bin/env python3
"""Check the OS/firmware pins against upstream; optionally bump them.

Usage:
  python3 test/upstream-pins.py                 report (table on stdout)
  python3 test/upstream-pins.py --apply         rewrite the pin files, sbom.cdx.json
                                                and SBOM.md
  python3 test/upstream-pins.py --summary FILE  also write a Markdown summary (the
                                                nightly PR body)
  python3 test/upstream-pins.py --github-output write changed=/manual= to $GITHUB_OUTPUT
  python3 test/upstream-pins.py --selftest      parser checks against embedded
                                                samples, no network

The nightly upstream-pins workflow runs this and opens a pull request when a
pin moved. Each value is resolved from the same live source the runbook
scripts' --check-releases logic reads (common/lib/oses.sh and the device
scripts), so a bump here is what those checks would report as drift:

  common/config/os-catalog.env
    QUBES_VERSION        Qubes ISO mirror listing (patch releases auto-bump; a
                         new 4.x line also moves the release key and dom0 repo,
                         so that is report-only)
    QUBES_DOM0_KERNEL    r4.3 dom0 rpm listing (default kernel track)
    PUREOS_RELEASE_DIR   newest image set under the crimson images root; moves
                         PUREOS_IMAGE, PUREOS_DL_BASE_URL and PUREOS_ISO_SHA256
                         (from Purism's published checksums file) with it
    PUREOS_KERNEL        crimson linux-signed pool listing (PUREOS_KERNEL_SERIES)
    ROCKY_VERSION        Rocky ISO root listing (same major only; a new major
                         needs a new GPG key, so that is report-only)
    ROCKY_KERNEL         live 10.x BaseOS kernel-core listing
    RHEL_VERSION/KERNEL  Red Hat's public release-dates article
    UBUNTU_VERSION       REPORT ONLY (changelogs.ubuntu.com meta-release-lts):
                         the LTS target is a runbook decision
    WIN11_VERSION        REPORT ONLY: release-health lists silicon-targeted
                         versions that never reach the download page
  devices/macbook-pro-14-3/config/versions.env
    OCLP_VERSION         dortania/OpenCore-Legacy-Patcher GitHub releases
  devices/librem-14-v1/config/versions.env
    PUREBOOT_VERSION     PUREBOOT_VERSION_14 inside Purism's coreboot_util.sh
    (LIBREM_EC_VERSION has no machine-readable source; not checked)
  devices/msi-raider-18-hx-ai/config/versions.env
    NVIDIA_DRIVER_BRANCH REPORT ONLY (newest nvidia-driver-NNN-open in the
                         Ubuntu archive for UBUNTU_VERSION, release + updates
                         pockets, which is where 10-nvidia-driver.sh installs
                         it from): a branch change is a hardware-support
                         decision

A resolver that fails (network, format change) is reported and skipped; it
never blocks the other pins. Exit status is 0 unless --strict is given and a
resolver failed.
"""
import argparse
import gzip
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "common" / "config" / "os-catalog.env"
MAC_ENV = ROOT / "devices" / "macbook-pro-14-3" / "config" / "versions.env"
LIBREM_ENV = ROOT / "devices" / "librem-14-v1" / "config" / "versions.env"
RAIDER_ENV = ROOT / "devices" / "msi-raider-18-hx-ai" / "config" / "versions.env"
BOM = ROOT / "sbom.cdx.json"
SBOM_MD = ROOT / "test" / "sbom-md.py"

USER_AGENT = "dual-boot upstream-pins (+https://github.com/asanderson/dual-boot)"
TIMEOUT = 30


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def fetch(url: str) -> str:
    headers = {"User-Agent": USER_AGENT, "Accept": "*/*"}
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return resp.read().decode("utf-8", "replace")


def fetch_gzip_text(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return gzip.decompress(resp.read()).decode("utf-8", "replace")


def vtuple(version: str):
    """Numeric sort key for version-ish strings (prefixes/suffixes ignored)."""
    return tuple(int(x) for x in re.findall(r"\d+", version))


def newest(values):
    values = list(values)
    return max(values, key=vtuple) if values else None


def read_env(path: pathlib.Path) -> dict:
    pins = {}
    for line in path.read_text().splitlines():
        m = re.match(r'^([A-Z0-9_]+)="([^"]*)"\s*$', line)
        if m:
            pins[m.group(1)] = m.group(2)
    return pins


def write_env(path: pathlib.Path, updates: dict) -> None:
    text = path.read_text()
    for key, value in updates.items():
        pattern = re.compile(rf'^({re.escape(key)}=")[^"]*(")', re.M)
        text, n = pattern.subn(rf"\g<1>{value}\g<2>", text, count=1)
        if n != 1:
            raise SystemExit(f"{path.relative_to(ROOT)}: pin {key} not found")
    path.write_text(text)


def github_latest_tag(repo: str) -> str:
    return json.loads(fetch(f"https://api.github.com/repos/{repo}/releases/latest"))["tag_name"]


# --------------------------------------------------------------------------- #
# parsers (pure; mirror the grep/sed in common/lib/oses.sh; --selftest covers them)
# --------------------------------------------------------------------------- #
def parse_qubes_iso_listing(html: str) -> str:
    isos = re.findall(r"Qubes-R(\d+\.\d+(?:\.\d+)?)-x86_64\.iso", html)
    return newest(set(isos))


def parse_qubes_dom0_kernel(html: str) -> str:
    # 'kernel-<ver>-<rel>.qubes.fcNN' — not kernel-latest-* and not the VM kernels.
    kernels = re.findall(r"(?<![\w-])kernel-(\d+\.\d+\.\d+-\d+\.qubes\.fc\d+)", html)
    return newest(set(kernels))


def parse_pureos_release_dirs(html: str) -> str:
    return newest(set(re.findall(r"20\d{2}\.\d{2}", html)))


def parse_pureos_image(html: str, pureos_version: str) -> str:
    isos = re.findall(rf"pureos-{re.escape(pureos_version)}-gnome-live-\d{{8}}_amd64\.iso", html)
    return newest(set(isos))


def parse_sha256_file(text: str) -> str:
    m = re.search(r"^([0-9a-f]{64})", text, re.M)
    if not m:
        raise ValueError("no sha256 in checksum file")
    return m.group(1)


def parse_pureos_kernel(html: str, series: str) -> str:
    pat = rf"linux-image-{re.escape(series)}-\d+-amd64_([0-9][^_\"<\s]*)_amd64\.deb"
    return newest(set(re.findall(pat, html)))


def parse_rocky_release_dirs(html: str) -> str:
    return newest(set(re.findall(r'href="(\d+(?:\.\d+)?)/"', html)))


def parse_rocky_kernel(html: str, major: str) -> str:
    pat = rf'kernel-core-(\d[^"<\s]*\.el{re.escape(major)}[_0-9]*)\.x86_64\.rpm'
    return newest(set(re.findall(pat, html)))


def parse_rhel_release(html: str) -> str:
    return newest(set(re.findall(r"(?:Red Hat Enterprise Linux|RHEL) (\d+\.\d+)", html)))


def parse_rhel_kernel(html: str) -> str:
    return newest(set(re.findall(r"\d+\.\d+\.\d+-\d+(?:\.\d+)*\.el\d+(?:_\d+)?", html)))


def parse_win11_release(html: str) -> str:
    return newest(set(re.findall(r"Version (\d{2}H\d)", html)))


def parse_ubuntu_meta_release_lts(text: str) -> str:
    # 'Version: 26.04.1 LTS' once the point release is out; the pin is the series.
    versions = re.findall(r"^Version: (\d+\.\d+)(?:\.\d+)?(?: LTS)?\s*$", text, re.M)
    return newest(set(versions))


def parse_ubuntu_codename(text: str, series: str) -> str:
    """Archive codename ('resolute') of an LTS series ('26.04') from meta-release-lts."""
    for stanza in re.split(r"\n\s*\n", text):
        dist = re.search(r"^Dist: (\S+)", stanza, re.M)
        version = re.search(r"^Version: (\d+\.\d+)(?:\.\d+)?(?: LTS)?\s*$", stanza, re.M)
        if dist and version and version.group(1) == series:
            return dist.group(1)
    raise ValueError(f"Ubuntu {series} is not in meta-release-lts")


def parse_ubuntu_nvidia_branches(packages: str) -> set:
    """Branches with an nvidia-driver-NNN-open metapackage in an apt Packages index."""
    return set(re.findall(r"^Package: nvidia-driver-(\d+)-open\s*$", packages, re.M))


def parse_pureboot_util(text: str) -> str:
    m = re.search(r'^PUREBOOT_VERSION_14="(.*)"', text, re.M)
    if not m:
        raise ValueError("PUREBOOT_VERSION_14 not in coreboot_util.sh")
    return m.group(1)


# --------------------------------------------------------------------------- #
# resolvers: each returns (latest_value, extra_env_updates, manual_reason_or_None)
# manual_reason turns an otherwise-auto pin into a report-only row for this run.
# --------------------------------------------------------------------------- #
def resolve_qubes_version(cat):
    latest = parse_qubes_iso_listing(fetch(f"{cat['QUBES_ISO_DIR_URL']}/"))
    if latest and latest.rsplit(".", 1)[0] != cat["QUBES_VERSION"].rsplit(".", 1)[0]:
        return latest, {}, "new Qubes line: QUBES_RELEASE_KEY_URL and QUBES_DOM0_RPM_URL change with it"
    return latest, {}, None


def resolve_qubes_kernel(cat):
    return parse_qubes_dom0_kernel(fetch(cat["QUBES_DOM0_RPM_URL"])), {}, None


def resolve_pureos_release(cat):
    root = cat["PUREOS_IMAGES_ROOT_URL"]
    release = parse_pureos_release_dirs(fetch(f"{root}/"))
    if release == cat["PUREOS_RELEASE_DIR"]:
        return release, {}, None
    base = f"{root}/{release}/gnome"
    image = parse_pureos_image(fetch(f"{base}/"), cat["PUREOS_VERSION"])
    if not image:
        raise ValueError(f"no gnome live image listed under {base}/")
    sha = parse_sha256_file(fetch(f"{base}/{image[:-4]}.checksums_sha256.txt"))
    return release, {"PUREOS_IMAGE": image, "PUREOS_DL_BASE_URL": base, "PUREOS_ISO_SHA256": sha}, None


def resolve_pureos_kernel(cat):
    return parse_pureos_kernel(fetch(cat["PUREOS_KERNEL_POOL_URL"]), cat["PUREOS_KERNEL_SERIES"]), {}, None


def resolve_rocky_version(cat):
    latest = parse_rocky_release_dirs(fetch(f"{cat['ROCKY_ISO_ROOT_URL']}/"))
    if latest and latest.split(".")[0] != cat["ROCKY_MAJOR"]:
        return latest, {}, "new Rocky major: GPG key, ISO root, kernel listing and /boot guidance change with it"
    return latest, {}, None


def resolve_rocky_kernel(cat):
    return parse_rocky_kernel(fetch(cat["ROCKY_KERNEL_PKGS_URL"]), cat["ROCKY_MAJOR"]), {}, None


_rhel_page = {}


def _rhel(cat):
    if "page" not in _rhel_page:
        _rhel_page["page"] = fetch(cat["RHEL_RELEASES_URL"])
    return _rhel_page["page"]


def resolve_rhel_version(cat):
    return parse_rhel_release(_rhel(cat)), {}, None


def resolve_rhel_kernel(cat):
    return parse_rhel_kernel(_rhel(cat)), {}, None


def resolve_ubuntu_version(cat):
    return parse_ubuntu_meta_release_lts(fetch("https://changelogs.ubuntu.com/meta-release-lts")), {}, None


def resolve_win11_version(cat):
    return parse_win11_release(fetch(cat["WIN11_RELEASE_INFO_URL"])), {}, None


def resolve_oclp(cat):
    return github_latest_tag("dortania/OpenCore-Legacy-Patcher"), {}, None


def resolve_pureboot(cat):
    librem = read_env(LIBREM_ENV)
    return parse_pureboot_util(fetch(librem["PUREBOOT_UTIL_URL"])), {}, None


def resolve_nvidia_branch(cat):
    # nvidia.com's Unix driver page is not machine-readable any more; what the
    # runbook installs is apt's nvidia-driver-NNN-open for the pinned Ubuntu
    # series, so the newest branch in that archive (release + updates) is the
    # upstream that matters.
    codename = parse_ubuntu_codename(fetch("https://changelogs.ubuntu.com/meta-release-lts"), cat["UBUNTU_VERSION"])
    branches = set()
    for pocket in (codename, f"{codename}-updates"):
        branches |= parse_ubuntu_nvidia_branches(fetch_gzip_text(
            f"https://archive.ubuntu.com/ubuntu/dists/{pocket}/restricted/binary-amd64/Packages.gz"))
    return newest(branches), {}, None


# file, key, resolver, apply (False = report only), one-line source description
PINS = [
    (CATALOG, "QUBES_VERSION", resolve_qubes_version, True, "Qubes ISO mirror listing"),
    (CATALOG, "QUBES_DOM0_KERNEL", resolve_qubes_kernel, True, "r4.3 dom0 rpm listing"),
    (CATALOG, "PUREOS_RELEASE_DIR", resolve_pureos_release, True, "PureOS crimson images root (+ image, base URL, sha256)"),
    (CATALOG, "PUREOS_KERNEL", resolve_pureos_kernel, True, "PureOS linux-signed pool listing"),
    (CATALOG, "ROCKY_VERSION", resolve_rocky_version, True, "Rocky ISO root listing"),
    (CATALOG, "ROCKY_KERNEL", resolve_rocky_kernel, True, "Rocky BaseOS kernel-core listing"),
    (CATALOG, "RHEL_VERSION", resolve_rhel_version, True, "Red Hat release-dates article"),
    (CATALOG, "RHEL_KERNEL", resolve_rhel_kernel, True, "Red Hat release-dates article"),
    (CATALOG, "UBUNTU_VERSION", resolve_ubuntu_version, False, "changelogs.ubuntu.com meta-release-lts (manual: runbook target)"),
    (CATALOG, "WIN11_VERSION", resolve_win11_version, False, "Windows release-health page (manual: may be silicon-targeted)"),
    (MAC_ENV, "OCLP_VERSION", resolve_oclp, True, "dortania/OpenCore-Legacy-Patcher GitHub releases"),
    (LIBREM_ENV, "PUREBOOT_VERSION", resolve_pureboot, True, "Purism coreboot_util.sh PUREBOOT_VERSION_14"),
    (RAIDER_ENV, "NVIDIA_DRIVER_BRANCH", resolve_nvidia_branch, False, "Ubuntu archive nvidia-driver-NNN-open for UBUNTU_VERSION (manual: hardware-support decision)"),
]


# --------------------------------------------------------------------------- #
# SBOM sync
# --------------------------------------------------------------------------- #
def bom_component(bom: dict, name: str) -> dict:
    for c in bom["components"]:
        if c["name"] == name:
            return c
    raise SystemExit(f"sbom.cdx.json: component {name!r} not found")


def bom_replace_in_properties(comp: dict, old: str, new: str) -> None:
    for p in comp.get("properties", []):
        p["value"] = p["value"].replace(old, new)


def sync_sbom(changes: dict, extra: dict) -> None:
    """Mirror the pin bumps into sbom.cdx.json (kept alongside the pin files)."""
    bom = json.loads(BOM.read_text())
    for key, (old, new) in changes.items():
        if key == "QUBES_VERSION":
            bom_component(bom, "Qubes OS")["version"] = new
        elif key == "PUREOS_RELEASE_DIR" and "PUREOS_IMAGE" in extra:
            comp = bom_component(bom, "PureOS")
            old_image = re.sub(r"_amd64\.iso$", "", read_env(CATALOG).get("PUREOS_IMAGE", ""))  # pre-write value
            new_image = re.sub(r"_amd64\.iso$", "", extra["PUREOS_IMAGE"])
            if old_image:
                bom_replace_in_properties(comp, old_image, new_image)
        elif key == "ROCKY_VERSION":
            bom_component(bom, "Rocky Linux")["version"] = new
        elif key == "RHEL_VERSION":
            bom_component(bom, "Red Hat Enterprise Linux")["version"] = new
        elif key == "OCLP_VERSION":
            bom_component(bom, "OpenCore Legacy Patcher")["version"] = new
        elif key == "PUREBOOT_VERSION":
            bom_component(bom, "PureBoot (coreboot + Heads)")["version"] = new
        # kernels are not SBOM components (the runbooks install the distro's newest)
    bom["version"] = int(bom.get("version", 1)) + 1
    bom["metadata"]["timestamp"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    BOM.write_text(json.dumps(bom, indent=2))
    subprocess.run([sys.executable, str(SBOM_MD)], check=True)


def stale_mentions(changes: dict) -> dict:
    """Markdown files that still spell out an old value (docs to touch by hand)."""
    skip = {ROOT / "SBOM.md"}
    hits = {}
    for key, (old, _new) in changes.items():
        if len(old) < 5:
            continue
        files = sorted(str(p.relative_to(ROOT)) for p in ROOT.rglob("*.md")
                       if p not in skip and ".git" not in p.parts and old in p.read_text(errors="replace"))
        if files:
            hits[key] = files
    return hits


# --------------------------------------------------------------------------- #
# reporting
# --------------------------------------------------------------------------- #
def markdown_summary(rows, changes, manual, failures, stale) -> str:
    out = ["## Upstream pin check", "",
           "| Pin | Pinned | Upstream | Source | Result |", "|---|---|---|---|---|"]
    for key, current, latest, source, result in rows:
        out.append(f"| `{key}` | `{current}` | `{latest}` | {source} | {result} |")
    if changes:
        out += ["", "### Bumped in this change", ""]
        for key, (old, new) in changes.items():
            out.append(f"- `{key}`: `{old}` → `{new}`")
        out += ["", "`sbom.cdx.json` (document version +1) and `SBOM.md` were regenerated to match.",
                "The nightly job only runs the lint checks; the container suites run on this PR as usual."]
    if "PUREOS_RELEASE_DIR" in changes:
        out += ["", "> `PUREOS_ISO_SHA256` was taken from Purism's published `.checksums_sha256.txt` for the new",
                "> image (Purism ships no GPG signatures). Re-check it on https://pureos.net/download before merging."]
    if manual:
        out += ["", "### Needs a manual decision", ""]
        for key, current, latest, why in manual:
            out.append(f"- `{key}`: pinned `{current}`, upstream `{latest}` — {why}")
    if stale:
        out += ["", "### Old values still mentioned in docs", ""]
        for key, files in stale.items():
            out.append(f"- `{key}` ({changes[key][0]}): " + ", ".join(f"`{f}`" for f in files))
    if failures:
        out += ["", "### Could not resolve", ""]
        for key, err in failures:
            out.append(f"- `{key}`: {err}")
    return "\n".join(out) + "\n"


def selftest() -> int:
    assert parse_qubes_iso_listing('Qubes-R4.3.1-x86_64.iso Qubes-R4.3.2-x86_64.iso Qubes-R4.2.4-x86_64.iso') == "4.3.2"
    rpms = 'kernel-6.18.42-1.qubes.fc41.x86_64.rpm kernel-6.18.50-1.qubes.fc41.x86_64.rpm kernel-latest-6.19.3-1.qubes.fc41.x86_64.rpm kernel-6.18.50-1.qubes.fc41-vm'
    assert parse_qubes_dom0_kernel(rpms) == "6.18.50-1.qubes.fc41"
    assert parse_pureos_release_dirs('href="2026.05/" href="2026.11/" href="2025.12/"') == "2026.11"
    assert parse_pureos_image('pureos-11-gnome-live-20260515_amd64.iso pureos-11-gnome-live-20261101_amd64.iso', "11") == "pureos-11-gnome-live-20261101_amd64.iso"
    assert parse_sha256_file("ab" * 32 + "  pureos.iso\n") == "ab" * 32
    pool = 'linux-image-6.1.0-37-amd64_6.1.180-1_amd64.deb linux-image-6.1.0-38-amd64_6.1.182-1_amd64.deb linux-image-6.12.0-1-amd64_6.12.5-1_amd64.deb'
    assert parse_pureos_kernel(pool, "6.1.0") == "6.1.182-1"
    assert parse_rocky_release_dirs('href="9.6/" href="10.2/" href="10.3/" href="10/"') == "10.3"
    assert parse_rocky_kernel('kernel-core-6.12.0-211.47.1.el10_2.x86_64.rpm kernel-core-6.12.0-230.3.1.el10_3.x86_64.rpm', "10") == "6.12.0-230.3.1.el10_3"
    rhel = "Red Hat Enterprise Linux 10.2 kernel 6.12.0-211.7.1.el10_2 ... RHEL 10.3 6.12.0-230.7.1.el10_3 ... Red Hat Enterprise Linux 9.8"
    assert parse_rhel_release(rhel) == "10.3"
    assert parse_rhel_kernel(rhel) == "6.12.0-230.7.1.el10_3"
    assert parse_win11_release("Version 25H2 ... Version 26H1 ... Version 24H2") == "26H1"
    lts = "Dist: dapper\nVersion: 6.06 LTS\n\nDist: noble\nVersion: 24.04.5 LTS\n\nDist: resolute\nVersion: 26.04.1 LTS\n"
    assert parse_ubuntu_meta_release_lts(lts) == "26.04"
    assert parse_ubuntu_codename(lts, "26.04") == "resolute"
    assert parse_ubuntu_codename(lts, "24.04") == "noble"
    assert parse_pureboot_util('X=1\nPUREBOOT_VERSION_14="Release-30.2"\nPUREBOOT_VERSION_13="Release-30.1"\n') == "Release-30.2"
    pkgs = "Package: nvidia-driver-580\n\nPackage: nvidia-driver-580-open\n\nPackage: nvidia-driver-595-open\nVersion: 1\n\nPackage: nvidia-driver-600\n"
    assert parse_ubuntu_nvidia_branches(pkgs) == {"580", "595"}
    assert newest(parse_ubuntu_nvidia_branches(pkgs)) == "595"
    assert newest(["4.3.1", "4.3.10", "4.3.9"]) == "4.3.10"
    for path, key, *_ in PINS:
        assert key in read_env(path), f"{key} missing from {path.relative_to(ROOT)}"
    bom = json.loads(BOM.read_text())
    for name in ("Qubes OS", "PureOS", "Rocky Linux", "Red Hat Enterprise Linux", "OpenCore Legacy Patcher", "PureBoot (coreboot + Heads)"):
        bom_component(bom, name)
    print("selftest: OK")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="rewrite the pin files when upstream moved")
    ap.add_argument("--summary", metavar="FILE", help="write a Markdown summary here")
    ap.add_argument("--github-output", action="store_true", help="append changed=/manual= to $GITHUB_OUTPUT")
    ap.add_argument("--strict", action="store_true", help="exit 1 if any resolver failed")
    ap.add_argument("--selftest", action="store_true", help="offline parser checks")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    catalog = read_env(CATALOG)
    rows, changes, manual, failures = [], {}, [], []
    updates: dict = {}          # path -> {key: value}
    extra_all: dict = {}
    for path, key, resolver, apply, source in PINS:
        current = read_env(path)[key]
        try:
            latest, extra, reason = resolver(catalog)
            if not latest:
                raise ValueError("nothing matched in the upstream listing")
        except Exception as exc:  # noqa: BLE001 - every resolver failure is reported, never fatal
            failures.append((key, f"{type(exc).__name__}: {exc}"))
            rows.append((key, current, "?", source, "unresolved"))
            continue
        if latest == current:
            rows.append((key, current, latest, source, "current"))
        elif vtuple(latest) < vtuple(current):
            rows.append((key, current, latest, source, "pin is newer (kept)"))
        elif not apply or reason:
            manual.append((key, current, latest, reason or "report-only pin; bump by hand"))
            rows.append((key, current, latest, source, "manual"))
        else:
            changes[key] = (current, latest)
            updates.setdefault(path, {})[key] = latest
            updates[path].update(extra)
            extra_all.update(extra)
            rows.append((key, current, latest, source, "bump"))

    stale = stale_mentions(changes) if changes else {}
    if args.apply and changes:
        sync_sbom(changes, extra_all)   # reads the old PureOS image name before the env write
        for path, kv in updates.items():
            write_env(path, kv)

    width = max(len(k) for _p, k, *_ in PINS)
    for key, current, latest, _source, result in rows:
        print(f"{key:<{width}}  {current:<28} -> {latest:<28} {result}")
    for key, err in failures:
        print(f"!! {key}: {err}", file=sys.stderr)
    if args.summary:
        pathlib.Path(args.summary).write_text(markdown_summary(rows, changes, manual, failures, stale))
    if args.github_output and os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as fh:
            fh.write(f"changed={'true' if changes else 'false'}\n")
            fh.write(f"manual={'true' if manual else 'false'}\n")
    return 1 if (args.strict and failures) else 0


if __name__ == "__main__":
    sys.exit(main())
