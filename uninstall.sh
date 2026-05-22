#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="/var/backups/cubie-a7a-penta-hat"
BASE_DIR="/usr/bin/rockpi-penta"
EXTLINUX="/boot/extlinux/extlinux.conf"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo ./uninstall.sh" >&2
  exit 1
fi

latest_backup() {
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n1
}

BACKUP_DIR="${1:-$(latest_backup)}"
if [[ -z "${BACKUP_DIR:-}" || ! -d "$BACKUP_DIR" ]]; then
  cat >&2 <<MSG
No backup directory found.
Expected backups under: $BACKUP_ROOT
You may pass a backup directory explicitly:
  sudo ./uninstall.sh /var/backups/cubie-a7a-penta-hat/YYYYmmdd-HHMMSS
MSG
  exit 1
fi

echo "Using backup: $BACKUP_DIR"

if [[ -f "$BACKUP_DIR/extlinux.conf" ]]; then
  cp -a "$BACKUP_DIR/extlinux.conf" "$EXTLINUX"
else
  echo "Warning: no extlinux.conf backup found; leaving $EXTLINUX unchanged" >&2
fi

if [[ -f "$BACKUP_DIR/rockpi-penta.env" ]]; then
  cp -a "$BACKUP_DIR/rockpi-penta.env" /etc/rockpi-penta.env
else
  echo "Warning: no rockpi-penta.env backup found; leaving current env file unchanged" >&2
fi

if [[ -f "$BACKUP_DIR/fan.py" ]]; then
  cp -a "$BACKUP_DIR/fan.py" "$BASE_DIR/fan.py"
else
  echo "Warning: no fan.py backup found; leaving current file unchanged" >&2
fi

if [[ -f "$BACKUP_DIR/oled.py" ]]; then
  cp -a "$BACKUP_DIR/oled.py" "$BASE_DIR/oled.py"
else
  echo "Warning: no oled.py backup found; leaving current file unchanged" >&2
fi

systemctl daemon-reload
systemctl restart rockpi-penta.service || true

cat <<MSG

Uninstall/rollback completed from:
  $BACKUP_DIR

A reboot is recommended if device-tree overlays changed.
MSG
