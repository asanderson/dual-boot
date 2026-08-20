# shellcheck shell=bash
# oses.sh — per-OS knowledge for the plan layer: descriptions, latest-release
# checks, and (where an unauthenticated official channel exists) installer
# image fetch + verification. Source AFTER common.sh and os-catalog.env.
#
# Naming: catalog keys use hyphens (windows-11-pro); function suffixes use
# underscores via os_fn_suffix.

os_fn_suffix() { printf '%s' "${1//-/_}"; }

os_describe() {
  case "$1" in
    ubuntu)          echo "Ubuntu ${UBUNTU_VERSION} LTS — the Raider/MacBook pair target" ;;
    qubes)           echo "Qubes OS ${QUBES_VERSION} — Xen-based compartmentalized OS" ;;
    pureos)          echo "PureOS ${PUREOS_VERSION} '${PUREOS_CODENAME}' — Purism's Debian-based OS" ;;
    rocky)           echo "Rocky Linux ${ROCKY_VERSION} — RHEL-compatible community rebuild" ;;
    rhel)            echo "Red Hat Enterprise Linux ${RHEL_VERSION} — media requires a Red Hat login" ;;
    windows-11-pro)  echo "Microsoft Windows 11 Pro ${WIN11_VERSION} — multi-edition ISO, edition by key" ;;
    windows-11-home) echo "Microsoft Windows 11 Home ${WIN11_VERSION} — multi-edition ISO, edition by key" ;;
    *)               echo "unknown OS '$1' (catalog: ${OS_CATALOG})" ;;
  esac
}

os_in_catalog() {
  [[ " ${OS_CATALOG} " == *" $1 "* ]]
}

# ---------------------------------------------------------------------------
# Latest-release checks — best-effort scrapes of official endpoints; each
# reports drift against the catalog pin and never installs anything.
# ---------------------------------------------------------------------------
os_release_check_ubuntu() {
  log "Ubuntu ${UBUNTU_VERSION} pinned; on an installed Ubuntu the release/kernel"
  log "check runs via common/ubuntu/scripts/20-kernel.sh (--check-releases)."
}

os_release_check_qubes() {
  local latest
  latest="$(fetch --max-time 20 "${QUBES_ISO_DIR_URL}/" 2>/dev/null \
    | grep -oE 'Qubes-R[0-9]+\.[0-9]+(\.[0-9]+)?-x86_64\.iso' \
    | grep -oE 'R[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -uV | tail -1 || true)"
  if [[ -n "$latest" ]]; then
    log "Latest Qubes OS release: ${latest} (pinned: R${QUBES_VERSION})"
    if [[ "$latest" != "R${QUBES_VERSION}" ]]; then
      warn "Pinned QUBES_VERSION (R${QUBES_VERSION}) differs from the latest (${latest}) — update common/config/os-catalog.env."
    fi
  else
    warn "Could not determine the latest Qubes release; using pin R${QUBES_VERSION}."
  fi
}

os_release_check_pureos() {
  local latest
  latest="$(fetch --max-time 20 "${PUREOS_IMAGES_ROOT_URL}/" 2>/dev/null \
    | grep -oE '20[0-9]{2}\.[0-9]{2}' | sort -uV | tail -1 || true)"
  if [[ -n "$latest" ]]; then
    log "Latest PureOS ${PUREOS_VERSION} '${PUREOS_CODENAME}' image set: ${latest} (pinned: ${PUREOS_RELEASE_DIR})"
    if [[ "$latest" != "$PUREOS_RELEASE_DIR" ]]; then
      warn "Pinned PUREOS_RELEASE_DIR (${PUREOS_RELEASE_DIR}) differs from the latest (${latest}) — update common/config/os-catalog.env."
    fi
  else
    warn "Could not determine the latest PureOS image set; using pin ${PUREOS_RELEASE_DIR}."
  fi
  log "(a successor codename to '${PUREOS_CODENAME}' would appear on pureos.net/download)"
}

