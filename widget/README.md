# Mac Fan Widget

This repo now includes a hidden macOS menu bar app, a bundled background helper, and a WidgetKit extension in one release build.

## Local build

1. Install full Xcode.
2. Accept the Xcode license once:

```bash
sudo xcodebuild -license accept
```
3. Install XcodeGen:

```bash
brew install xcodegen
```

4. Generate the Xcode project:

```bash
xcodegen generate
```

5. Open `MacFanWidgetApp.xcodeproj` in Xcode.
6. Build and run the `MacFanWidgetApp` scheme once.
7. The app registers the bundled background helper and stays out of the Dock.
8. Add the installed widget from the macOS widget gallery to your desktop.

## Runtime model

The shipped product now works like this:

- the hidden menu bar app registers the bundled launch agent
- the launch agent keeps polling AppleSMC and applies `Silent` or `Boost`
- the widget and menu bar UI both read the same shared snapshot file

Shared snapshot fallback path for ad-hoc builds:

```text
~/Library/Application Support/MacFanSystem/fan_rpm.json
```

## Widget features

- Small and medium widget layouts
- Interactive `Silent` and `Boost` controls
- Menu bar companion instead of a normal Dock app
- Bundled background helper that can keep running after the UI app exits
- GitHub Actions packaging for a release `.app.zip` artifact

## GitHub Actions

The workflow at `.github/workflows/build-mac-widget.yml`:

- installs XcodeGen on a macOS runner
- generates `MacFanWidgetApp.xcodeproj`
- builds a release app bundle
- ad-hoc signs the app bundle
- uploads a zipped `.app` artifact
- publishes the zip to GitHub Releases when you push a tag like `v1.0.0`

## Release flow

Once your local Xcode build succeeds, you can publish a downloadable release asset with:

```bash
git add .
git commit -m "Buildable macOS widget app"
git push origin main
git tag v1.0.0
git push origin v1.0.0
```

That tag triggers GitHub Actions to build `Mac-Fan-Widget-macOS.zip` and attach it to the GitHub Release for that tag.

## Limitation

The code now prefers an App Group-style shared container, but direct downloadable builds from GitHub Releases still fall back to the user Application Support path unless you later add real App Group entitlements and signing for distribution under an Apple Developer team.

## Important Apple limitation

The desktop widget still ships inside a containing app bundle on macOS. This repo hides that container from the Dock and uses a menu bar extra plus bundled helper so it behaves much closer to "widget plus taskbar item" than "separate app window."
