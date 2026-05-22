#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo ./install.sh" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/var/backups/cubie-a7a-penta-hat/$(date +%Y%m%d-%H%M%S)"
BASE_DIR="/usr/bin/rockpi-penta"

require_file() {
  if [[ ! -e "$1" ]]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

validate_extlinux() {
  python3 - <<'PY'
from pathlib import Path
path = Path('/boot/extlinux/extlinux.conf')
text = path.read_text()
if not any(line.strip().startswith(('fdtoverlays', 'fdtdir')) for line in text.splitlines()):
    raise SystemExit('Could not find fdtdir/fdtoverlays in /boot/extlinux/extlinux.conf; aborting before changes')
PY
}

pip_install() {
  local pkg="$1"
  local module="${2:-${pkg//-/_}}"

  if python3 - <<PY >/dev/null 2>&1
import importlib
importlib.import_module('${module}')
PY
  then
    return 0
  fi

  # Debian 12+ may enforce PEP 668; older pip may not know --break-system-packages.
  python3 -m pip install --upgrade "$pkg" --break-system-packages >/dev/null 2>&1 \
    || python3 -m pip install --upgrade "$pkg" >/dev/null
}

pip_install_requirements() {
  local req="$1"
  [[ -f "$req" ]] || return 0

  python3 -m pip install -r "$req" --break-system-packages >/dev/null 2>&1 \
    || python3 -m pip install -r "$req" >/dev/null
}

ensure_rockpi_penta_base() {
  if [[ -f "$BASE_DIR/main.py" && -f "$BASE_DIR/misc.py" ]]; then
    echo "Found existing rockpi-penta base files in $BASE_DIR"
    return 0
  fi

  echo "rockpi-penta base files are missing."
  echo "Trying to download and extract the upstream rockpi-penta package without running its postinst..."

  local tmp deb
  tmp="$(mktemp -d)"
  (
    cd "$tmp"
    if ! apt-get download rockpi-penta >/dev/null; then
      cat >&2 <<'MSG'
Could not download the upstream rockpi-penta package.

This patch intentionally does not require running the official package postinst,
because the upstream package may reject the Cubie A7A as unsupported. However,
it still needs the upstream base files (main.py, misc.py, fonts, service unit).

Options:
  1. Enable the repository that provides rockpi-penta and rerun this installer.
  2. Manually place/extract the upstream rockpi-penta files into /usr/bin/rockpi-penta.
  3. If you already have a rockpi-penta .deb, extract it with:
       sudo dpkg-deb -x rockpi-penta_*.deb /
     Then rerun this installer.
MSG
      exit 1
    fi

    deb="$(ls rockpi-penta_*.deb 2>/dev/null | head -n1)"
    if [[ -z "$deb" ]]; then
      echo "Downloaded rockpi-penta package not found" >&2
      exit 1
    fi
    dpkg-deb -x "$deb" /
  )
  rm -rf "$tmp"

  require_file "$BASE_DIR/main.py"
  require_file "$BASE_DIR/misc.py"
}

require_file /boot/extlinux/extlinux.conf
validate_extlinux

apt-get update
apt-get install -y device-tree-compiler i2c-tools gpiod python3-pip

ensure_rockpi_penta_base
require_file "$BASE_DIR/main.py"
require_file "$BASE_DIR/misc.py"
require_file "$BASE_DIR/fan.py"
require_file "$BASE_DIR/oled.py"

mkdir -p "$BACKUP_DIR" /boot/dtbo
cp -a /boot/extlinux/extlinux.conf "$BACKUP_DIR/extlinux.conf"
[[ -e /etc/rockpi-penta.env ]] && cp -a /etc/rockpi-penta.env "$BACKUP_DIR/rockpi-penta.env" || true
[[ -e "$BASE_DIR/fan.py" ]] && cp -a "$BASE_DIR/fan.py" "$BACKUP_DIR/fan.py" || true
[[ -e "$BASE_DIR/oled.py" ]] && cp -a "$BASE_DIR/oled.py" "$BACKUP_DIR/oled.py" || true

pip_install_requirements "$BASE_DIR/requirements.txt"
pip_install adafruit-extended-bus adafruit_extended_bus

# Build and install overlays.
dtc -@ -I dts -O dtb -o /boot/dtbo/cubie-a7a-spwm0-4-pin13.dtbo "$ROOT_DIR/overlays/cubie-a7a-spwm0-4-pin13.dts"
dtc -@ -I dts -O dtb -o /boot/dtbo/cubie-a7a-twi7-pin3-5.dtbo "$ROOT_DIR/overlays/cubie-a7a-twi7-pin3-5.dts"

# Idempotently add overlays to extlinux.conf. Existing overlays are preserved.
python3 - <<'PY'
from pathlib import Path

path = Path('/boot/extlinux/extlinux.conf')
text = path.read_text()
needed = [
    '/boot/dtbo/cubie-a7a-spwm0-4-pin13.dtbo',
    '/boot/dtbo/cubie-a7a-twi7-pin3-5.dtbo',
]
lines = text.splitlines()
changed = False

for i, line in enumerate(lines):
    stripped = line.strip()
    if stripped.startswith('fdtoverlays'):
        prefix = line[:len(line) - len(line.lstrip())]
        parts = stripped.split()
        overlays = parts[1:]
        for item in needed:
            if item not in overlays:
                overlays.append(item)
                changed = True
        lines[i] = prefix + 'fdtoverlays ' + ' '.join(overlays)
        break
else:
    for i, line in enumerate(lines):
        if line.strip().startswith('fdtdir'):
            indent = line[:len(line) - len(line.lstrip())]
            lines.insert(i + 1, indent + 'fdtoverlays ' + ' '.join(needed))
            changed = True
            break
    else:
        raise SystemExit('Could not find fdtdir/fdtoverlays in extlinux.conf')

if changed:
    path.write_text('\n'.join(lines) + '\n')
PY

# Install patched rockpi-penta files.
install -m 0755 "$ROOT_DIR/files/fan.py" "$BASE_DIR/fan.py"
install -m 0755 "$ROOT_DIR/files/oled.py" "$BASE_DIR/oled.py"

# Update environment idempotently.
python3 - <<'PY'
from pathlib import Path
path = Path('/etc/rockpi-penta.env')
lines = path.read_text().splitlines() if path.exists() else []

values = {
    'HARDWARE_PWM': '1',
    'PWMCHIP': '20',
    'PWM_CHANNEL': '4',
    'PWM_POLARITY': 'inversed',
    'PWM_PERIOD_US': '40',
    'I2C_BUS': '7',
    'OLED_ADDR': '0x3c',
    'OLED_WIDTH': '128',
    'OLED_HEIGHT': '32',
    'BUTTON_CHIP': '0',
    'BUTTON_LINE': '33',
}
seen = set()
out = []
for line in lines:
    if '=' in line and not line.lstrip().startswith('#'):
        key = line.split('=', 1)[0].strip()
        if key in values:
            out.append(f'{key}={values[key]}')
            seen.add(key)
            continue
    out.append(line)

if out and out[-1].strip():
    out.append('')
out.append('# Cubie A7A + Penta SATA HAT patch')
for key, value in values.items():
    if key not in seen:
        out.append(f'{key}={value}')
path.write_text('\n'.join(out).rstrip() + '\n')
PY

python3 -m py_compile "$BASE_DIR/fan.py" "$BASE_DIR/oled.py"
systemctl daemon-reload
systemctl enable rockpi-penta.service >/dev/null || true
systemctl restart rockpi-penta.service || true

cat <<MSG

Installed Cubie A7A Penta HAT patch.
Backup: $BACKUP_DIR

Required reboot: yes, if overlays were newly added.
After reboot, verify with:
  grep -nE 'fdtoverlays|spwm|twi7' /boot/extlinux/extlinux.conf
  for d in /sys/class/i2c-dev/i2c-*; do bus=\${d##*/i2c-}; echo --- i2c-\$bus ---; readlink -f \$d/device; done
  sudo /usr/sbin/i2cdetect -y 7
  sudo cat /sys/kernel/debug/pwm | sed -n '/7023000.pwm/,+14p'
MSG
