# mac-fan-system

Native fan RPM monitoring for current Apple Silicon MacBook Pros, with a shipped macOS menu bar app + widget bundle and a separate Python CLI for development diagnostics.

## What this does

- Reads fan RPM directly from `AppleSMC`
- Uses the same fan key family `mactop` uses: `FNum`, `F%dAc`, `F%dMn`, `F%dMx`, `F%dTg`, `F%dMd`
- Does not depend on `mactop`
- Prints only fan data
- Can report and change Apple-supported cooling mode when macOS exposes it
- Includes a generated macOS menu bar app + WidgetKit extension path via XcodeGen and GitHub Actions
- Ships a bundled background helper inside the macOS app so the release does not need Python at runtime
- Exposes two built-in UI modes in the shipped app and widget: `Silent` and `Boost`

The native fan reads happen in:

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

## Shipped app build

Generate and build the installable macOS menu bar app and widget locally:

```bash
brew install xcodegen
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project MacFanWidgetApp.xcodeproj \
  -scheme MacFanWidgetApp \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

The shipped product now runs a bundled launch agent inside the app package. The menu bar UI only registers that helper and writes control state, so Python is no longer required after install and the backend can continue after the UI app exits.

## Python dev tools

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
- The shipped app tries to use an App Group-style shared container when available and falls back to the standard user Application Support path for direct downloadable builds that are not provisioned with App Group entitlements.
- The shipped UI is intentionally minimal: no manual refresh, no layout toggle, and no visible file-path plumbing.
- If you test from a restricted environment, `AppleSMC` access may fail even though the same code works fine in your normal Terminal session.
