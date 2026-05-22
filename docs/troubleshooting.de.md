# Troubleshooting / Fehlerdiagnose

[English](troubleshooting.md) | Deutsch

## I2C/OLED

Erwartung:

```bash
sudo /usr/sbin/i2cdetect -y 7
```

Dort sollte `0x3c` erscheinen.

Wenn Bus 7 nicht existiert, prüfe, ob das TWI7-Overlay geladen wurde:

```bash
grep -nE 'fdtoverlays|twi7' /boot/extlinux/extlinux.conf
tr -d '\0' < /sys/firmware/devicetree/base/soc@3000000/twi@2517000/status
```

Wenn `2517000.twi` auf `okay` steht, aber kein `/dev/i2c-*` erscheint, prüfe das Treiber-Probe-Log:

```bash
sudo dmesg -T | grep -Ei '2517000|twi7|failed to get clock frequency|sunxi-twi' | tail -80
```

Das TWI7-Overlay muss `clock-frequency = <100000>;` setzen. Ohne diese Property kann der BSP-Treiber mit `failed to get clock frequency` abbrechen.

Wenn das Display geteilt aussieht oder scrollt, ist im OLED-Controller wahrscheinlich noch Hardware-Scroll aktiv. Die gepatchte `oled.py` sendet:

- `0x2E` Scroll deaktivieren
- `0xA6` Normaldarstellung
- `0xA4` Anzeige folgt RAM-Inhalt

## Fan PWM

Erwarteter PWM-Kanal:

```bash
sudo mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
sudo cat /sys/kernel/debug/pwm | sed -n '/7023000.pwm/,+14p'
```

Erwartung: `pwm-4` ist auf `platform/7023000.pwm` aktiv.

Die Umgebung sollte enthalten:

```text
PWMCHIP=20
PWM_CHANNEL=4
PWM_POLARITY=inversed
PWM_PERIOD_US=40
```

Die sysfs-Werte für PWM-Polarität sind normalerweise `normal` oder `inversed`. Wenn dein Kernel `inversed` ablehnt, prüfe:

```bash
sudo journalctl -u rockpi-penta.service -b --no-pager | grep -i polarity
```

## Stromversorgung

Den Cubie nicht gleichzeitig per USB-C und über den HAT-Stromeingang versorgen, wenn die 5-V-Schienen über den 40-Pin-Header verbunden sind. Nur eine Stromquelle bzw. eine eindeutige Stromtopologie verwenden.

## Bekannte Nicht-OLED-Busse

- `i2c-20` ist HDMI-DDC, nicht das OLED.
- `i2c-15@0x3e` ist der `sunxi-ac101b` Audio-Codec, nicht das OLED.
