# Radxa Cubie A7A + Penta SATA HAT patch

English | [Deutsch](README.de.md)

Support files for running the Radxa Penta SATA HAT top-board fan and OLED on a Radxa Cubie A7A.

This patch was created for the Cubie A7A / A733 BSP kernel where the HAT top-board signals do not map 1:1 to the original ROCK/Raspberry Pi assumptions in `rockpi-penta`.

## Quick Start

```bash
git clone https://github.com/devmipha/cubie-a7a-penta-hat.git
cd cubie-a7a-penta-hat
sudo ./install.sh --check
sudo ./install.sh
sudo reboot
```

After reboot:

```bash
cd cubie-a7a-penta-hat
sudo ./verify.sh
systemctl status rockpi-penta.service --no-pager
```

## Requirements / tested environment

Tested with:

- Radxa Cubie A7A / A733 BSP kernel
- Radxa Debian-style images with U-Boot/extlinux boot flow
- Linux 5.15 `a733` BSP kernels
- aarch64 userspace

Expected by the installer:

- `/boot/extlinux/extlinux.conf`
- `/boot/dtbo` overlay support
- access to the upstream `rockpi-penta` base files, either already installed/extracted or downloadable through `apt-get download rockpi-penta`

The installer does **not** require running the official `rockpi-penta` package post-install script, because the upstream package may reject the Cubie A7A as unsupported.

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

## Installation

Run this patch installer directly:

```bash
sudo ./install.sh
sudo reboot
```

Useful installer modes:

```bash
sudo ./install.sh --check       # prerequisite checks only
sudo ./install.sh --dry-run     # show intended actions
sudo ./install.sh -v            # verbose mode
```

The installer uses existing `/usr/bin/rockpi-penta` base files if they are already present. If they are missing, it tries to download the upstream `rockpi-penta` `.deb` and extract it with `dpkg-deb -x` without running the upstream `postinst`, then applies the Cubie A7A patches.

If you want checksum validation for the downloaded upstream `.deb`, set:

```bash
export ROCKPI_PENTA_DEB_SHA256=<expected-sha256>
sudo -E ./install.sh
```

## Verification

```bash
sudo ./verify.sh
```

The verifier checks:

- boot overlay entries and `.dtbo` files
- runtime Device Tree status for TWI7 and S-PWM0-4
- I2C bus 7 / OLED address `0x3c`
- PWM path `pwmchip20/pwm4`
- `/etc/rockpi-penta.env` values
- `rockpi-penta.service` state

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

See [config.example.env](config.example.env) for commented configuration values.

`PWM_PERIOD_US=40` means a 40 microsecond PWM period, equivalent to 25 kHz. This is a typical quiet fan PWM frequency.

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

## FAQ

### OLED not detected?

Run:

```bash
sudo ./verify.sh
sudo /usr/sbin/i2cdetect -y 7
```

Expected: address `0x3c` on bus 7. If the bus is missing, the TWI7 overlay did not load or the board has not rebooted after installation.

### Fan not spinning or not changing speed?

Run:

```bash
sudo ./verify.sh
sudo cat /sys/kernel/debug/pwm | sed -n '/7023000.pwm/,+14p'
```

Expected: `pwm-4` on `platform/7023000.pwm` active after `rockpi-penta.service` starts.

### Display looks split or scrolls horizontally?

This patch explicitly sends SSD1306 commands to disable hardware scrolling. If it still happens, power-cycle the HAT completely; the OLED controller may retain scroll state while powered.

### Can I power both the Cubie and the HAT separately?

No. Use one power path only to avoid backfeeding.

## Troubleshooting

See [Troubleshooting](docs/troubleshooting.md).

## Rollback

```bash
sudo ./uninstall.sh
sudo reboot
```

The installer stores backups in `/var/backups/cubie-a7a-penta-hat/`.

## Maintainer checks

```bash
make check
make package
```

Static checks are also defined in `.github/workflows/check.yml`.

## Notes

This patch intentionally does not modify unrelated overlays, such as a local overlay for disabling broken USB hardware. Existing `fdtoverlays` entries are preserved by the installer.

`PWM_POLARITY=inversed` is intentional for the tested Cubie A7A + Penta SATA HAT wiring. The installer writes the string expected by the Linux PWM sysfs interface (`normal`/`inversed`). If your kernel rejects it, the service journal will show a polarity warning and the fan may behave inverted.
