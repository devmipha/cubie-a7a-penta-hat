# Radxa Cubie A7A + Penta SATA HAT Patch

[English](README.md) | Deutsch

Hilfsdateien, um den Lüfter und das OLED-Top-Board des Radxa Penta SATA HAT auf einem Radxa Cubie A7A zu betreiben.

Dieser Patch wurde für den Cubie A7A / A733 BSP-Kernel erstellt. Dort sind die Top-Board-Signale des HAT nicht 1:1 so belegt, wie es die ursprünglichen ROCK-/Raspberry-Pi-Annahmen in `rockpi-penta` erwarten.

## Was der Patch macht

- Aktiviert Cubie A7A Pin 13 als Lüfter-PWM über `S-PWM0-4`.
- Aktiviert Cubie A7A Pin 3/5 als TWI7 für das OLED.
- Patcht `rockpi-penta/fan.py`, damit ein PWM-Kanal ungleich `0` genutzt werden kann.
- Patcht `rockpi-penta/oled.py`, damit direkt der Linux-I2C-Bus genutzt wird, statt über die Adafruit-Blinka-Board-Erkennung zu gehen.
- Deaktiviert den OLED-Hardware-Scroll beim Initialisieren und vor dem Rendern.
- Legt die Lüfter-/OLED-Konfiguration soweit sinnvoll in `/etc/rockpi-penta.env` ab.

## Getestete Belegung

| Funktion | Cubie A7A | Penta SATA HAT |
|---|---:|---:|
| OLED SDA | Pin 3 | Pin 3 |
| OLED SCL | Pin 5 | Pin 5 |
| Fan PWM | Pin 13 | Pin 13 |
| GND | Pin 6 oder 39 | Pin 6 oder 39 |

Siehe auch: [Pinout / Verkabelung](docs/pinout.de.md)

## Warnung zur Stromversorgung

Nutze genau **einen** Strompfad. Versorge den Cubie A7A **nicht** gleichzeitig über USB-C und den Penta SATA HAT so, dass der Cubie über den 40-Pin-Header rückgespeist wird. Entscheide dich für Cubie → HAT oder HAT → Cubie und prüfe 5 V/GND vor dem Einschalten.

Für erste Signaltests empfiehlt es sich, nur gemeinsame Masse und die benötigten Signalleitungen zu verbinden. 5-V-/3,3-V-Schienen sollten nur verbunden werden, wenn diese Seite bewusst die einzige Stromquelle ist.

## Installation

Installiere das offizielle `rockpi-penta`-Paket auf dem Cubie A7A **nicht** als normale Voraussetzung. Das Upstream-Paket kann dieses Board im `postinst`-Schritt als nicht unterstützt ablehnen.

Starte stattdessen direkt diesen Patch-Installer:

```bash
sudo ./install.sh
sudo reboot
```

Der Installer nutzt vorhandene Basisdateien unter `/usr/bin/rockpi-penta`, falls sie bereits existieren. Falls sie fehlen, versucht er das Upstream-`.deb` von `rockpi-penta` herunterzuladen und mit `dpkg-deb -x` zu extrahieren, ohne das Upstream-`postinst` auszuführen. Danach werden die Cubie-A7A-Patches angewendet.

Nach dem Neustart:

```bash
systemctl status rockpi-penta.service --no-pager
sudo /usr/sbin/i2cdetect -y 7
```

Das OLED sollte auf I2C-Bus 7 mit Adresse `0x3c` erscheinen.

## Konfiguration

Der Installer schreibt folgende Werte nach `/etc/rockpi-penta.env`:

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

Die Lüfterschwellen bleiben in `/etc/rockpi-penta.conf`. Ein leiser Startwert ist:

```ini
[fan]
lv0 = 35
lv1 = 45
lv2 = 60
lv3 = 75
```

Mit `PWM_POLARITY=inversed` entsprechen die `rockpi-penta`-Stufen ungefähr:

| Temperaturschwelle | Lüftergeschwindigkeit |
|---|---:|
| unter `lv0` | aus / minimal |
| `lv0` | 25% |
| `lv1` | 50% |
| `lv2` | 75% |
| `lv3` | 100% |

## Fehlerdiagnose

Siehe [Troubleshooting / Fehlerdiagnose](docs/troubleshooting.de.md).

## Rollback

```bash
sudo ./uninstall.sh
sudo reboot
```

Der Installer legt Backups unter `/var/backups/cubie-a7a-penta-hat/` ab.

## Hinweise

Der Patch verändert absichtlich keine unrelated Overlays, z. B. ein lokales Overlay zum Deaktivieren defekter USB-Hardware. Vorhandene `fdtoverlays`-Einträge werden vom Installer beibehalten.

`PWM_POLARITY=inversed` ist für die getestete Cubie-A7A- und Penta-SATA-HAT-Verkabelung gewollt. Der Installer schreibt den String, den die Linux-PWM-sysfs-Schnittstelle erwartet (`normal`/`inversed`). Wenn dein Kernel diesen Wert ablehnt, zeigt das Service-Journal eine Polarity-Warnung und der Lüfter kann invertiert reagieren.
