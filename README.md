# mac-fan-system

Safe-by-default Python utilities for reading Mac fan telemetry and managing supported macOS thermal controls on current MacBook Pros.

## Why this approach

macOS does not provide a stable public Python API for manually controlling MacBook fan RPM on current Apple Silicon machines. This project stays inside safer boundaries:

- Reads telemetry using built-in userland tools such as `ioreg` and `system_profiler`
- Reads official thermal state and Low Power Mode status through supported macOS interfaces
- Changes supported system thermal policy with `pmset` instead of poking undocumented fan controls
- Never disables SIP, patches kernel extensions, or writes directly to undocumented device interfaces
- Keeps fan control disabled unless you explicitly wire in an external tool you trust

That means the project is useful immediately for detection and monitoring, and it can delegate control only when you choose a backend that matches your Mac and your risk tolerance.

## What works today

- Identify the Mac model and platform
- Attempt to discover fan telemetry from `ioreg`
- Read the official process thermal state
- Read whether Low Power Mode is supported and enabled
- Enable or disable Low Power Mode on supported Macs
- Optionally call a user-supplied executable to request a fan speed change

## Important limitation

On recent Apple Silicon MacBooks, there may be no supported manual fan-control backend available at all. In that case, the supported control surface is the system power mode, and macOS continues to manage the actual fans.

## Install

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
```

## Usage

Show system and fan status:

```bash
mac-fan-system status
```

Show supported thermal policy status:

```bash
mac-fan-system mode status
```

Output JSON:

```bash
mac-fan-system status --json
```

Request a fan speed change through an external tool:

```bash
mac-fan-system set \
  --fan left \
  --rpm 3000 \
  --allow-external-control \
  --external-tool /path/to/your-fan-cli \
  --external-arg set \
  --external-arg --fan \
  --external-arg {fan} \
  --external-arg --rpm \
  --external-arg {rpm}
```

Notes:

- `--allow-external-control` is required so writes are always explicit
- `--external-tool` and `--external-arg` use `subprocess.run()` without a shell
- `{fan}` and `{rpm}` placeholders are replaced before execution

## Python example

```python
from mac_fan_system.control import ExternalToolController
from mac_fan_system.probes import MacFanProbe

probe = MacFanProbe()
snapshot = probe.snapshot()
print(snapshot.to_dict())

controller = ExternalToolController(
    executable="/path/to/your-fan-cli",
    arguments=["set", "--fan", "{fan}", "--rpm", "{rpm}"],
)
controller.set_speed(fan_id="left", rpm=3000, allow_external_control=True)
```

Enable Low Power Mode with the supported `pmset` interface:

```bash
sudo python3 -m mac_fan_system.cli mode set-low-power on
```

Disable Low Power Mode:

```bash
sudo python3 -m mac_fan_system.cli mode set-low-power off
```

## Safety guidance

- Prefer the built-in Low Power Mode path on current MacBook Pros
- Prefer read-only fan status checks unless you know your specific Mac supports manual control
- Never ship a default control backend that pokes undocumented kernel or SMC interfaces
- Treat external fan control as hardware-specific and test carefully
