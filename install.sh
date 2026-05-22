#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="/var/backups/cubie-a7a-penta-hat"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
BASE_DIR="/usr/bin/rockpi-penta"
EXTLINUX="/boot/extlinux/extlinux.conf"

DRY_RUN=0
CHECK_ONLY=0
VERBOSE=0
FORCE=0

OVERLAY_SOURCES=(
  "$ROOT_DIR/overlays/cubie-a7a-spwm0-4-pin13.dts"
  "$ROOT_DIR/overlays/cubie-a7a-twi7-pin3-5.dts"
)

usage() {
  cat <<'USAGE'
Usage: sudo ./install.sh [options]

Options:
  --check           Run prerequisite checks only; do not change the system.
  --dry-run         Show intended actions without changing the system.
  -v, --verbose     Print commands before running them.
  --force           Continue despite board/architecture warnings.
  -h, --help        Show this help.
USAGE
}

log() { echo "[install] $*"; }
warn() { echo "[install] WARNING: $*" >&2; }
die() { echo "[install] ERROR: $*" >&2; exit 1; }

run() {
  if [[ "$VERBOSE" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    printf '[install] +'
    printf ' %q' "$@"
    printf '\n'
  fi
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -v|--verbose) VERBOSE=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    die "Please run as root: sudo ./install.sh"
  fi
}

require_file() {
  [[ -e "$1" ]] || die "Missing required file: $1"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

check_arch_and_board() {
  local arch model compatible id

  arch="$(uname -m || true)"
  if [[ "$arch" != "aarch64" && "$FORCE" -ne 1 ]]; then
    die "Expected aarch64, got '$arch'. Use --force to continue anyway."
  elif [[ "$arch" != "aarch64" ]]; then
    warn "Expected aarch64, got '$arch'; continuing due to --force."
  fi

  model="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)"
  compatible="$(tr '\0' ' ' < /proc/device-tree/compatible 2>/dev/null || true)"
  id="$model $compatible"

  if [[ "$id" == *"Cubie A7A"* \
     || "$id" == *"cubie-a7a"* \
     || "$id" == *"radxa,cubie-a7a"* ]]; then
    return 0
  fi

  if [[ "$FORCE" -eq 1 ]]; then
    warn "This does not look like a Radxa Cubie A7A: model='$model', compatible='$compatible'; continuing due to --force."
    return 0
  fi

  die "This does not look like a Radxa Cubie A7A: model='$model', compatible='$compatible'. Use --force to continue."
}

check_overlay_sources() {
  for f in "${OVERLAY_SOURCES[@]}"; do
    require_file "$f"
  done
}

validate_extlinux() {
  require_file "$EXTLINUX"

  python3 - <<'PY_EXTLINUX'
from pathlib import Path

path = Path("/boot/extlinux/extlinux.conf")
text = path.read_text(encoding="utf-8")

if not any(line.strip().startswith(("fdtoverlays", "fdtdir")) for line in text.splitlines()):
    raise SystemExit(
        "Could not find fdtdir/fdtoverlays in /boot/extlinux/extlinux.conf; "
        "aborting before changes"
    )
PY_EXTLINUX
}

check_python_files() {
  require_file "$ROOT_DIR/files/fan.py"
  require_file "$ROOT_DIR/files/oled.py"
  python3 -m py_compile "$ROOT_DIR/files/fan.py" "$ROOT_DIR/files/oled.py"
}

check_dtc_compile() {
  local tmp
  command_exists dtc || return 0
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  for src in "${OVERLAY_SOURCES[@]}"; do
    local out
    out="$tmp/$(basename "$src" .dts).dtbo"
    if ! dtc -@ -I dts -O dtb -o "$out" "$src"; then
      die "Device-tree overlay failed to compile: $src"
    fi
  done
}

preflight() {
  log "Running prerequisite checks"
  require_file "$ROOT_DIR/files/fan.py"
  require_file "$ROOT_DIR/files/oled.py"
  check_overlay_sources
  validate_extlinux
  check_arch_and_board
  check_python_files
  check_dtc_compile
  log "Preflight checks passed"
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

  log "Installing Python package: $pkg"
  python3 -m pip install --upgrade "$pkg" --break-system-packages >/dev/null 2>&1 \
    || python3 -m pip install --upgrade "$pkg" >/dev/null
}

pip_install_requirements() {
  local req="$1"
  [[ -f "$req" ]] || return 0

  log "Installing upstream Python requirements from $req"
  python3 -m pip install -r "$req" --break-system-packages >/dev/null 2>&1 \
    || python3 -m pip install -r "$req" >/dev/null
}

validate_deb_if_requested() {
  local deb="$1"
  local expected_sha="${ROCKPI_PENTA_DEB_SHA256:-}"

  if [[ -n "$expected_sha" ]]; then
    local actual
    actual="$(sha256sum "$deb" | awk '{print $1}')"
    [[ "$actual" == "$expected_sha" ]] || die "SHA256 mismatch for $deb: expected $expected_sha, got $actual"
  else
    warn "ROCKPI_PENTA_DEB_SHA256 not set; validating package metadata/contents instead of checksum."
  fi

  [[ "$(dpkg-deb -f "$deb" Package)" == "rockpi-penta" ]] || die "Downloaded .deb is not package rockpi-penta"
  dpkg-deb -c "$deb" | grep -q '/usr/bin/rockpi-penta/main.py$' || die "rockpi-penta .deb does not contain main.py"
  dpkg-deb -c "$deb" | grep -q '/usr/bin/rockpi-penta/misc.py$' || die "rockpi-penta .deb does not contain misc.py"
}

ensure_rockpi_penta_base() {
  if [[ -f "$BASE_DIR/main.py" && -f "$BASE_DIR/misc.py" ]]; then
    log "Found existing rockpi-penta base files in $BASE_DIR"
    return 0
  fi

  log "rockpi-penta base files are missing. Downloading and extracting upstream package without running postinst."

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

    deb="$(find . -maxdepth 1 -type f -name 'rockpi-penta_*.deb' -printf '%f\n' | sort | head -n1)"
    [[ -n "$deb" ]] || die "Downloaded rockpi-penta package not found"
    validate_deb_if_requested "$deb"
    run dpkg-deb -x "$deb" /
  )
  rm -rf "$tmp"

  require_file "$BASE_DIR/main.py"
  require_file "$BASE_DIR/misc.py"
}

update_extlinux() {
  python3 - <<'PY'
from pathlib import Path

path = Path('/boot/extlinux/extlinux.conf')
text = path.read_text(encoding='utf-8')
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
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY
}

update_env() {
  python3 - <<'PY'
from pathlib import Path
path = Path('/etc/rockpi-penta.env')
lines = path.read_text(encoding='utf-8').splitlines() if path.exists() else []

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
path.write_text('\n'.join(out).rstrip() + '\n', encoding='utf-8')
PY
}

if [[ "$CHECK_ONLY" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
  preflight
  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    exit 0
  fi
fi

require_root
preflight

log "Installing OS dependencies"
run apt-get update
run apt-get install -y device-tree-compiler i2c-tools gpiod python3-pip

ensure_rockpi_penta_base
require_file "$BASE_DIR/main.py"
require_file "$BASE_DIR/misc.py"
require_file "$BASE_DIR/fan.py"
require_file "$BASE_DIR/oled.py"

log "Creating backups in $BACKUP_DIR"
run mkdir -p "$BACKUP_DIR" /boot/dtbo
run cp -a "$EXTLINUX" "$BACKUP_DIR/extlinux.conf"
if [[ -e /etc/rockpi-penta.env ]]; then
  run cp -a /etc/rockpi-penta.env "$BACKUP_DIR/rockpi-penta.env"
fi

if [[ -e "$BASE_DIR/fan.py" ]]; then
  run cp -a "$BASE_DIR/fan.py" "$BACKUP_DIR/fan.py"
fi

if [[ -e "$BASE_DIR/oled.py" ]]; then
  run cp -a "$BASE_DIR/oled.py" "$BACKUP_DIR/oled.py"
fi

pip_install_requirements "$BASE_DIR/requirements.txt"
pip_install adafruit-extended-bus adafruit_extended_bus

log "Building and installing device-tree overlays"
run dtc -@ -I dts -O dtb -o /boot/dtbo/cubie-a7a-spwm0-4-pin13.dtbo "$ROOT_DIR/overlays/cubie-a7a-spwm0-4-pin13.dts"
run dtc -@ -I dts -O dtb -o /boot/dtbo/cubie-a7a-twi7-pin3-5.dtbo "$ROOT_DIR/overlays/cubie-a7a-twi7-pin3-5.dts"

log "Updating extlinux overlays"
if [[ "$DRY_RUN" -eq 0 ]]; then
  update_extlinux
fi

log "Installing patched rockpi-penta files"
run install -m 0755 "$ROOT_DIR/files/fan.py" "$BASE_DIR/fan.py"
run install -m 0755 "$ROOT_DIR/files/oled.py" "$BASE_DIR/oled.py"

log "Updating /etc/rockpi-penta.env"
if [[ "$DRY_RUN" -eq 0 ]]; then
  update_env
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  python3 -m py_compile "$BASE_DIR/fan.py" "$BASE_DIR/oled.py"
  systemctl daemon-reload
  systemctl enable rockpi-penta.service >/dev/null || true
  systemctl restart rockpi-penta.service || true
fi

cat <<MSG

Installed Cubie A7A Penta HAT patch.
Backup: $BACKUP_DIR

Required reboot: yes, if overlays were newly added.
After reboot, run:
  sudo ./verify.sh
MSG
