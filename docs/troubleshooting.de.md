# Fehlerdiagnose

Starte zuerst das Diagnose-Skript:

```bash
sudo ./verify.sh
```

Bitte die vollständige Ausgabe in Issues einfügen.

## Boot-Overlays

Extlinux prüfen:

```bash
grep -nE 'fdtoverlays|spwm|twi7|dtbo' /boot/extlinux/extlinux.conf
```

Erwartete Overlays:

```text
/boot/dtbo/cubie-a7a-spwm0-4-pin13.dtbo
/boot/dtbo/cubie-a7a-twi7-pin3-5.dtbo
```

Runtime-Device-Tree prüfen:

```bash
tr -d '\0' < /sys/firmware/devicetree/base/soc@3000000/twi@2517000/status
tr -d '\0' < /sys/firmware/devicetree/base/soc@3000000/s_pwm0@7023014/status
```

Erwartet: jeweils `okay`.

## OLED / I2C

I2C-Adapter anzeigen:

```bash
for d in /sys/class/i2c-dev/i2c-*; do
  [ -e "$d" ] || continue
  bus="${d##*/i2c-}"
  echo "--- i2c-$bus ---"
  readlink -f "$d/device"
  cat "$d/name" 2>/dev/null || true
done
```

Erwartet: Ein Adapter zeigt auf `2517000.twi`; meist ist das `/dev/i2c-7`.

OLED-Bus scannen:

```bash
sudo /usr/sbin/i2cdetect -y 7
```

Erwartet: `0x3c`.

Bekannte Nicht-OLED-Busse im getesteten System:

- `i2c-15` bei `0x3e`: `sunxi-ac101b` Audio-Codec
- `i2c-20`: HDMI-DDC, nicht das Top-Board-OLED

Wenn `2517000.twi` existiert, aber kein I2C-Adapter erscheint:

```bash
sudo dmesg -T | grep -Ei '2517000|twi7|sunxi-twi'
```

Bei `failed to get clock frequency` muss das TWI7-Overlay enthalten:

```dts
clock-frequency = <100000>;
```

## Lüfter-PWM

Erwarteter Pfad nach Start des Services:

```text
/sys/class/pwm/pwmchip20/pwm4
```

Debug:

```bash
sudo cat /sys/kernel/debug/pwm | sed -n '/7023000.pwm/,+14p'
```

Erwartet: `pwm-4` aktiv auf `platform/7023000.pwm`.

Konfiguration:

```bash
cat /etc/rockpi-penta.env
```

Erwartet:

```text
PWMCHIP=20
PWM_CHANNEL=4
PWM_POLARITY=inversed
PWM_PERIOD_US=40
```

`PWM_PERIOD_US=40` bedeutet 40 Mikrosekunden Periodendauer, also 25 kHz.

## Service-Logs

```bash
systemctl status rockpi-penta.service --no-pager
sudo journalctl -u rockpi-penta.service -b --no-pager | tail -120
```

## Display scrollt oder wirkt geteilt

Der OLED-Controller kann einen Hardware-Scroll-Zustand behalten, solange er versorgt wird. Dieser Patch sendet `0x2E`, `0xA6` und `0xA4` beim Initialisieren und vor dem Rendern. Wenn das Display trotzdem geteilt wirkt, Service stoppen und den HAT komplett stromlos machen.

## Rollback

```bash
sudo ./uninstall.sh
sudo reboot
```

Backups liegen unter `/var/backups/cubie-a7a-penta-hat/`.
