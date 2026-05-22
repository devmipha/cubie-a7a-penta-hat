#!/usr/bin/env bash
set -u

OK=0
WARN=0
FAIL=0
SUDO=""
[[ ${EUID:-$(id -u)} -eq 0 ]] || SUDO="sudo"

ok() { echo "[ OK ] $*"; OK=$((OK + 1)); }
warn() { echo "[WARN] $*"; WARN=$((WARN + 1)); }
fail() { echo "[FAIL] $*"; FAIL=$((FAIL + 1)); }
info() { echo "[INFO] $*"; }

read_dt_string() {
  local path="$1"
  tr -d '\0' < "$path" 2>/dev/null || true
}

check_file_contains() {
  local file="$1" pattern="$2" label="$3"
  if [[ -f "$file" ]] && grep -q -- "$pattern" "$file"; then
    ok "$label"
  else
    fail "$label"
  fi
}

check_env_value() {
  local key="$1" expected="$2" file="/etc/rockpi-penta.env"
  local value=""
  if [[ -f "$file" ]]; then
    value="$(awk -F= -v k="$key" '$1 == k {v=$2} END {print v}' "$file")"
  fi
  if [[ "$value" == "$expected" ]]; then
    ok "$key=$expected"
  else
    fail "$key expected '$expected', got '${value:-missing}'"
  fi
}

info "System"
arch="$(uname -m 2>/dev/null || true)"
if [[ "$arch" == "aarch64" ]]; then
  ok "Architecture is aarch64"
else
  warn "Architecture is '$arch', expected aarch64"
fi

model="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)"
compatible="$(tr '\0' ' ' < /proc/device-tree/compatible 2>/dev/null || true)"
board_id="$model $compatible"

if [[ "$board_id" == *"Cubie A7A"* \
   || "$board_id" == *"cubie-a7a"* \
   || "$board_id" == *"radxa,cubie-a7a"* ]]; then
  ok "Device-tree compatible identifies Radxa Cubie A7A"
else
  warn "Device-tree does not clearly identify Cubie A7A: model='$model', compatible='$compatible'"
fi

info "Boot overlays"
check_file_contains /boot/extlinux/extlinux.conf "cubie-a7a-spwm0-4-pin13.dtbo" "Fan PWM overlay listed in extlinux.conf"
check_file_contains /boot/extlinux/extlinux.conf "cubie-a7a-twi7-pin3-5.dtbo" "TWI7/OLED overlay listed in extlinux.conf"
if [[ -f /boot/dtbo/cubie-a7a-spwm0-4-pin13.dtbo ]]; then
  ok "Fan PWM .dtbo exists"
else
  fail "Fan PWM .dtbo missing"
fi
if [[ -f /boot/dtbo/cubie-a7a-twi7-pin3-5.dtbo ]]; then
  ok "TWI7/OLED .dtbo exists"
else
  fail "TWI7/OLED .dtbo missing"
fi

info "Device tree runtime state"
twi7_status="$(read_dt_string /sys/firmware/devicetree/base/soc@3000000/twi@2517000/status)"
if [[ "$twi7_status" == "okay" ]]; then
  ok "TWI7 status is okay"
else
  fail "TWI7 status is '${twi7_status:-missing}'"
fi
spwm_status="$(read_dt_string /sys/firmware/devicetree/base/soc@3000000/s_pwm0@7023014/status)"
if [[ "$spwm_status" == "okay" ]]; then
  ok "S-PWM0-4 status is okay"
else
  fail "S-PWM0-4 status is '${spwm_status:-missing}'"
fi

info "I2C / OLED"
i2c_bus=""
for d in /sys/class/i2c-dev/i2c-*; do
  [[ -e "$d" ]] || continue
  if readlink -f "$d/device" | grep -q '2517000.twi'; then
    i2c_bus="${d##*/i2c-}"
    break
  fi
done

if [[ -n "$i2c_bus" ]]; then
  ok "TWI7 registered as /dev/i2c-$i2c_bus"
  if command -v /usr/sbin/i2cdetect >/dev/null 2>&1; then
    scan="$($SUDO /usr/sbin/i2cdetect -y "$i2c_bus" 2>/dev/null || true)"
    if echo "$scan" | grep -Eq '(^|[[:space:]])3c([[:space:]]|$)'; then
      ok "OLED detected at 0x3c on i2c-$i2c_bus"
    else
      warn "OLED 0x3c not visible on i2c-$i2c_bus. Check power, SDA/SCL, reset, and HAT wiring."
    fi
  else
    warn "i2cdetect not installed; cannot scan OLED address"
  fi
else
  fail "No /dev/i2c-* adapter points to 2517000.twi"
fi

info "PWM / fan"
if [[ -d /sys/class/pwm/pwmchip20 ]]; then
  ok "pwmchip20 exists"
else
  fail "pwmchip20 missing"
fi
if [[ -d /sys/class/pwm/pwmchip20/pwm4 ]]; then
  ok "pwmchip20/pwm4 is exported"
  period="$(cat /sys/class/pwm/pwmchip20/pwm4/period 2>/dev/null || true)"
  duty="$(cat /sys/class/pwm/pwmchip20/pwm4/duty_cycle 2>/dev/null || true)"
  polarity="$(cat /sys/class/pwm/pwmchip20/pwm4/polarity 2>/dev/null || true)"
  info "pwm4 period=${period:-?} duty=${duty:-?} polarity=${polarity:-?}"
else
  warn "pwmchip20/pwm4 is not exported yet. It is usually exported after rockpi-penta.service starts."
fi


info "Drive temperatures"
drive_count=0
hottest_milli=0

for hwmon in /sys/class/hwmon/hwmon*; do
  [[ -e "$hwmon/name" ]] || continue
  [[ "$(cat "$hwmon/name" 2>/dev/null)" == "drivetemp" ]] || continue
  [[ -e "$hwmon/temp1_input" ]] || continue

  temp_milli="$(cat "$hwmon/temp1_input" 2>/dev/null || true)"
  [[ "$temp_milli" =~ ^[0-9]+$ ]] || continue

  drive_count=$((drive_count + 1))
  if (( temp_milli > hottest_milli )); then
    hottest_milli="$temp_milli"
  fi
done

if (( drive_count > 0 )); then
  hottest_c=$((hottest_milli / 1000))
  ok "drivetemp exposes ${drive_count} drive temperature sensor(s), hottest ${hottest_c}C"
else
  warn "No drivetemp drive temperature sensor found; fan control will use CPU temperature only"
fi

info "Configuration"
check_env_value HARDWARE_PWM 1
check_env_value PWMCHIP 20
check_env_value PWM_CHANNEL 4
check_env_value PWM_POLARITY inversed
check_env_value PWM_PERIOD_US 40
check_env_value I2C_BUS 7
check_env_value OLED_ADDR 0x3c

info "Service"
if systemctl is-active --quiet rockpi-penta.service; then
  ok "rockpi-penta.service is active"
else
  fail "rockpi-penta.service is not active"
  systemctl status rockpi-penta.service --no-pager 2>/dev/null || true
fi

printf '\nSummary: %d OK, %d warnings, %d failures\n' "$OK" "$WARN" "$FAIL"
[[ "$FAIL" -eq 0 ]]
