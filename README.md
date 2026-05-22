# Radxa Cubie A7A + Penta SATA HAT patch

English | [Deutsch](README.de.md)

Support files for running the Radxa Penta SATA HAT top-board fan and OLED on a Radxa Cubie A7A.

This patch was created for the Cubie A7A / A733 BSP kernel where the HAT top-board signals do not map 1:1 to the original ROCK/Raspberry Pi assumptions in `rockpi-penta`.

## What this does

- Enables Cubie A7A pin 13 as fan PWM via `S-PWM0-4`.
- Enables Cubie A7A pins 3/5 as TWI7 for the OLED.
- Patches `rockpi-penta/fan.py` to support a non-zero PWM channel.
- Patches `rockpi-penta/oled.py` to use direct Linux I2C bus access instead of Adafruit Blinka board detection.
- Disables OLED hardware scroll during initialization and before rendering.
- Keeps the fan/OLED configuration in `/etc/rockpi-penta.env` where practical.

## Tested mapping

| Function | Cubie A7A | Penta SATA HAT |
|---|---:|---:|
| OLED SDA | Pin 3 | Pin 3 |
| OLED SCL | Pin 5 | Pin 5 |
| Fan PWM | Pin 13 | Pin 13 |
| GND | Pin 6 or 39 | Pin 6 or 39 |

See also: [Pinout / Wiring](docs/pinout.md)

## Power warning

Use exactly one power path. Do **not** power the Cubie A7A over USB-C while also powering the Penta SATA HAT in a way that backfeeds the Cubie through the 40-pin header. Choose either Cubie → HAT or HAT → Cubie and verify 5 V/GND wiring before powering on.

For initial signal-only testing, connect a shared GND and the required signal pins first; do not bridge 5 V/3.3 V rails unless you intentionally use that side as the only power source.

## Install

Do **not** run a normal upstream `rockpi-penta` installation as a prerequisite on the Cubie A7A. The upstream package may reject this board during its `postinst` step.

Run this patch installer directly:

```bash
sudo ./install.sh
sudo reboot
```

The installer uses existing `/usr/bin/rockpi-penta` base files if they are already present. If they are missing, it tries to download the upstream `rockpi-penta` `.deb` and extract it with `dpkg-deb -x` without running the upstream `postinst`, then applies the Cubie A7A patches.

After reboot:

```bash
systemctl status rockpi-penta.service --no-pager
sudo /usr/sbin/i2cdetect -y 7
```

The OLED should be at address `0x3c` on I2C bus 7.

## Configuration

The installer writes these values to `/etc/rockpi-penta.env`:

```text
HARDWARE_PWM=1
PWMCHIP=20
PWM_CHANNEL=4
PWM_POLARITY=inversed
PWM_PERIOD_US=40
I2C_BUS=7
OLED_ADDR=0x3c
OLED_WIDTH=128
OLED_HEIGHT=32
```

Fan thresholds remain in `/etc/rockpi-penta.conf`. A quiet starting point is:

```ini
[fan]
lv0 = 35
lv1 = 45
lv2 = 60
lv3 = 75
```

With `PWM_POLARITY=inversed`, the `rockpi-penta` levels are approximately:

| Temperature level | Fan speed |
|---|---:|
| below `lv0` | off / minimal |
| `lv0` | 25% |
| `lv1` | 50% |
| `lv2` | 75% |
| `lv3` | 100% |

## Troubleshooting

See [Troubleshooting](docs/troubleshooting.md).

## Rollback

```bash
sudo ./uninstall.sh
sudo reboot
```

The installer stores backups in `/var/backups/cubie-a7a-penta-hat/`.

## Notes

This patch intentionally does not modify unrelated overlays, such as a local overlay for disabling broken USB hardware. Existing `fdtoverlays` entries are preserved by the installer.

`PWM_POLARITY=inversed` is intentional for the tested Cubie A7A + Penta SATA HAT wiring. The installer writes the string expected by the Linux PWM sysfs interface (`normal`/`inversed`). If your kernel rejects it, the service journal will show a polarity warning and the fan may behave inverted.
