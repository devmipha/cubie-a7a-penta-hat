#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/usr/bin/rockpi-penta"
EXTLINUX="/boot/extlinux/extlinux.conf"

DRY_RUN=0
VERBOSE=0
PURGE=0

usage() {
  cat <<'USAGE'
Usage: sudo ./uninstall.sh [options]

Options:
  --dry-run         Show intended actions without changing the system.
  -v, --verbose     Print commands before running them.
  --purge           Also remove /etc/rockpi-penta.conf.
  -h, --help        Show this help.
USAGE
}

log() { echo "[uninstall] $*"; }
warn() { echo "[uninstall] WARNING: $*" >&2; }
die() { echo "[uninstall] ERROR: $*" >&2; exit 1; }

run() {
  if [[ "$VERBOSE" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    printf '[uninstall] +'
    printf ' %q' "$@"
    printf '\n'
  fi

  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$@"
  fi
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    die "Please run as root: sudo ./uninstall.sh"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -v|--verbose) VERBOSE=1 ;;
    --purge) PURGE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

remove_extlinux_overlays() {
  if [[ ! -f "$EXTLINUX" ]]; then
    warn "$EXTLINUX not found; skipping boot overlay cleanup"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Would remove Penta-HAT overlays from $EXTLINUX"
    return 0
  fi

  python3 - <<'PY'
from pathlib import Path

path = Path("/boot/extlinux/extlinux.conf")
text = path.read_text(encoding="utf-8")

remove = {
    "/boot/dtbo/cubie-a7a-spwm0-4-pin13.dtbo",
    "/boot/dtbo/cubie-a7a-twi7-pin3-5.dtbo",
}

out = []
for line in text.splitlines():
    stripped = line.strip()

    if stripped.startswith("fdtoverlays"):
        indent = line[:len(line) - len(line.lstrip())]
        parts = stripped.split()
        overlays = [item for item in parts[1:] if item not in remove]

        if overlays:
            out.append(indent + "fdtoverlays " + " ".join(overlays))
        continue

    out.append(line)

path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
}

require_root

log "Stopping and disabling service"
run systemctl disable --now rockpi-penta.service 2>/dev/null || true

log "Removing systemd unit"
run rm -f /lib/systemd/system/rockpi-penta.service
run rm -f /etc/systemd/system/multi-user.target.wants/rockpi-penta.service
run systemctl daemon-reload
run systemctl reset-failed rockpi-penta.service 2>/dev/null || true

log "Removing boot overlay entries"
remove_extlinux_overlays

log "Removing installed files"
run rm -rf "$BASE_DIR"
run rm -f /etc/rockpi-penta.env
run rm -f /etc/modules-load.d/cubie-a7a-penta-hat.conf

if [[ "$PURGE" -eq 1 ]]; then
  run rm -f /etc/rockpi-penta.conf
else
  log "Keeping /etc/rockpi-penta.conf if present. Use --purge to remove it."
fi

log "Removing installed device-tree overlay binaries"
run rm -f /boot/dtbo/cubie-a7a-spwm0-4-pin13.dtbo
run rm -f /boot/dtbo/cubie-a7a-twi7-pin3-5.dtbo

cat <<MSG

Uninstalled Cubie A7A Penta HAT patch.

Recommended next step:
  sudo reboot

Note:
  This does not remove unrelated overlays such as cubie-a7a-disable-broken-usb.dtbo.
MSG
