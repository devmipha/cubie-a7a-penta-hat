#!/usr/bin/env python3
import logging
import os
import os.path
import threading
import time
import traceback

try:
    import gpiod
except Exception:
    gpiod = None

import misc

logging.basicConfig(level=logging.INFO, format="rockpi-penta-fan: %(levelname)s: %(message)s")

pin = None
VALID_POLARITIES = {"normal", "inversed"}


class Pwm:
    def __init__(self, chip, channel=0, polarity=None):
        self.period_value = None
        try:
            int(chip)
            chip = f"pwmchip{chip}"
        except ValueError:
            pass

        self.chip_path = f"/sys/class/pwm/{chip}"
        self.channel = int(channel)
        self.filepath = f"{self.chip_path}/pwm{self.channel}/"

        try:
            if not os.path.isdir(self.filepath):
                with open(f"{self.chip_path}/export", "w", encoding="ascii") as f:
                    f.write(str(self.channel))
                time.sleep(0.2)
        except OSError:
            logging.warning("init pwm error")
            traceback.print_exc()

        if polarity:
            if polarity not in VALID_POLARITIES:
                logging.warning("invalid PWM_POLARITY=%r; expected one of %s", polarity, sorted(VALID_POLARITIES))
            else:
                try:
                    self.enable(False)
                    with open(os.path.join(self.filepath, "polarity"), "w", encoding="ascii") as f:
                        f.write(str(polarity))
                except OSError:
                    logging.warning("setting pwm polarity failed")
                    traceback.print_exc()

    def period(self, ns: int):
        self.period_value = ns
        with open(os.path.join(self.filepath, "period"), "w", encoding="ascii") as f:
            f.write(str(ns))

    def period_us(self, us: int):
        self.period(us * 1000)

    def enable(self, t: bool):
        with open(os.path.join(self.filepath, "enable"), "w", encoding="ascii") as f:
            f.write(f"{int(t)}")

    def write(self, duty: float):
        assert self.period_value, "The Period is not set."
        duty = max(0.0, min(1.0, float(duty)))
        with open(os.path.join(self.filepath, "duty_cycle"), "w", encoding="ascii") as f:
            f.write(f"{int(self.period_value * duty)}")


class Gpio:
    def tr(self):
        while True:
            self.line.set_value(1)
            time.sleep(self.value[0])
            self.line.set_value(0)
            time.sleep(self.value[1])

    def __init__(self, period_s):
        if gpiod is None:
            raise RuntimeError("python gpiod module is not available")
        self.line = gpiod.Chip(os.environ["FAN_CHIP"]).get_line(int(os.environ["FAN_LINE"]))
        self.line.request(consumer="fan", type=gpiod.LINE_REQ_DIR_OUT)
        self.value = [period_s / 2, period_s / 2]
        self.period_s = period_s
        self.thread = threading.Thread(target=self.tr, daemon=True)
        self.thread.start()

    def write(self, duty):
        self.value[1] = duty * self.period_s
        self.value[0] = self.period_s - self.value[1]


def read_temp():
    with open("/sys/class/thermal/thermal_zone0/temp", encoding="ascii") as f:
        return int(f.read().strip()) / 1000.0


def get_dc(cache={}):
    if misc.conf["run"].value == 0:
        return 0.999

    if time.time() - cache.get("time", 0) > 60:
        cache["time"] = time.time()
        cache["dc"] = misc.fan_temp2dc(read_temp())

    return cache["dc"]


def change_dc(dc, cache={}):
    if dc != cache.get("dc"):
        cache["dc"] = dc
        pin.write(dc)


def running():
    global pin

    if os.environ["HARDWARE_PWM"] == "1":
        chip = os.environ["PWMCHIP"]
        channel = os.environ.get("PWM_CHANNEL", "0")
        polarity = os.environ.get("PWM_POLARITY", "normal")
        period_us = int(os.environ.get("PWM_PERIOD_US", "40"))

        pin = Pwm(chip, channel=channel, polarity=polarity)
        pin.period_us(period_us)
        pin.write(0.999)
        pin.enable(True)
    else:
        pin = Gpio(0.025)

    while True:
        change_dc(get_dc())
        time.sleep(1)


if __name__ == "__main__":
    running()
