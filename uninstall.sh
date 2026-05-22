#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo ./uninstall.sh" >&2
  exit 1
fi

LATEST="$(ls -1dt /var/backups/cubie-a7a-penta-hat/* 2>/dev/null | head -1 || true)"
if [[ -z "$LATEST" ]]; then
  echo "No backup found in /var/backups/cubie-a7a-penta-hat" >&2
  exit 1
fi

echo "Restoring from $LATEST"
[[ -e "$LATEST/extlinux.conf" ]] && cp -a "$LATEST/extlinux.conf" /boot/extlinux/extlinux.conf
[[ -e "$LATEST/rockpi-penta.env" ]] && cp -a "$LATEST/rockpi-penta.env" /etc/rockpi-penta.env
[[ -e "$LATEST/fan.py" ]] && cp -a "$LATEST/fan.py" /usr/bin/rockpi-penta/fan.py
[[ -e "$LATEST/oled.py" ]] && cp -a "$LATEST/oled.py" /usr/bin/rockpi-penta/oled.py

systemctl restart rockpi-penta.service || true

echo "Restored. Reboot recommended if extlinux.conf changed."
