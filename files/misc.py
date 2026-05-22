#!/usr/bin/python3
"""Minimal support module for the Cubie A7A Penta SATA HAT service."""

from __future__ import annotations

import configparser
import os
from pathlib import Path


CONF_PATH = Path("/etc/rockpi-penta.conf")


class Value:
    def __init__(self, value):
        self.value = value


def _load_conf() -> configparser.ConfigParser:
    cfg = configparser.ConfigParser()
    cfg["fan"] = {
        "lv0": "35",
        "lv1": "45",
        "lv2": "60",
        "lv3": "75",
    }
    cfg["slider"] = {
        "auto": "true",
        "time": "3",
    }
    cfg["oled"] = {
        "rotate": "false",
    }
    cfg["run"] = {
        "enabled": "1",
    }

    if CONF_PATH.exists():
        cfg.read(CONF_PATH, encoding="utf-8")

    return cfg


_cfg = _load_conf()

conf = {
    "fan": {
        "lv0": int(_cfg["fan"].get("lv0", "35")),
        "lv1": int(_cfg["fan"].get("lv1", "45")),
        "lv2": int(_cfg["fan"].get("lv2", "60")),
        "lv3": int(_cfg["fan"].get("lv3", "75")),
    },
    "slider": {
        "auto": _cfg["slider"].getboolean("auto", fallback=True),
        "time": int(_cfg["slider"].get("time", "3")),
    },
    "oled": {
        "rotate": _cfg["oled"].getboolean("rotate", fallback=False),
    },
    "run": Value(int(_cfg["run"].get("enabled", "1"))),
}


def fan_temp2dc(temp_c: float) -> float:
    """Map temperature to upstream-compatible duty values.

    With PWM_POLARITY=inversed this becomes approximately:
      < lv0 -> off/minimal
      lv0   -> 25 %
      lv1   -> 50 %
      lv2   -> 75 %
      lv3   -> 100 %
    """
    fan = conf["fan"]

    if temp_c >= fan["lv3"]:
        return 0.0
    if temp_c >= fan["lv2"]:
        return 0.25
    if temp_c >= fan["lv1"]:
        return 0.50
    if temp_c >= fan["lv0"]:
        return 0.75
    return 0.999


def slider_sleep() -> None:
    import time

    time.sleep(conf["slider"]["time"])


def slider_next(pages: dict):
    """Return the first page from a page dictionary.

    Kept for compatibility with older oled.py variants.
    """
    if not pages:
        return []
    return pages[min(pages.keys())]


def get_info(kind: str) -> str:
    if kind == "up":
        try:
            with open("/proc/uptime", encoding="ascii") as f:
                seconds = int(float(f.read().split()[0]))
            hours = seconds // 3600
            minutes = (seconds % 3600) // 60
            return f"Up {hours}h{minutes:02d}m"
        except Exception:
            return "Up n/a"

    if kind == "cpu":
        return f"CPU load {os.getloadavg()[0]:.2f}"

    if kind in {"men", "mem"}:
        try:
            total = available = 0
            with open("/proc/meminfo", encoding="ascii") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        total = int(line.split()[1])
                    elif line.startswith("MemAvailable:"):
                        available = int(line.split()[1])
            used_pct = int((total - available) / total * 100) if total else 0
            return f"Mem {used_pct}%"
        except Exception:
            return "Mem n/a"

    if kind == "ip":
        return "IP n/a"

    return "n/a"


def get_cpu_temp() -> str:
    try:
        with open("/sys/class/thermal/thermal_zone0/temp", encoding="ascii") as f:
            return f"CPU {int(f.read().strip()) / 1000:.1f}C"
    except Exception:
        return "CPU n/a"


def get_disk_info():
    return ["Disk"], ["n/a"]
