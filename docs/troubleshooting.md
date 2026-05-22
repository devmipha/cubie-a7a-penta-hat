# Troubleshooting

Run the bundled verifier first:

```bash
sudo ./verify.sh
```

Include the full output when opening an issue.

## Boot overlays

Check extlinux:

```bash
grep -nE 'fdtoverlays|spwm|twi7|dtbo' /boot/extlinux/extlinux.conf
```

Expected overlays:

```text
/boot/dtbo/cubie-a7a-spwm0-4-pin13.dtbo
/boot/dtbo/cubie-a7a-twi7-pin3-5.dtbo
```

Check runtime Device Tree:

```bash
tr -d '\0' < /sys/firmware/devicetree/base/soc@3000000/twi@2517000/status
tr -d '\0' < /sys/firmware/devicetree/base/soc@3000000/s_pwm0@7023014/status
```

Expected: `okay` for both.

## OLED / I2C

List I2C adapters:

```bash
for d in /sys/class/i2c-dev/i2c-*; do
  [ -e "$d" ] || continue
  bus="${d##*/i2c-}"
  echo "--- i2c-$bus ---"
  readlink -f "$d/device"
  cat "$d/name" 2>/dev/null || true
done
```

Expected: one adapter points to `2517000.twi`; it is usually `/dev/i2c-7`.

Scan the OLED bus:

```bash
sudo /usr/sbin/i2cdetect -y 7
```

Expected: `0x3c`.

Known non-OLED buses on the tested system:

- `i2c-15` at `0x3e`: `sunxi-ac101b` audio codec
- `i2c-20`: HDMI DDC, not the top-board OLED

If `2517000.twi` exists but no I2C adapter appears, check dmesg:

```bash
sudo dmesg -T | grep -Ei '2517000|twi7|sunxi-twi'
```

If you see `failed to get clock frequency`, ensure the TWI7 overlay contains:

```dts
clock-frequency = <100000>;
```

## Fan PWM

Expected path after the service starts:

```text
/sys/class/pwm/pwmchip20/pwm4
```

Debug:

```bash
sudo cat /sys/kernel/debug/pwm | sed -n '/7023000.pwm/,+14p'
```

Expected: `pwm-4` active on `platform/7023000.pwm`.

Configuration:

```bash
cat /etc/rockpi-penta.env
```

Expected:

```text
PWMCHIP=20
PWM_CHANNEL=4
PWM_POLARITY=inversed
PWM_PERIOD_US=40
```

`PWM_PERIOD_US=40` means a 40 microsecond period, or 25 kHz.

## Service logs

```bash
systemctl status rockpi-penta.service --no-pager
sudo journalctl -u rockpi-penta.service -b --no-pager | tail -120
```

## Display scrolls or looks split

The OLED controller can retain a hardware-scroll state while powered. This patch sends `0x2E`, `0xA6`, and `0xA4` during initialization and before rendering. If the screen still looks split, stop the service and power-cycle the HAT completely.

## Rollback

```bash
sudo ./uninstall.sh
sudo reboot
```

Backups are stored in `/var/backups/cubie-a7a-penta-hat/`.