os_release_check_rocky() {
  local latest
  latest="$(fetch --max-time 20 "${ROCKY_ISO_ROOT_URL}/" 2>/dev/null \
    | grep -oE 'href="[0-9]+(\.[0-9]+)?/"' | grep -oE '[0-9]+(\.[0-9]+)?' \
    | sort -uV | tail -1 || true)"
  if [[ -n "$latest" ]]; then
    log "Latest Rocky Linux release directory: ${latest} (pinned: ${ROCKY_VERSION})"
    if [[ "$latest" != "$ROCKY_VERSION" ]]; then
      warn "Pinned ROCKY_VERSION (${ROCKY_VERSION}) differs from the latest (${latest}) — update common/config/os-catalog.env."
    fi
  else
    warn "Could not determine the latest Rocky release; using pin ${ROCKY_VERSION}."
  fi
}

os_release_check_rhel() {
  local latest
  latest="$(fetch --max-time 20 "${RHEL_RELEASES_URL}" 2>/dev/null \
    | grep -oE '(Red Hat Enterprise Linux|RHEL) [0-9]+\.[0-9]+' \
    | grep -oE '[0-9]+\.[0-9]+' | sort -uV | tail -1 || true)"
  if [[ -n "$latest" ]]; then
    log "Latest RHEL release: ${latest} (pinned: ${RHEL_VERSION})"
    if [[ "$latest" != "$RHEL_VERSION" ]]; then
      warn "Pinned RHEL_VERSION (${RHEL_VERSION}) differs from the latest (${latest}) — update common/config/os-catalog.env."
    fi
  else
    warn "Could not determine the latest RHEL release; using pin ${RHEL_VERSION}."
  fi
  log "RHEL media needs a Red Hat login (customer or no-cost Developer"
  log "Subscription): https://developers.redhat.com/products/rhel/download"
}

os_release_check_win11() {
  local latest
  latest="$(fetch --max-time 20 "${WIN11_RELEASE_INFO_URL}" 2>/dev/null \
    | grep -oE 'Version [0-9]{2}H[0-9]' | grep -oE '[0-9]{2}H[0-9]' \
    | sort -uV | tail -1 || true)"
  if [[ -n "$latest" ]]; then
    log "Newest Windows 11 version on the release-health page: ${latest} (pinned: ${WIN11_VERSION})"
    if [[ "$latest" != "$WIN11_VERSION" ]]; then
      warn "Pinned WIN11_VERSION (${WIN11_VERSION}) differs from ${latest} — but newer"
      warn "version strings can be silicon-targeted releases (e.g. 26H1) that never"
      warn "reach the consumer download page; confirm what ${WIN11_DOWNLOAD_URL}"
      warn "actually offers before bumping the pin."
    fi
  else
    warn "Could not determine the latest Windows 11 version; using pin ${WIN11_VERSION}."
  fi
  log "Media: one multi-edition ISO covers Pro and Home (edition chosen by"
  log "product key or ei.cfg) from ${WIN11_DOWNLOAD_URL} — the page generates"
  log "time-limited links, so the download itself is a manual step."
}
os_release_check_windows_11_pro()  { os_release_check_win11; }
os_release_check_windows_11_home() { os_release_check_win11; }

os_release_check() {
  local fn
  fn="os_release_check_$(os_fn_suffix "$1")"
  if declare -F "$fn" >/dev/null; then "$fn"; else warn "No release check for '$1'."; fi
}

# ---------------------------------------------------------------------------
# Installer image fetch + verification (unauthenticated official channels
# only — RHEL and Windows media are login-gated/manual by design; see the
# release checks above for their channels). All verification is hard-fail.
# ---------------------------------------------------------------------------
os_fetch_verify_qubes() {
  local dir="$1" iso="Qubes-R${QUBES_VERSION}-x86_64.iso"
  mkdir -p "$dir"; cd "$dir" || die "cannot cd to ${dir}"
  [[ -f "$iso" ]] || fetch -O "${QUBES_ISO_DIR_URL}/${iso}"
  fetch -O "${QUBES_ISO_DIR_URL}/${iso}.asc"
  fetch -o qubes-master-key.asc "${QUBES_MASTER_KEY_URL}"
  fetch -o qubes-release-key.asc "${QUBES_RELEASE_KEY_URL}"
  export GNUPGHOME="${dir}/.gnupg-qubes"
  mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
  gpg -q --import qubes-master-key.asc qubes-release-key.asc
  gpg --fingerprint --with-colons 2>/dev/null | grep -q "fpr:::::::::${QUBES_MASTER_KEY_FPR}:" \
    || die "Qubes Master Signing Key fingerprint mismatch — expected ${QUBES_MASTER_KEY_FPR}. Do not proceed."
  echo "${QUBES_MASTER_KEY_FPR}:6:" | gpg -q --import-ownertrust
  gpg --check-sigs --with-colons "Qubes OS Release" 2>/dev/null \
    | grep -q "^sig:!:.*${QUBES_MASTER_KEY_FPR: -16}" \
    || die "Qubes release key is NOT signed by the pinned master key. Do not proceed."
  gpg --verify "${iso}.asc" "$iso" 2>&1 | grep -q "Good signature" \
    || die "BAD SIGNATURE on ${iso} — do not use this image."
  unset GNUPGHOME
  cd - >/dev/null || true
  ok "Qubes ISO signature verified (release key chained to the pinned master key)."
}

