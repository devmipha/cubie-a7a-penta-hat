# Radxa Cubie A7A + Penta SATA HAT Patch

[English](README.md) | Deutsch

Hilfsdateien, um den Lüfter und das OLED-Top-Board des Radxa Penta SATA HAT auf einem Radxa Cubie A7A zu betreiben.

Dieser Patch wurde für den Cubie A7A / A733 BSP-Kernel erstellt. Dort sind die Top-Board-Signale des HAT nicht 1:1 so belegt, wie es die ursprünglichen ROCK-/Raspberry-Pi-Annahmen in `rockpi-penta` erwarten.

## Schnellstart

```bash
git clone https://github.com/devmipha/cubie-a7a-penta-hat.git
cd cubie-a7a-penta-hat
sudo ./install.sh --check
sudo ./install.sh
sudo reboot
```

Nach dem Neustart:

```bash
cd cubie-a7a-penta-hat
sudo ./verify.sh
systemctl status rockpi-penta.service --no-pager
```

## Voraussetzungen / getestete Umgebung

Getestet mit:

- Radxa Cubie A7A / A733 BSP-Kernel
- Radxa-Debian-Images mit U-Boot/extlinux-Bootflow
- Linux-5.15-`a733`-BSP-Kernel
- aarch64-Userspace

Vom Installer erwartet:

- `/boot/extlinux/extlinux.conf`
- `/boot/dtbo`-Overlay-Unterstützung
- Zugriff auf die Upstream-`rockpi-penta`-Basisdateien, entweder bereits installiert/extrahiert oder per `apt-get download rockpi-penta` verfügbar

Der Installer muss das offizielle `rockpi-penta`-`postinst` nicht ausführen, weil das Upstream-Paket den Cubie A7A als nicht unterstützt ablehnen kann.

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

Starte direkt diesen Patch-Installer:

```bash
sudo ./install.sh
sudo reboot
```

Nützliche Installer-Modi:

```bash
sudo ./install.sh --check       # nur Voraussetzungen prüfen
sudo ./install.sh --dry-run     # geplante Änderungen anzeigen
sudo ./install.sh -v            # ausführliche Ausgabe
```

Der Installer nutzt vorhandene Basisdateien unter `/usr/bin/rockpi-penta`, falls sie bereits existieren. Falls sie fehlen, versucht er das Upstream-`.deb` von `rockpi-penta` herunterzuladen und mit `dpkg-deb -x` zu extrahieren, ohne das Upstream-`postinst` auszuführen. Danach werden die Cubie-A7A-Patches angewendet.

Wenn du eine Prüfsumme für das heruntergeladene Upstream-`.deb` erzwingen möchtest:

```bash
export ROCKPI_PENTA_DEB_SHA256=<erwartete-sha256>
sudo -E ./install.sh
```

## Verifikation

```bash
sudo ./verify.sh
```

Das Diagnose-Skript prüft:

- Boot-Overlay-Einträge und `.dtbo`-Dateien
- Runtime-Device-Tree-Status für TWI7 und S-PWM0-4
- I2C-Bus 7 / OLED-Adresse `0x3c`
- PWM-Pfad `pwmchip20/pwm4`
- Werte in `/etc/rockpi-penta.env`
- Status von `rockpi-penta.service`

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

Siehe [config.example.env](config.example.env) für kommentierte Konfigurationswerte.

`PWM_PERIOD_US=40` bedeutet 40 Mikrosekunden PWM-Periode, also 25 kHz. Das ist eine typische leise PWM-Frequenz für Lüfter.

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

## FAQ

### OLED wird nicht erkannt?

```bash
sudo ./verify.sh
sudo /usr/sbin/i2cdetect -y 7
```

Erwartet: Adresse `0x3c` auf Bus 7. Wenn der Bus fehlt, wurde das TWI7-Overlay nicht geladen oder nach der Installation noch nicht neu gestartet.

### Lüfter dreht nicht oder ändert die Drehzahl nicht?

```bash
sudo ./verify.sh
sudo cat /sys/kernel/debug/pwm | sed -n '/7023000.pwm/,+14p'
```

Erwartet: `pwm-4` auf `platform/7023000.pwm`, sobald `rockpi-penta.service` läuft.

### Display wirkt geteilt oder scrollt horizontal?

Dieser Patch sendet explizit SSD1306-Kommandos, um Hardware-Scrolling zu deaktivieren. Falls es trotzdem passiert, den HAT komplett stromlos machen; der OLED-Controller kann Scroll-Zustand behalten, solange er versorgt wird.

### Kann ich Cubie und HAT getrennt gleichzeitig versorgen?

Nein. Nutze nur einen Strompfad, um Backfeeding zu vermeiden.

## Fehlerdiagnose

Siehe [Troubleshooting / Fehlerdiagnose](docs/troubleshooting.de.md).

## Rollback

```bash
sudo ./uninstall.sh
sudo reboot
```

Der Installer legt Backups unter `/var/backups/cubie-a7a-penta-hat/` ab.

## Maintainer-Checks

```bash
make check
make package
```

Statische Checks liegen zusätzlich in `.github/workflows/check.yml`.

## Hinweise

Der Patch verändert absichtlich keine unrelated Overlays, z. B. ein lokales Overlay zum Deaktivieren defekter USB-Hardware. Vorhandene `fdtoverlays`-Einträge werden vom Installer beibehalten.

`PWM_POLARITY=inversed` ist für die getestete Cubie-A7A- und Penta-SATA-HAT-Verkabelung gewollt. Der Installer schreibt den String, den die Linux-PWM-sysfs-Schnittstelle erwartet (`normal`/`inversed`). Wenn dein Kernel diesen Wert ablehnt, zeigt das Service-Journal eine Polarity-Warnung und der Lüfter kann invertiert reagieren.
