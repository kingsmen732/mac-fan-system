#!/usr/bin/env python3
"""
Fan RPM monitor that mirrors mactop's SMC logic as closely as possible.

This version follows metaspartan/mactop's C SMC layer:
- exact SMCKeyData_t-style ctypes structs
- SMC_CMD_READ_KEYINFO = 9
- SMC_CMD_READ_BYTES = 5
- float decoding matching SMCGetFloatValue()
"""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import json
import os
import struct
import time
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


_iokit = ctypes.cdll.LoadLibrary(ctypes.util.find_library("IOKit"))

io_object_t = ctypes.c_uint
io_connect_t = ctypes.c_uint
kern_return_t = ctypes.c_int
CFMutableDictRef = ctypes.c_void_p

kIOMasterPortDefault = ctypes.c_uint(0)
kIOReturnSuccess = 0

KERNEL_INDEX_SMC = 2
SMC_CMD_READ_BYTES = 5
SMC_CMD_READ_INDEX = 8
SMC_CMD_READ_KEYINFO = 9


class SMCKeyDataVers(ctypes.Structure):
    _fields_ = [
        ("major", ctypes.c_char),
        ("minor", ctypes.c_char),
        ("build", ctypes.c_char),
        ("reserved", ctypes.c_char * 1),
        ("release", ctypes.c_ushort),
    ]


class SMCKeyDataPLimitData(ctypes.Structure):
    _fields_ = [
        ("version", ctypes.c_ushort),
        ("length", ctypes.c_ushort),
        ("cpuPLimit", ctypes.c_uint),
        ("gpuPLimit", ctypes.c_uint),
        ("memPLimit", ctypes.c_uint),
    ]


class SMCKeyDataKeyInfo(ctypes.Structure):
    _fields_ = [
        ("dataSize", ctypes.c_uint),
        ("dataType", ctypes.c_uint),
        ("dataAttributes", ctypes.c_char),
    ]


SMCBytes = ctypes.c_char * 32


class SMCKeyData(ctypes.Structure):
    _fields_ = [
        ("key", ctypes.c_uint),
        ("vers", SMCKeyDataVers),
        ("pLimitData", SMCKeyDataPLimitData),
        ("keyInfo", SMCKeyDataKeyInfo),
        ("result", ctypes.c_char),
        ("status", ctypes.c_char),
        ("data8", ctypes.c_char),
        ("data32", ctypes.c_uint),
        ("bytes", SMCBytes),
    ]


@dataclass
class FanRPM:
    index: int
    rpm: int
    target_rpm: int | None = None
    min_rpm: int | None = None
    max_rpm: int | None = None
    mode: str | None = None


DEFAULT_WIDGET_EXPORT_PATH = (
    Path.home() / "Library" / "Application Support" / "MacFanSystem" / "fan_rpm.json"
)


def key_to_uint(key: str) -> int:
    key = key[:4].ljust(4, "\0")
    return (
        (ord(key[0]) << 24)
        | (ord(key[1]) << 16)
        | (ord(key[2]) << 8)
        | ord(key[3])
    )


def uint_to_fourcc(value: int) -> str:
    return struct.pack(">I", value).decode("ascii", errors="replace")


class AppleSMCError(RuntimeError):
    pass


