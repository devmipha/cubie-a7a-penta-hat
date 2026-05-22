#!/usr/bin/python3
"""Minimal Cubie A7A Penta SATA HAT service runner."""

from __future__ import annotations

import logging
import multiprocessing as mp
import signal
import sys
import threading
import time


logging.basicConfig(
    level=logging.INFO,
    format="rockpi-penta: %(levelname)s: %(message)s",
)


_stop = threading.Event()


def _handle_signal(signum, frame):  # noqa: ARG001
    _stop.set()


def start_fan() -> threading.Thread:
    import fan

    t = threading.Thread(target=fan.running, name="fan", daemon=True)
    t.start()
    return t


def start_oled() -> threading.Thread | None:
    try:
        import oled
    except Exception:
        logging.exception("OLED disabled because initialization failed")
        return None

    def run_oled() -> None:
        lock = mp.Lock()
        try:
            oled.welcome()
            oled.auto_slider(lock)
        except Exception:
            logging.exception("OLED worker stopped")

    t = threading.Thread(target=run_oled, name="oled", daemon=True)
    t.start()
    return t


def main() -> int:
    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    start_fan()
    start_oled()

    while not _stop.is_set():
        time.sleep(1)

    try:
        import oled

        oled.goodbye()
    except Exception:
        pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
