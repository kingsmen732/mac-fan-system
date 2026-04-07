# mac-fan-system

Native fan RPM monitoring for current Apple Silicon MacBook Pros, with a Python CLI on top of a small C/Objective-C bridge.

## What this does

- Reads fan RPM directly from `AppleSMC`
- Uses the same fan key family `mactop` uses: `FNum`, `F%dAc`, `F%dMn`, `F%dMx`, `F%dTg`, `F%dMd`
- Does not depend on `mactop`
- Prints only fan data
- Can report and change Apple-supported cooling mode when macOS exposes it
- Can export widget JSON for the macOS widget scaffold in [`widget/`](./widget)

The Python layer is just the UI and JSON/export wrapper. The actual fan reads happen in:

- [`native/smc_bridge.c`](./native/smc_bridge.c)
- [`native/fan_bridge.m`](./native/fan_bridge.m)

## Build

```bash
zsh build_native.sh
```

This produces:

```text
build/libfanbridge.dylib
```

## Usage

Print fan RPM once:

```bash
python3 main.py
```

Print JSON once:

```bash
python3 main.py --json
```

Watch live fan RPM:

```bash
python3 main.py --watch 1
```

Show Apple-supported cooling mode status:

```bash
python3 main.py --cooling-status
```

Enable the safest supported "more cooling" mode:

```bash
sudo python3 main.py --set-supported-cooling high
```

Return to normal automatic behavior:

```bash
sudo python3 main.py --set-supported-cooling normal
```

Experimental direct fan max mode:

```bash
sudo python3 main.py --unsafe-force-fans-high --i-understand-this-is-unsupported
```

Restore automatic fan control:

```bash
sudo python3 main.py --unsafe-restore-auto --i-understand-this-is-unsupported
```

Export widget JSON while watching:

```bash
python3 main.py --watch 2 --widget-export
```

## Example output

```json
{
  "fans": [
    {
      "index": 0,
      "rpm": 2326,
      "target_rpm": 2317,
      "min_rpm": 2317,
      "max_rpm": 7826,
      "mode": "auto"
    },
    {
      "index": 1,
      "rpm": 2500,
      "target_rpm": 2502,
      "min_rpm": 2317,
      "max_rpm": 7826,
      "mode": "auto"
    }
  ]
}
```

## Notes

- `main.py` keeps the native bridge open during `--watch` mode so reads stay stable.
- The bridge tries the broader `IOReport` setup as a best-effort warm-up, but live fan RPM comes from direct SMC keys.
- Directly forcing fan RPM to max is not exposed by Apple as a supported macOS interface. The safe path in this project is `High Power Mode` when the Mac advertises `highpowermode` support through `pmset`.
- The `--unsafe-force-fans-high` and `--unsafe-restore-auto` commands use undocumented AppleSMC writes. They are intentionally opt-in, require `sudo`, and should be treated as experimental.
- If you test from a restricted environment, `AppleSMC` access may fail even though the same code works fine in your normal Terminal session.
