#!/usr/bin/python3
import os
import socket
import subprocess
import time
import multiprocessing as mp

import adafruit_ssd1306
from adafruit_extended_bus import ExtendedI2C as I2C
from PIL import Image, ImageDraw, ImageFont

import misc

BASE = "/usr/bin/rockpi-penta/fonts"

try:
    FONT = ImageFont.truetype(f"{BASE}/DejaVuSansMono.ttf", 10)
    FONT_BOLD = ImageFont.truetype(f"{BASE}/DejaVuSansMono-Bold.ttf", 10)
except Exception:
    FONT = ImageFont.load_default()
    FONT_BOLD = FONT


def get_temp():
    try:
        with open("/sys/class/thermal/thermal_zone0/temp", encoding="ascii") as f:
            return f"{int(f.read().strip()) / 1000:.0f}C"
    except Exception:
        return "--C"


def get_load():
    try:
        return f"{os.getloadavg()[0]:.2f}"
    except Exception:
        return "--"


def get_mem():
    try:
        values = {}
        with open("/proc/meminfo", encoding="ascii") as f:
            for line in f:
                key, value = line.split(":", 1)
                values[key] = int(value.strip().split()[0])
        total = values.get("MemTotal", 0)
        available = values.get("MemAvailable", 0)
        if total <= 0:
            return "--%"
        used = total - available
        return f"{round(used / total * 100)}%"
    except Exception:
        return "--%"


def get_ip():
    # Prefer the kernel route table: no DNS and no external packet needs to be sent.
    try:
        result = subprocess.run(
            ["ip", "-4", "route", "get", "1.1.1.1"],
            check=True,
            capture_output=True,
            text=True,
            timeout=0.5,
        )
        parts = result.stdout.split()
        if "src" in parts:
            return parts[parts.index("src") + 1]
    except Exception:
        pass

    # Fallback for minimal systems.
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.settimeout(0.2)
            s.connect(("1.1.1.1", 80))
            return s.getsockname()[0]
    except Exception:
        return "no ip"


def get_fan():
    try:
        chip = os.environ.get("PWMCHIP", "20")
        channel = os.environ.get("PWM_CHANNEL", "4")
        pwm_path = f"/sys/class/pwm/pwmchip{chip}/pwm{channel}"

        with open(f"{pwm_path}/period", encoding="ascii") as f_per:
            period = int(f_per.read().strip())
        with open(f"{pwm_path}/duty_cycle", encoding="ascii") as f_duty:
            duty = int(f_duty.read().strip())

        if period <= 0:
            return "--%"
        # With PWM_POLARITY=inversed, effective fan speed is approximately 100-duty%.
        fan = 100 - round(duty / period * 100)
        return f"{fan}%"
    except Exception:
        return "--%"


def disp_init():
    i2c = I2C(int(os.environ.get("I2C_BUS", "7")))
    disp = adafruit_ssd1306.SSD1306_I2C(
        int(os.environ.get("OLED_WIDTH", "128")),
        int(os.environ.get("OLED_HEIGHT", "32")),
        i2c,
        addr=int(os.environ.get("OLED_ADDR", "0x3c"), 0),
        reset=None,
    )

    disp.write_cmd(0x2E)  # deactivate hardware scroll
    disp.write_cmd(0xA6)  # normal display
    disp.write_cmd(0xA4)  # display follows RAM

    disp.fill(0)
    disp.show()
    return disp


disp = disp_init()


def normalize_display():
    disp.write_cmd(0x2E)
    disp.write_cmd(0xA6)
    disp.write_cmd(0xA4)


def fit(draw, text, font, max_width):
    text = str(text)
    while text and draw.textbbox((0, 0), text, font=font)[2] > max_width:
        text = text[:-1]
    return text


def render(lines):
    image = Image.new("1", (disp.width, disp.height), 0)
    draw = ImageDraw.Draw(image)

    ys = [0, 11, 22]

    for idx, text in enumerate(lines[:3]):
        fnt = FONT_BOLD if idx == 0 else FONT
        draw.text((0, ys[idx]), fit(draw, text, fnt, disp.width), font=fnt, fill=255)

    if misc.conf["oled"]["rotate"]:
        image = image.rotate(180)

    normalize_display()
    disp.image(image)
    disp.show()


def welcome():
    render(["Cubie A7A", "Penta SATA HAT", "Starting..."])


def goodbye():
    render(["Good Bye", "", ""])
    time.sleep(1)
    normalize_display()
    disp.fill(0)
    disp.show()


def slider(lock):
    with lock:
        render([
            f"CPU {get_temp()} L {get_load()}",
            f"Mem {get_mem()} Fan {get_fan()}",
            f"IP {get_ip()}",
        ])


def auto_slider(lock):
    while True:
        slider(lock)
        time.sleep(3)


if __name__ == "__main__":
    lock = mp.Lock()
    auto_slider(lock)
