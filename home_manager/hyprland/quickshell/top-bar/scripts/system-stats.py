#!/usr/bin/env python3
"""Emit lightweight local telemetry as one JSON object per second."""

from __future__ import annotations

import json
import shutil
import signal
import time
from pathlib import Path

PROC_STAT = Path("/proc/stat")
PROC_MEMINFO = Path("/proc/meminfo")
BACKLIGHT_ROOT = Path("/sys/class/backlight")


def read_cpu_totals() -> tuple[int, int]:
    fields = PROC_STAT.read_text(encoding="utf-8").splitlines()[0].split()
    values = [int(value) for value in fields[1:9]]
    idle = values[3] + values[4]
    return idle, sum(values)


def read_memory_percent() -> int:
    values: dict[str, int] = {}
    for line in PROC_MEMINFO.read_text(encoding="utf-8").splitlines():
        key, value, *_ = line.replace(":", "").split()
        if key in {"MemTotal", "MemAvailable"}:
            values[key] = int(value)
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", 0)
    return round(100 * (total - available) / total) if total else 0


def find_backlight() -> Path | None:
    try:
        return next(path for path in BACKLIGHT_ROOT.iterdir() if path.is_dir())
    except (FileNotFoundError, StopIteration):
        return None


def read_brightness_percent(backlight: Path | None) -> int:
    if backlight is None:
        return 0
    current = int((backlight / "brightness").read_text(encoding="utf-8"))
    maximum = int((backlight / "max_brightness").read_text(encoding="utf-8"))
    return round(100 * current / maximum) if maximum else 0


def read_disk_percent() -> int:
    usage = shutil.disk_usage("/")
    return round(100 * usage.used / usage.total) if usage.total else 0


def main() -> None:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    backlight = find_backlight()
    previous_idle, previous_total = read_cpu_totals()
    disk = read_disk_percent()
    iteration = 0

    while True:
        time.sleep(1)
        try:
            current_idle, current_total = read_cpu_totals()
            delta_idle = current_idle - previous_idle
            delta_total = current_total - previous_total
            cpu = round(100 * (delta_total - delta_idle) / delta_total) if delta_total else 0
            previous_idle, previous_total = current_idle, current_total

            if iteration % 30 == 0:
                disk = read_disk_percent()

            payload = {
                "cpu": cpu,
                "memory": read_memory_percent(),
                "disk": disk,
                "brightness": read_brightness_percent(backlight),
            }
            print(json.dumps(payload, separators=(",", ":")), flush=True)
            iteration += 1
        except (OSError, ValueError) as error:
            print(json.dumps({"error": str(error)}, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    main()
