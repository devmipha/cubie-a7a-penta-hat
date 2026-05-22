# Troubleshooting

English | [Deutsch](troubleshooting.de.md)

## I2C/OLED

Expected:

```bash
sudo /usr/sbin/i2cdetect -y 7
```

Should show `0x3c`.

If bus 7 does not exist, check that the TWI7 overlay is loaded:

```bash
grep -nE 'fdtoverlays|twi7' /boot/extlinux/extlinux.conf
tr -d '\0' < /sys/firmware/devicetree/base/soc@3000000/twi@2517000/status
```

If `2517000.twi` is `okay` but no `/dev/i2c-*` appears, check the driver probe log:

```bash
sudo dmesg -T | grep -Ei '2517000|twi7|failed to get clock frequency|sunxi-twi' | tail -80
```

The TWI7 overlay must set `clock-frequency = <100000>;`. Without it, the BSP driver can fail with `failed to get clock frequency`.

If the display looks split or scrolling, the OLED controller still has hardware scroll enabled. The patched `oled.py` sends:

- `0x2E` deactivate scroll
- `0xA6` normal display
- `0xA4` display follows RAM

## Fan PWM

Expected PWM channel:

```bash
sudo mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
sudo cat /sys/kernel/debug/pwm | sed -n '/7023000.pwm/,+14p'
```

Expected: `pwm-4` active on `platform/7023000.pwm`.

The environment should contain:

```text
PWMCHIP=20
PWM_CHANNEL=4
PWM_POLARITY=inversed
PWM_PERIOD_US=40
```

The sysfs PWM polarity values are normally `normal` or `inversed`. If your kernel rejects `inversed`, check:

```bash
sudo journalctl -u rockpi-penta.service -b --no-pager | grep -i polarity
```

## Power

Do not power the Cubie through USB-C and the HAT power input at the same time if their 5 V rails are connected through the 40-pin header. Use one power source/topology only.

## Known non-target buses

- `i2c-20` is HDMI DDC, not the OLED.
- `i2c-15@0x3e` is the `sunxi-ac101b` audio codec, not the OLED.
