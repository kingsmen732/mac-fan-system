# Mac Fan Widget

This folder contains a minimal WidgetKit scaffold for a macOS widget that displays fan RPM values produced by `main.py`.

## What the Python script does

Run the Python reader so it exports widget JSON:

```bash
sudo python3 main.py --watch 2 --widget-export
```

Default export path:

```text
~/Library/Application Support/MacFanSystem/fan_rpm.json
```

## What the widget expects

The widget reads a JSON payload shaped like this:

```json
{
  "timestamp": "2026-03-30T01:23:45",
  "fans": [
    { "index": 0, "rpm": 2318, "target_rpm": null, "min_rpm": null, "max_rpm": null, "mode": null },
    { "index": 1, "rpm": 2505, "target_rpm": null, "min_rpm": null, "max_rpm": null, "mode": null }
  ],
  "error": null
}
```

## How to use in Xcode

1. Install full Xcode if it is not already installed.
2. Create a new macOS app project.
3. Add a macOS Widget Extension target.
4. Copy the Swift files from this folder into the widget extension target.
5. Set the widget extension deployment target to a macOS version that supports desktop widgets.
6. Update `WidgetDataSource.defaultJSONPath` if you want a different file location.
7. Run the Python exporter in the background.
8. Build and add the widget to your desktop or Notification Center.

## Important limitation

For a production widget, the preferred Apple approach is an App Group container shared between the app and widget. This scaffold reads from a file path directly to keep the prototype simple.
