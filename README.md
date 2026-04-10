# mac-fan-system

Python CLI for reading Apple Silicon MacBook Pro fan RPM directly from `AppleSMC`, with an optional experimental manual-control path.

## What this does

- Reads live fan RPM without depending on `mactop`
- Uses a native Objective-C/C bridge in [`native/fan_bridge.m`](./native/fan_bridge.m) and [`native/smc_bridge.c`](./native/smc_bridge.c)
- Prints fan RPM in text or JSON
- Supports watch mode for realtime terminal output
- Exposes Apple-supported cooling mode checks through `pmset`
- Keeps the unsupported direct fan-write path explicit and opt-in

## Local build

Build the native bridge:

```bash
zsh build_native.sh
```

Run once:

```bash
python3 main.py
```

Run as JSON:

```bash
python3 main.py --json
```

Run in watch mode:

```bash
python3 main.py --watch 1
```

## Homebrew package

This repo includes a development Brew formula at [`Formula/mac-fan-system.rb`](./Formula/mac-fan-system.rb).

Install from the local checkout:

```bash
brew install --HEAD ./Formula/mac-fan-system.rb
```

For public users, the clean setup is:

1. Keep this repository as the source repository.
2. Create a separate Homebrew tap repository named `homebrew-mac-fan-system` or `homebrew-tap`.
3. Publish tagged releases from this source repo.
4. Put the generated stable formula for each tag into the tap repo.

The public formula should point at a tagged GitHub release tarball, not `--HEAD`.

This source repo now includes:

- CI at [ci.yml](./.github/workflows/ci.yml)
- a tag release workflow at [release.yml](./.github/workflows/release.yml)
- a formula renderer at [render_formula.py](./scripts/render_formula.py)

When you push a tag like `v0.1.0`, the release workflow uploads:

- `mac-fan-system-v0.1.0.tar.gz`
- `checksums.txt`
- `mac-fan-system.rb`

That generated `mac-fan-system.rb` is the file you copy into your public tap repo.

After the tap repo is live, public install becomes:

```bash
brew tap kingsmen732/mac-fan-system
brew install mac-fan-system
```

## CLI usage

Read fan RPM:

```bash
mac-fan-system
```

Read JSON:

```bash
mac-fan-system --json
```

Watch continuously:

```bash
mac-fan-system --watch 1
```

Show Apple-supported cooling status:

```bash
mac-fan-system --cooling-status
```

Use Apple-supported higher cooling mode when available:

```bash
sudo mac-fan-system --set-supported-cooling high
```

Return to Apple’s normal supported mode:

```bash
sudo mac-fan-system --set-supported-cooling normal
```

Experimental direct fan max mode:

```bash
sudo mac-fan-system --unsafe-force-fans-high --i-understand-this-is-unsupported
```

Restore automatic fan control:

```bash
sudo mac-fan-system --unsafe-restore-auto --i-understand-this-is-unsupported
```

## Example output

```text
fan0: 2326 rpm (auto, 2317-7826)
fan1: 2500 rpm (auto, 2317-7826)
```

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

- The CLI first checks `MAC_FAN_SYSTEM_NATIVE_LIB`; Brew uses that to point at the installed dylib.
- If that variable is unset, the CLI falls back to the local `build/libfanbridge.dylib`.
- Direct max-fan writes are undocumented AppleSMC writes and should be treated as experimental.
- On restricted environments, `AppleSMC` access may fail even if the same code works in a normal Terminal session.
- The clean public Homebrew path is a separate tap repo plus tagged releases from this source repo.
