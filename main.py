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


@dataclass
class CoolingStatus:
    high_power_supported: bool
    low_power_supported: bool
    high_power_enabled: bool | None
    low_power_enabled: bool | None

    @property
    def mode(self) -> str:
        if self.high_power_enabled:
            return "high"
        if self.low_power_enabled:
            return "low"
        return "normal"


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

        self.lib.fan_bridge_force_high.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
        self.lib.fan_bridge_force_high.restype = ctypes.c_int

        self.lib.fan_bridge_restore_auto.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
        self.lib.fan_bridge_restore_auto.restype = ctypes.c_int

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

    def force_high(self) -> int:
        error_buffer = self._error_buffer()
        count = self.lib.fan_bridge_force_high(error_buffer, ERROR_BUFFER_SIZE)
        if count < 0:
            raise NativeFanError(self._decode_error(error_buffer))
        return int(count)

    def restore_auto(self) -> int:
        error_buffer = self._error_buffer()
        count = self.lib.fan_bridge_restore_auto(error_buffer, ERROR_BUFFER_SIZE)
        if count < 0:
            raise NativeFanError(self._decode_error(error_buffer))
        return int(count)


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


def run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, capture_output=True, text=True)


def parse_pmset_keys(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.endswith(":"):
            continue
        parts = line.split()
        if len(parts) >= 2:
            values[parts[0].lower()] = parts[-1].lower()
    return values


def command_error(result: subprocess.CompletedProcess[str], fallback: str) -> str:
    stderr = (result.stderr or "").strip()
    stdout = (result.stdout or "").strip()
    return stderr or stdout or fallback


def try_pmset_commands(commands: list[list[str]]) -> tuple[list[str], str | None]:
    errors: list[str] = []
    for command in commands:
        result = run_command(command)
        if result.returncode == 0:
            return command, None
        errors.append(f"{' '.join(command)} -> {command_error(result, 'pmset failed')}")
    return [], "; ".join(errors)


def read_cooling_status() -> CoolingStatus:
    caps_result = run_command(["pmset", "-g", "cap"])
    if caps_result.returncode != 0:
        raise RuntimeError(caps_result.stderr.strip() or "failed to read pmset capabilities")

    settings_result = run_command(["pmset", "-g", "custom"])
    if settings_result.returncode != 0:
        raise RuntimeError(settings_result.stderr.strip() or "failed to read pmset settings")

    caps = {line.strip().lower() for line in caps_result.stdout.splitlines() if line.strip()}
    values = parse_pmset_keys(settings_result.stdout)

    high_supported = "highpowermode" in caps or values.get("powermode") in {"2"} or "powermode" in caps
    low_supported = "lowpowermode" in caps
    if "powermode" in values:
        high_enabled = values.get("powermode") == "2"
        low_enabled = values.get("powermode") == "1"
        high_supported = True
        low_supported = True
    else:
        high_enabled = values.get("highpowermode") == "1" if high_supported else None
        low_enabled = values.get("lowpowermode") == "1" if low_supported else None

    return CoolingStatus(
        high_power_supported=high_supported,
        low_power_supported=low_supported,
        high_power_enabled=high_enabled,
        low_power_enabled=low_enabled,
    )


def set_supported_cooling(mode: str) -> CoolingStatus:
    status = read_cooling_status()

    if os.geteuid() != 0:
        raise RuntimeError("setting supported cooling mode requires sudo")

    command_options: list[list[str]] = []
    if mode == "high":
        command_options = [
            ["pmset", "-a", "powermode", "2"],
            ["pmset", "-a", "highpowermode", "1"],
        ]
    elif mode == "normal":
        command_options = [
            ["pmset", "-a", "powermode", "0"],
            ["pmset", "-a", "highpowermode", "0"],
        ]
    else:
        raise RuntimeError(f"unsupported cooling mode: {mode}")

    selected_command, error_text = try_pmset_commands(command_options)
    if not selected_command:
        raise RuntimeError(
            "High Power Mode is not available through pmset on this Mac or macOS build. "
            + (error_text or "")
        )

    if mode == "normal" and status.low_power_supported:
        run_command(["pmset", "-a", "lowpowermode", "0"])

    return read_cooling_status()


def print_cooling_text(status: CoolingStatus) -> None:
    print(f"supported cooling mode: {status.mode}")
    print(
        "High Power Mode: "
        + ("enabled" if status.high_power_enabled else "disabled" if status.high_power_supported else "unsupported")
    )
    print(
        "Low Power Mode: "
        + ("enabled" if status.low_power_enabled else "disabled" if status.low_power_supported else "unsupported")
    )


def print_cooling_json(status: CoolingStatus) -> None:
    print(
        json.dumps(
            {
                "supported_cooling": {
                    "mode": status.mode,
                    "high_power_supported": status.high_power_supported,
                    "high_power_enabled": status.high_power_enabled,
                    "low_power_supported": status.low_power_supported,
                    "low_power_enabled": status.low_power_enabled,
                }
            },
            indent=2,
        )
    )


def ensure_unsafe_opt_in(args: argparse.Namespace) -> None:
    if not args.i_understand_this_is_unsupported:
        raise RuntimeError(
            "add --i-understand-this-is-unsupported to use direct AppleSMC fan writes"
        )
    if os.geteuid() != 0:
        raise RuntimeError("direct AppleSMC fan writes require sudo")


def restore_apple_default() -> tuple[int | None, CoolingStatus]:
    if os.geteuid() != 0:
        raise RuntimeError("restoring Apple default cooling requires sudo")

    restored_fans: int | None = None
    try:
        with NativeFanBridge() as bridge:
            restored_fans = bridge.restore_auto()
    except NativeFanError:
        restored_fans = None

    status = set_supported_cooling("normal")
    return restored_fans, status


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Display fan RPM using a native AppleSMC and IOReport bridge."
    )
    parser.add_argument("--watch", type=float, metavar="SECS", help="Refresh every N seconds.")
    parser.add_argument("--json", action="store_true", help="Emit JSON.")
    parser.add_argument(
        "--cooling-status",
        action="store_true",
        help="Show the supported macOS cooling mode status.",
    )
    parser.add_argument(
        "--set-supported-cooling",
        choices=["high", "normal"],
        help=(
            "Use Apple-supported macOS power modes. "
            "'high' enables High Power Mode when supported; "
            "'normal' returns to default automatic behavior."
        ),
    )
    parser.add_argument(
        "--unsafe-force-fans-high",
        action="store_true",
        help=(
            "Experimental: set all fans to manual mode and target their max RPM "
            "through direct AppleSMC writes."
        ),
    )
    parser.add_argument(
        "--unsafe-restore-auto",
        action="store_true",
        help="Experimental: restore all fans to automatic control.",
    )
    parser.add_argument(
        "--restore-apple-default",
        action="store_true",
        help=(
            "Restore Apple-style default behavior: automatic fan control and normal "
            "supported cooling mode."
        ),
    )
    parser.add_argument(
        "--i-understand-this-is-unsupported",
        action="store_true",
        help="Required with the unsafe direct AppleSMC fan-write options.",
    )
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

    if args.restore_apple_default:
        try:
            restored_fans, status = restore_apple_default()
        except RuntimeError as exc:
            if args.json:
                print(json.dumps({"restored": False, "error": str(exc)}, indent=2))
            else:
                print(f"restore failed: {exc}")
            return 1

        if args.json:
            print(
                json.dumps(
                    {
                        "restored": True,
                        "restored_fans": restored_fans,
                        "supported_cooling": {
                            "mode": status.mode,
                            "high_power_supported": status.high_power_supported,
                            "high_power_enabled": status.high_power_enabled,
                            "low_power_supported": status.low_power_supported,
                            "low_power_enabled": status.low_power_enabled,
                        },
                    },
                    indent=2,
                )
            )
        else:
            print("restored Apple default cooling behavior")
            if restored_fans is not None:
                print(f"automatic fan control restored for {restored_fans} fan(s)")
            print_cooling_text(status)
        return 0

    if args.unsafe_force_fans_high or args.unsafe_restore_auto:
        try:
            ensure_unsafe_opt_in(args)
            with NativeFanBridge() as bridge:
                count = bridge.force_high() if args.unsafe_force_fans_high else bridge.restore_auto()
                fans, error = read_fans_from_connection(bridge)
        except (RuntimeError, NativeFanError) as exc:
            if args.json:
                print(json.dumps({"fans": [], "error": str(exc)}, indent=2))
            else:
                print(f"unsafe fan control failed: {exc}")
            return 1

        if args.json:
            print(
                json.dumps(
                    {
                        "updated_fans": count,
                        "fans": [asdict(fan) for fan in fans],
                        "error": error,
                    },
                    indent=2,
                )
            )
        else:
            action = "forced high" if args.unsafe_force_fans_high else "restored to auto"
            print(f"unsafe fan control: {action} for {count} fan(s)")
            print_text(fans, error)
        return 0

    if args.cooling_status or args.set_supported_cooling:
        try:
            status = (
                set_supported_cooling(args.set_supported_cooling)
                if args.set_supported_cooling
                else read_cooling_status()
            )
        except RuntimeError as exc:
            if args.json:
                print(json.dumps({"supported_cooling": None, "error": str(exc)}, indent=2))
            else:
                print(f"supported cooling unavailable: {exc}")
            return 1

        if args.json:
            print_cooling_json(status)
        else:
            print_cooling_text(status)
        return 0

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
