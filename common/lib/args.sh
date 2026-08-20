# shellcheck shell=bash
# shellcheck disable=SC2034  # variables here are set for consuming scripts
# args.sh — the shared command-line contract for every runnable script in
# this repo. Sourced automatically by common.sh; do not execute directly.
#
# A script declares which standard flags it supports:
#     COMMON_ARGS_ACCEPT="check-releases destructive disk"
# defines its usage() (usually ending in a usage_common_flags call), then:
#     parse_common_args "$@"
# Flags outside the accept list are rejected with usage. After parsing:
#
#   CHECK_RELEASES   1 when prechecks/release checks should run. The repo
#                    contract is applied here once: interactive runs always
#                    check; unattended (DEV_SETUP_ASSUME_YES=1) only with
#                    --check-releases.
#   DESTRUCTIVE      1 only when --destructive was passed (see
#                    destructive_gate below).
#   BACKUP           "" (prompt later), 1 (--backup) or 0 (--no-backup).
#   OS_SELECTION     comma-separated list from --os, or "".
#   MODE_SELECTION   comma-separated OS=install|upgrade pairs from --mode.
#   TARGET_DISK, BOOT_GIB, DOWNLOAD_DIR, USB_QUBES, USB_PUREOS

_arg_accepted() {
  local accept=" ${COMMON_ARGS_ACCEPT:-check-releases} help "
  [[ "$accept" == *" $1 "* ]] || { err "Unknown argument: $2"; usage; exit 2; }
}

parse_common_args() {
  CHECK_RELEASES=""
  DESTRUCTIVE=""
  BACKUP=""
  OS_SELECTION=""
  MODE_SELECTION=""
  TARGET_DISK="${TARGET_DISK:-${TARGET_DISK_DEFAULT:-}}"
  TARGET_DISK_SET=""
  BOOT_GIB="${BOOT_GIB:-2}"
  BOOT_GIB_SET=""
  DOWNLOAD_DIR="${DOWNLOAD_DIR:-$HOME/dual-boot-isos}"
  PLAN_FILE="${PLAN_FILE:-$HOME/.dual-boot-plan.env}"
  USB_QUBES=""
  USB_PUREOS=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check-releases) _arg_accepted check-releases "$1"; CHECK_RELEASES=1 ;;
      --destructive)    _arg_accepted destructive "$1";    DESTRUCTIVE=1 ;;
      --backup)         _arg_accepted backup "$1";         BACKUP=1 ;;
      --no-backup)      _arg_accepted backup "$1";         BACKUP=0 ;;
      --os)             _arg_accepted os "$1";        OS_SELECTION="${2:?--os needs a comma-separated OS list}"; shift ;;
      --mode)           _arg_accepted mode "$1";      MODE_SELECTION="${MODE_SELECTION:+${MODE_SELECTION},}${2:?--mode needs OS=install|upgrade}"; shift ;;
      --disk)           _arg_accepted disk "$1";      TARGET_DISK="${2:?--disk needs a device}"; TARGET_DISK_SET=1; shift ;;
      --boot-size)      _arg_accepted boot-size "$1"; BOOT_GIB="${2:?--boot-size needs a size in GiB}"; BOOT_GIB_SET=1; shift ;;
      --download-dir)   _arg_accepted download-dir "$1"; DOWNLOAD_DIR="${2:?--download-dir needs a path}"; shift ;;
      --plan-file)      _arg_accepted plan-file "$1"; PLAN_FILE="${2:?--plan-file needs a path}"; shift ;;
      --usb-qubes)      _arg_accepted usb "$1";       USB_QUBES="${2:?--usb-qubes needs a device}"; shift ;;
      --usb-pureos)     _arg_accepted usb "$1";       USB_PUREOS="${2:?--usb-pureos needs a device}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) err "Unknown argument: $1"; usage; exit 2 ;;
    esac
    shift
  done
  [[ "${DEV_SETUP_ASSUME_YES:-0}" != "1" ]] && CHECK_RELEASES=1
  CHECK_RELEASES="${CHECK_RELEASES:-0}"
}

# usage_common_flags — help text for the standard flags this script accepts;
# call it from the script's usage() after its own header line.
usage_common_flags() {
  local accept=" ${COMMON_ARGS_ACCEPT:-check-releases} help "
  if [[ "$accept" == *" check-releases "* ]]; then
    echo "  --check-releases     in non-interactive mode (DEV_SETUP_ASSUME_YES=1), also run"
    echo "                       the firmware/OS release prechecks (interactive always does)"
  fi
  if [[ "$accept" == *" destructive "* ]]; then
    echo "  --destructive        in non-interactive mode, authorize DESTRUCTIVE disk"
    echo "                       actions; without it an unattended run never touches a"
    echo "                       disk (interactive runs confirm instead)"
  fi
  if [[ "$accept" == *" backup "* ]]; then
    echo "  --backup|--no-backup back up the existing partition table and boot"
    echo "                       partitions first, or skip it (default: prompted, yes)"
  fi
  if [[ "$accept" == *" os "* ]]; then
    echo "  --os LIST            comma-separated OSes to plan for; catalog:"
    echo "                       ${OS_CATALOG:-see common/config/os-catalog.env}"
  fi
  if [[ "$accept" == *" mode "* ]]; then
    echo "  --mode OS=MODE       per-OS mode: 'install' (clean, destructive) or"
    echo "                       'upgrade' (in-place); repeatable"
  fi
  [[ "$accept" == *" disk "* ]] && \
    echo "  --disk DEV           target disk (default: ${TARGET_DISK_DEFAULT:-none})"
  [[ "$accept" == *" boot-size "* ]] && \
    echo "  --boot-size GIB      boot partition size in GiB (default: 2)"
  [[ "$accept" == *" download-dir "* ]] && \
    echo "  --download-dir DIR   where installer images are downloaded (default: ~/dual-boot-isos)"
  [[ "$accept" == *" plan-file "* ]] && \
    echo "  --plan-file FILE     where the plan is written/read (default: ~/.dual-boot-plan.env)"
  if [[ "$accept" == *" usb "* ]]; then
    echo "  --usb-qubes DEV      write the Qubes installer to this USB device"
    echo "  --usb-pureos DEV     write the PureOS installer to this USB device"
  fi
}

# destructive_gate "<full prompt text>" — the repo's one rule for destructive
# actions: interactive runs confirm (default YES — destructive flows are
# only wired on devices whose documented default is destructive); unattended
# runs proceed only when --destructive was passed. Returns 0 to proceed.
destructive_gate() {
  local what="$1"
  if [[ "${DEV_SETUP_ASSUME_YES:-0}" == "1" ]]; then
    if [[ "${DESTRUCTIVE:-}" == "1" ]]; then
      log "--destructive passed: proceeding unattended."
      return 0
    fi
    log "Unattended run without --destructive: skipping the destructive step."
    log "(pass --destructive to authorize it unattended)"
    return 1
  fi
  confirm "$what" y
}