class AppleSMC:
    def __init__(self) -> None:
        self.conn = io_connect_t(0)

    def __enter__(self) -> "AppleSMC":
        self.open()
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def open(self) -> None:
        _iokit.IOServiceMatching.restype = CFMutableDictRef
        _iokit.IOServiceMatching.argtypes = [ctypes.c_char_p]
        matching = _iokit.IOServiceMatching(b"AppleSMC")

        _iokit.IOServiceGetMatchingService.restype = io_object_t
        _iokit.IOServiceGetMatchingService.argtypes = [ctypes.c_uint, CFMutableDictRef]
        service = _iokit.IOServiceGetMatchingService(kIOMasterPortDefault, matching)
        if not service:
            raise AppleSMCError("AppleSMC service not found")

        _iokit.IOServiceOpen.restype = kern_return_t
        _iokit.IOServiceOpen.argtypes = [
            io_object_t,
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.POINTER(io_connect_t),
        ]
        _iokit.mach_task_self.restype = ctypes.c_uint

        result = _iokit.IOServiceOpen(
            service,
            _iokit.mach_task_self(),
            1,
            ctypes.byref(self.conn),
        )
        _iokit.IOObjectRelease(service)

        if result != kIOReturnSuccess:
            raise AppleSMCError(f"IOServiceOpen failed: 0x{result & 0xFFFFFFFF:08x}")

    def close(self) -> None:
        if self.conn.value:
            _iokit.IOServiceClose(self.conn)
            self.conn.value = 0

    def call(self, input_struct: SMCKeyData) -> tuple[int, SMCKeyData]:
        output_struct = SMCKeyData()
        input_size = ctypes.c_size_t(ctypes.sizeof(SMCKeyData))
        output_size = ctypes.c_size_t(ctypes.sizeof(SMCKeyData))

        _iokit.IOConnectCallStructMethod.restype = kern_return_t
        _iokit.IOConnectCallStructMethod.argtypes = [
            io_connect_t,
            ctypes.c_uint,
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_size_t),
        ]

        result = _iokit.IOConnectCallStructMethod(
            self.conn,
            KERNEL_INDEX_SMC,
            ctypes.byref(input_struct),
            input_size,
            ctypes.byref(output_struct),
            ctypes.byref(output_size),
        )
        return result, output_struct

    def get_key_info(self, key: str) -> SMCKeyDataKeyInfo | None:
        input_struct = SMCKeyData()
        input_struct.key = key_to_uint(key)
        input_struct.data8 = bytes([SMC_CMD_READ_KEYINFO])
        result, output_struct = self.call(input_struct)
        if result != kIOReturnSuccess:
            return None
        if ord(output_struct.result or b"\0") != 0:
            return None
        return output_struct.keyInfo

    def read_key(self, key: str) -> tuple[str | None, bytes | None]:
        key_info = self.get_key_info(key)
        if key_info is None or key_info.dataSize == 0:
            return None, None

        input_struct = SMCKeyData()
        input_struct.key = key_to_uint(key)
        input_struct.keyInfo.dataSize = key_info.dataSize
        input_struct.data8 = bytes([SMC_CMD_READ_BYTES])
        result, output_struct = self.call(input_struct)
        if result != kIOReturnSuccess:
            return None, None
        if ord(output_struct.result or b"\0") != 0:
            return None, None

        data_type = uint_to_fourcc(key_info.dataType).rstrip("\x00 ")
        raw = bytes(output_struct.bytes[: key_info.dataSize])
        return data_type, raw


def decode_uint8(raw: bytes | None) -> int | None:
    if not raw:
        return None
    return raw[0]


def decode_float(data_type: str | None, raw: bytes | None) -> float | None:
    if not data_type or not raw:
        return None
    try:
        if data_type == "flt" and len(raw) >= 4:
            return struct.unpack("f", raw[:4])[0]
        if data_type == "fpe2" and len(raw) >= 2:
            return struct.unpack(">H", raw[:2])[0] / 4.0
    except Exception:
        return None
    return None


def decode_mode(raw: bytes | None) -> str | None:
    value = decode_uint8(raw)
    if value is None:
        return None
    if value == 0:
        return "auto"
    if value == 1:
        return "manual"
    if value == 3:
        return "system"
    return str(value)


def read_fans() -> tuple[list[FanRPM], str | None]:
    try:
        with AppleSMC() as smc:
            _, raw_count = smc.read_key("FNum")
            fan_count = decode_uint8(raw_count)
            if not fan_count:
                fan_count = 2

            fans: list[FanRPM] = []
            for index in range(fan_count):
                actual_type, actual_raw = smc.read_key(f"F{index}Ac")
                actual = decode_float(actual_type, actual_raw)
                if actual is None:
                    continue

                target_type, target_raw = smc.read_key(f"F{index}Tg")
                min_type, min_raw = smc.read_key(f"F{index}Mn")
                max_type, max_raw = smc.read_key(f"F{index}Mx")
                _, mode_raw = smc.read_key(f"F{index}Md")

                fans.append(
                    FanRPM(
                        index=index,
                        rpm=int(round(actual)),
                        target_rpm=(
                            int(round(decode_float(target_type, target_raw)))
                            if decode_float(target_type, target_raw) is not None
                            else None
                        ),
                        min_rpm=(
                            int(round(decode_float(min_type, min_raw)))
                            if decode_float(min_type, min_raw) is not None
                            else None
                        ),
                        max_rpm=(
                            int(round(decode_float(max_type, max_raw)))
                            if decode_float(max_type, max_raw) is not None
                            else None
                        ),
                        mode=decode_mode(mode_raw),
                    )
                )
            return fans, None
    except AppleSMCError as exc:
        return [], str(exc)


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


def export_widget_payload(
    fans: list[FanRPM],
    error: str | None,
    export_path: Path,
) -> None:
    export_path.parent.mkdir(parents=True, exist_ok=True)
    payload = build_payload(fans, error)
    export_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Display fan RPM using mactop-style SMC calls.")
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

    try:
        while True:
            fans, error = read_fans()
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

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