os_fetch_verify_pureos() {
  local dir="$1" iso="${PUREOS_IMAGE}" iso_sha remote_sha
  mkdir -p "$dir"; cd "$dir" || die "cannot cd to ${dir}"
  [[ -f "$iso" ]] || fetch -O "${PUREOS_DL_BASE_URL}/${iso}"
  iso_sha="$(sha256sum "$iso" | cut -d' ' -f1)"
  [[ "$iso_sha" == "$PUREOS_ISO_SHA256" ]] \
    || die "PureOS ISO sha256 mismatch — expected ${PUREOS_ISO_SHA256}, got ${iso_sha}. Do not use this image."
  remote_sha="$(fetch --max-time 20 "${PUREOS_DL_BASE_URL}/${iso%.iso}.checksums_sha256.txt" 2>/dev/null \
    | grep -oE '^[0-9a-f]{64}' | head -1 || true)"
  if [[ -n "$remote_sha" && "$remote_sha" != "$PUREOS_ISO_SHA256" ]]; then
    die "Published PureOS checksum (${remote_sha}) disagrees with the pin — investigate before proceeding."
  fi
  cd - >/dev/null || true
  ok "PureOS ISO sha256 verified against the pin$( [[ -n "$remote_sha" ]] && echo ' and the published checksum file' )."
}

os_fetch_verify_rocky() {
  # Stable name: Rocky-<major>-latest-x86_64-dvd.iso (byte-identical to the
  # current point release); the CHECKSUM file names the exact version and
  # carries a DETACHED signature by the pinned Rocky release key.
  local dir="$1" iso="Rocky-${ROCKY_MAJOR}-latest-x86_64-dvd.iso"
  local base="${ROCKY_ISO_ROOT_URL}/${ROCKY_MAJOR}/isos/x86_64"
  mkdir -p "$dir"; cd "$dir" || die "cannot cd to ${dir}"
  [[ -f "$iso" ]] || fetch -O "${base}/${iso}"
  fetch -o rocky-CHECKSUM "${base}/CHECKSUM"
  fetch -o rocky-CHECKSUM.asc "${base}/CHECKSUM.asc"
  fetch -o rocky-gpg-key.asc "${ROCKY_GPG_KEY_URL}"
  export GNUPGHOME="${dir}/.gnupg-rocky"
  mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
  gpg -q --import rocky-gpg-key.asc
  gpg --fingerprint --with-colons 2>/dev/null | grep -q "fpr:::::::::${ROCKY_GPG_KEY_FPR}:" \
    || die "Rocky Linux GPG key fingerprint mismatch — expected ${ROCKY_GPG_KEY_FPR}. Do not proceed."
  gpg --verify rocky-CHECKSUM.asc rocky-CHECKSUM 2>&1 | grep -q "Good signature" \
    || die "BAD SIGNATURE on the Rocky CHECKSUM file — do not trust these checksums."
  unset GNUPGHOME
  local expected actual
  expected="$(grep -F "SHA256 (${iso})" rocky-CHECKSUM | grep -oE '[0-9a-f]{64}' | head -1 || true)"
  [[ -n "$expected" ]] || die "Could not find ${iso} in the signed CHECKSUM file."
  actual="$(sha256sum "$iso" | cut -d' ' -f1)"
  [[ "$actual" == "$expected" ]] || die "Rocky ISO sha256 mismatch — do not use this image."
  cd - >/dev/null || true
  ok "Rocky ISO verified against the GPG-signed CHECKSUM file."
}
