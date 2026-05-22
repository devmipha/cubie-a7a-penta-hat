# Changelog

## 0.2.3

- Clarify installation flow: do not require a normal upstream `rockpi-penta` install on Cubie A7A.
- Installer now uses existing upstream base files when present, otherwise attempts to download and extract the upstream `.deb` without running its unsupported-board `postinst`.
- Installer installs upstream Python requirements when available before applying Cubie A7A patches.

## 0.2.2

- Added bilingual documentation:
  - `README.md` / `README.de.md`
  - `docs/pinout.md` / `docs/pinout.de.md`
  - `docs/troubleshooting.md` / `docs/troubleshooting.de.md`
- Confirmed `fan.py` uses logging and does not require `sys`.
- Confirmed `/proc/meminfo` is opened with `encoding="ascii"` in `oled.py`.
- Kept the tested OLED layout and SSD1306 hardware-scroll reset sequence.

## 0.2.1

- Added robust PWM polarity handling.
- Made OLED fan-speed display use `PWMCHIP` and `PWM_CHANNEL` from `/etc/rockpi-penta.env`.
- Improved installer checks and PEP-668 pip fallback.
- Added prominent power/backfeeding warnings.

## 0.2.0

- Initial package with overlays, installer, patched `fan.py`, patched `oled.py`, and English documentation.
