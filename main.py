#!/usr/bin/env python3
"""
Fan RPM monitor backed by a native Objective-C bridge.

This follows the same broad shape as mactop's native path: keep a persistent
AppleSMC connection alive, initialize the IOReport side once, and read fan data
through a native bridge instead of pure Python SMC transactions.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
import subprocess
import time
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


OPEN_RETRIES = 3
READ_RETRIES = 3
RETRY_DELAY = 0.03
ERROR_BUFFER_SIZE = 256
BUILD_DIR = Path(__file__).resolve().parent / "build"
NATIVE_LIB_PATH = BUILD_DIR / "libfanbridge.dylib"
DEFAULT_WIDGET_EXPORT_PATH = (
    Path.home() / "Library" / "Application Support" / "MacFanSystem" / "fan_rpm.json"
)


@dataclass
class FanRPM:
    index: int
    rpm: int
    target_rpm: int | None = None
    min_rpm: int | None = None
    max_rpm: int | None = None
    mode: str | None = None


class NativeFanError(RuntimeError):
    pass


class NativeFanInfo(ctypes.Structure):
    _fields_ = [
        ("name", ctypes.c_char * 32),
        ("actualRPM", ctypes.c_int),
        ("minRPM", ctypes.c_int),
        ("maxRPM", ctypes.c_int),
        ("targetRPM", ctypes.c_int),
        ("mode", ctypes.c_int),
        ("id", ctypes.c_int),
    ]


def ensure_native_bridge() -> Path:
    if NATIVE_LIB_PATH.exists():
        return NATIVE_LIB_PATH

    script_path = Path(__file__).resolve().parent / "build_native.sh"
    completed = subprocess.run(
        [str(script_path)],
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0 or not NATIVE_LIB_PATH.exists():
        raise NativeFanError(
            "failed to build native fan bridge: "
            + (completed.stderr.strip() or completed.stdout.strip() or "unknown error")
        )
    return NATIVE_LIB_PATH


class NativeFanBridge:
    def __init__(self) -> None:
        self.lib = ctypes.CDLL(str(ensure_native_bridge()))
        self._configure()
        self._open = False

    def _configure(self) -> None:
        self.lib.fan_bridge_open.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
        self.lib.fan_bridge_open.restype = ctypes.c_int

        self.lib.fan_bridge_close.argtypes = []
        self.lib.fan_bridge_close.restype = None

        self.lib.fan_bridge_read.argtypes = [
            ctypes.POINTER(NativeFanInfo),
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_size_t,
        ]
        self.lib.fan_bridge_read.restype = ctypes.c_int

    def __enter__(self) -> "NativeFanBridge":
        self.open()
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def _error_buffer(self) -> ctypes.Array[ctypes.c_char]:
        return ctypes.create_string_buffer(ERROR_BUFFER_SIZE)

    def _decode_error(self, buffer: ctypes.Array[ctypes.c_char]) -> str:
        return buffer.value.decode("utf-8", errors="replace") or "unknown native fan error"

    def open(self) -> None:
        if self._open:
            return
        error_buffer = self._error_buffer()
        result = self.lib.fan_bridge_open(error_buffer, ERROR_BUFFER_SIZE)
        if result != 0:
            raise NativeFanError(self._decode_error(error_buffer))
        self._open = True

    def close(self) -> None:
        if self._open:
            self.lib.fan_bridge_close()
            self._open = False

    def read(self, max_fans: int = 8) -> tuple[list[FanRPM], str | None]:
        fans_buffer = (NativeFanInfo * max_fans)()
        error_buffer = self._error_buffer()
        count = self.lib.fan_bridge_read(fans_buffer, max_fans, error_buffer, ERROR_BUFFER_SIZE)
        if count < 0:
            return [], self._decode_error(error_buffer)
        if count == 0:
            return [], "no fan rpm keys returned data"

        fans: list[FanRPM] = []
        for item in fans_buffer[:count]:
            mode = None
            if item.mode == 0:
                mode = "auto"
            elif item.mode == 1:
                mode = "manual"
            elif item.mode == 3:
                mode = "system"
            elif item.mode != 0:
                mode = str(item.mode)

            fans.append(
                FanRPM(
                    index=int(item.id),
                    rpm=int(item.actualRPM),
                    target_rpm=int(item.targetRPM) if item.targetRPM > 0 else None,
                    min_rpm=int(item.minRPM) if item.minRPM > 0 else None,
                    max_rpm=int(item.maxRPM) if item.maxRPM > 0 else None,
                    mode=mode,
                )
            )
        return fans, None


def read_fans_from_connection(bridge: NativeFanBridge) -> tuple[list[FanRPM], str | None]:
    last_error: str | None = None
    for attempt in range(READ_RETRIES):
        fans, error = bridge.read()
        if fans:
            return fans, None
        last_error = error
        if attempt < READ_RETRIES - 1:
            time.sleep(RETRY_DELAY)
    return [], last_error


def read_fans() -> tuple[list[FanRPM], str | None]:
    last_error: str | None = None
    for attempt in range(OPEN_RETRIES):
        try:
            with NativeFanBridge() as bridge:
                fans, error = read_fans_from_connection(bridge)
                if fans:
                    return fans, None
                last_error = error
        except NativeFanError as exc:
            last_error = str(exc)

        if attempt < OPEN_RETRIES - 1:
            time.sleep(RETRY_DELAY)
    return [], last_error


def print_text(fans: list[FanRPM], error: str | None) -> None:
    if error:
        print(f"fan rpm unavailable: {error}")
        return
    if not fans:
        print("fan rpm unavailable: no fan rpm keys returned data")
        return

    for fan in fans:
        details = []
        if fan.mode:
            details.append(fan.mode)
        if fan.min_rpm is not None and fan.max_rpm is not None:
            details.append(f"{fan.min_rpm}-{fan.max_rpm}")
        suffix = f" ({', '.join(details)})" if details else ""
        print(f"fan{fan.index}: {fan.rpm} rpm{suffix}")


def print_json(fans: list[FanRPM], error: str | None) -> None:
    if error:
        print(json.dumps({"fans": [], "error": error}, indent=2))
        return
    print(json.dumps({"fans": [asdict(fan) for fan in fans]}, indent=2))


def build_payload(fans: list[FanRPM], error: str | None) -> dict[str, object]:
    return {
        "timestamp": datetime.now().isoformat(),
        "fans": [asdict(fan) for fan in fans],
        "error": error,
    }


def export_widget_payload(fans: list[FanRPM], error: str | None, export_path: Path) -> None:
    export_path.parent.mkdir(parents=True, exist_ok=True)
    export_path.write_text(json.dumps(build_payload(fans, error), indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Display fan RPM using a native AppleSMC and IOReport bridge."
    )
    parser.add_argument("--watch", type=float, metavar="SECS", help="Refresh every N seconds.")
    parser.add_argument("--json", action="store_true", help="Emit JSON.")
    parser.add_argument(
        "--widget-export",
        action="store_true",
        help="Write widget JSON to disk using the configured export path.",
    )
    parser.add_argument(
        "--widget-export-path",
        default=str(DEFAULT_WIDGET_EXPORT_PATH),
        help=f"Path for widget JSON export. Default: {DEFAULT_WIDGET_EXPORT_PATH}",
    )
    args = parser.parse_args()

    export_path = Path(args.widget_export_path).expanduser()
    last_good_fans: list[FanRPM] = []
    persistent_bridge: NativeFanBridge | None = None

    try:
        if args.watch:
            for attempt in range(OPEN_RETRIES):
                try:
                    persistent_bridge = NativeFanBridge()
                    persistent_bridge.open()
                    break
                except NativeFanError:
                    persistent_bridge = None
                    if attempt < OPEN_RETRIES - 1:
                        time.sleep(RETRY_DELAY)

        while True:
            if persistent_bridge is not None:
                fans, error = read_fans_from_connection(persistent_bridge)
            else:
                fans, error = read_fans()

            if fans:
                last_good_fans = fans
            elif last_good_fans:
                fans = last_good_fans
                error = None

            if args.watch and persistent_bridge is None:
                for attempt in range(OPEN_RETRIES):
                    try:
                        persistent_bridge = NativeFanBridge()
                        persistent_bridge.open()
                        break
                    except NativeFanError:
                        persistent_bridge = None
                        if attempt < OPEN_RETRIES - 1:
                            time.sleep(RETRY_DELAY)

            if args.widget_export:
                export_widget_payload(fans, error, export_path)
            if args.json:
                print_json(fans, error)
            else:
                if args.watch:
                    os.system("clear")
                print_text(fans, error)

            if not args.watch:
                break
            time.sleep(args.watch)
    except KeyboardInterrupt:
        return 0
    finally:
        if persistent_bridge is not None:
            persistent_bridge.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
