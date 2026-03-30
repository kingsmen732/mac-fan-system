# mac-fan-system

Native fan RPM monitoring for current Apple Silicon MacBook Pros, with a Python CLI on top of a small C/Objective-C bridge.

## What this does

- Reads fan RPM directly from `AppleSMC`
- Uses the same fan key family `mactop` uses: `FNum`, `F%dAc`, `F%dMn`, `F%dMx`, `F%dTg`, `F%dMd`
- Does not depend on `mactop`
- Prints only fan data
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
- If you test from a restricted environment, `AppleSMC` access may fail even though the same code works fine in your normal Terminal session.
