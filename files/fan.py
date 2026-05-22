#!/usr/bin/python3
"""PWM fan control for the Cubie A7A Penta SATA HAT.

The fan speed is controlled by the highest requested cooling level from:
- CPU/SoC temperature
- hottest SATA drive temperature exposed via the kernel drivetemp hwmon driver

Drive temperatures are discovered automatically by scanning:
  /sys/class/hwmon/hwmon*/name == "drivetemp"
"""

from __future__ import annotations

import logging
import os
import time
from pathlib import Path


logging.basicConfig(
    level=logging.INFO,
    format="rockpi-penta fan: %(levelname)s: %(message)s",
)


def env_bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)))
    except ValueError:
        logging.warning("Invalid integer for %s=%r, using %d", name, os.environ.get(name), default)
        return default


class Pwm:
    def __init__(self) -> None:
        self.chip = env_int("PWMCHIP", 20)
        self.channel = env_int("PWM_CHANNEL", 4)
        self.period_ns = env_int("PWM_PERIOD_US", 40) * 1000
        self.polarity = os.environ.get("PWM_POLARITY", "inversed").strip()

        if self.polarity not in {"normal", "inversed"}:
            logging.warning("Invalid PWM_POLARITY=%r, using 'inversed'", self.polarity)
            self.polarity = "inversed"

        self.chip_path = Path(f"/sys/class/pwm/pwmchip{self.chip}")
        self.path = self.chip_path / f"pwm{self.channel}"

        self._export()
        self._configure()

    def _write(self, name: str, value: str | int) -> None:
        (self.path / name).write_text(str(value), encoding="ascii")

    def _export(self) -> None:
        if self.path.exists():
            return

        logging.info("Exporting pwmchip%d/pwm%d", self.chip, self.channel)
        (self.chip_path / "export").write_text(str(self.channel), encoding="ascii")

        for _ in range(20):
            if self.path.exists():
                return
            time.sleep(0.05)

        raise RuntimeError(f"PWM path did not appear: {self.path}")

    def _configure(self) -> None:
        try:
            self._write("enable", 0)
        except OSError:
            pass

        try:
            self._write("polarity", self.polarity)
        except OSError:
            logging.exception("Could not set PWM polarity to %s", self.polarity)

        self._write("period", self.period_ns)
        self.set_speed_percent(0)
        self._write("enable", 1)

    def set_speed_percent(self, speed: int) -> None:
        speed = max(0, min(100, int(speed)))

        if self.polarity == "inversed":
            duty = round(self.period_ns * (100 - speed) / 100)
        else:
            duty = round(self.period_ns * speed / 100)

        duty = max(0, min(self.period_ns, duty))
        self._write("duty_cycle", duty)


def read_temp_file(path: Path) -> float | None:
    try:
        milli_c = int(path.read_text(encoding="ascii").strip())
        return milli_c / 1000.0
    except Exception:
        return None


def get_cpu_temp_c() -> float | None:
    temps: list[float] = []

    for zone in Path("/sys/class/thermal").glob("thermal_zone*"):
        temp = read_temp_file(zone / "temp")
        if temp is not None:
            temps.append(temp)

    return max(temps) if temps else None


def get_drive_temps_hwmon() -> list[float]:
    temps: list[float] = []

    for hwmon in Path("/sys/class/hwmon").glob("hwmon*"):
        name_file = hwmon / "name"
        temp_file = hwmon / "temp1_input"

        try:
            if name_file.read_text(encoding="ascii").strip() != "drivetemp":
                continue
        except Exception:
            continue

        temp = read_temp_file(temp_file)
        if temp is not None:
            temps.append(temp)

    return temps


_drive_cache_ts = 0.0
_drive_cache: list[float] = []


def get_cached_drive_temps() -> list[float]:
    global _drive_cache_ts, _drive_cache

    interval = max(1, env_int("FAN_DRIVE_INTERVAL", 10))
    now = time.monotonic()

    if now - _drive_cache_ts >= interval:
        _drive_cache = get_drive_temps_hwmon()
        _drive_cache_ts = now

    return _drive_cache


def temp_to_speed(temp_c: float, prefix: str) -> int:
    lv0 = env_int(f"{prefix}_LV0", 35)
    lv1 = env_int(f"{prefix}_LV1", 45)
    lv2 = env_int(f"{prefix}_LV2", 60)
    lv3 = env_int(f"{prefix}_LV3", 75)

    if temp_c >= lv3:
        return 100
    if temp_c >= lv2:
        return 75
    if temp_c >= lv1:
        return 50
    if temp_c >= lv0:
        return 25
    return 0


def choose_fan_speed(cpu_temp: float | None, drive_temps: list[float]) -> int:
    requested: list[int] = []

    if env_bool("FAN_CPU_ENABLE", True) and cpu_temp is not None:
        requested.append(temp_to_speed(cpu_temp, "FAN_CPU"))

    if env_bool("FAN_DRIVE_ENABLE", True) and drive_temps:
        requested.append(temp_to_speed(max(drive_temps), "FAN_DRIVE"))

    return max(requested) if requested else 0


def running() -> None:
    pwm = Pwm()
    interval = max(1, env_int("FAN_INTERVAL", 2))
    last_speed: int | None = None

    while True:
        cpu_temp = get_cpu_temp_c()
        drive_temps = get_cached_drive_temps()
        speed = choose_fan_speed(cpu_temp, drive_temps)

        try:
            pwm.set_speed_percent(speed)
        except Exception:
            logging.exception("Failed to update fan PWM")

        if speed != last_speed:
            drive_text = f"{max(drive_temps):.1f}C" if drive_temps else "n/a"
            cpu_text = f"{cpu_temp:.1f}C" if cpu_temp is not None else "n/a"
            logging.info("fan=%d%% cpu=%s drive_max=%s", speed, cpu_text, drive_text)
            last_speed = speed

        time.sleep(interval)


if __name__ == "__main__":
    running()
