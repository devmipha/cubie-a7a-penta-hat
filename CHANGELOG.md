# Changelog

## 0.3.0
- Made the installer self-contained.
- Removed dependency on downloading or successfully configuring the upstream `rockpi-penta` package.
- Added bundled minimal `main.py`, `misc.py`, and systemd service unit.
- Installed fonts from the system package instead of relying on upstream package contents.
- Fixed systemd unit ordering so the service starts promptly during boot.

## 0.2.7
- Fixed Cubie A7A board detection using `/proc/device-tree/compatible`.
- Fixed installer preflight extlinux validation.
- Fixed temporary overlay compile cleanup during `install.sh --check`.

## 0.2.6
- Fixed Cubie A7A board detection by checking `/proc/device-tree/compatible` for `radxa,cubie-a7a`.

## 0.2.5
- Fixed GitHub Actions static checks.
- Updated workflow checkout action to avoid Node.js 20 deprecation warnings.
- Resolved ShellCheck findings in `install.sh` and `verify.sh`.

## 0.2.4

- Added `verify.sh` for post-install diagnostics.
- Added `install.sh --check`, `--dry-run`, `--verbose`, and `--force` modes.
- Added prerequisite checks for overlay source files, Python syntax, extlinux, board model, and architecture.
- Improved installer error messages around Device Tree overlay compilation.
- Added optional upstream `.deb` checksum validation via `ROCKPI_PENTA_DEB_SHA256`.
- Added `config.example.env` documenting all supported environment values.
- Added `.gitignore`, `.editorconfig`, `.shellcheckrc`, `Makefile`, GitHub issue template, and static-check workflow.
- Expanded English and German README files with Quick Start, requirements, verification, FAQ, and maintainer checks.
- Expanded troubleshooting documentation in English and German.
- Improved uninstall script with explicit backup selection and backup validation.

## 0.2.3

- Clarified that the official upstream `rockpi-penta` package should not be installed normally first on Cubie A7A.
- Installer extracts upstream base files without running upstream `postinst` when needed.

## 0.2.2

- Added bilingual documentation.
- Added consistency fixes in Python file handling.

## 0.2.1

- Improved Python robustness for fan and OLED patches.
- Added README power warning and troubleshooting notes.

## 0.2.0

- Added patched fan and OLED support for Cubie A7A + Penta SATA HAT.
- Added Device Tree overlays for S-PWM0-4 and TWI7.
