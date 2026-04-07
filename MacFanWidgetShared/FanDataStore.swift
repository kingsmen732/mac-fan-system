import Foundation

enum SharedContainer {
    private static let fallbackDirectoryName = "MacFanSystem"
    private static let snapshotFileName = "fan_rpm.json"
    private static let controlFileName = "fan_control.json"

    private static var baseDirectoryURL: URL {
        URL(fileURLWithPath: "/Users/Shared", isDirectory: true)
            .appendingPathComponent(fallbackDirectoryName, isDirectory: true)
    }

    static var snapshotURL: URL {
        baseDirectoryURL.appendingPathComponent(snapshotFileName)
    }

    static var controlURL: URL {
        baseDirectoryURL.appendingPathComponent(controlFileName)
    }

    static func ensureParentDirectory() throws {
        try FileManager.default.createDirectory(
            at: baseDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}

enum FanDataStore {
    private static let formatter = ISO8601DateFormatter()

    static func load() -> FanWidgetEntryData {
        let controlState = loadControlState()

        if let payload = decodePayload(at: SharedContainer.snapshotURL) {
            return buildEntry(from: payload, controlState: controlState)
        }

        if let sampleURL = Bundle.main.url(forResource: "widget-sample", withExtension: "json"),
           let payload = decodePayload(at: sampleURL)
        {
            return buildEntry(from: payload, controlState: controlState)
        }

        return FanWidgetEntryData(
            timestamp: .now,
            fans: [],
            error: "The bundled fan monitor is starting. Open the menu bar extra if this persists.",
            controlMode: controlState.desiredMode,
            appliedMode: nil
        )
    }

    static func write(_ payload: WidgetPayload) throws {
        try SharedContainer.ensureParentDirectory()
        let data = try JSONEncoder().encode(payload)
        try data.write(to: SharedContainer.snapshotURL, options: .atomic)
    }

    static func loadControlState() -> FanControlState {
        guard
            let data = try? Data(contentsOf: SharedContainer.controlURL),
            let state = try? JSONDecoder().decode(FanControlState.self, from: data)
        else {
            return FanControlState(desiredMode: .silent)
        }
        return state
    }

    static func writeControlState(_ state: FanControlState) throws {
        try SharedContainer.ensureParentDirectory()
        let data = try JSONEncoder().encode(state)
        try data.write(to: SharedContainer.controlURL, options: .atomic)
    }

    private static func decodePayload(at url: URL) -> WidgetPayload? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetPayload.self, from: data)
    }

    private static func buildEntry(from payload: WidgetPayload, controlState: FanControlState) -> FanWidgetEntryData {
        let parsedDate = formatter.date(from: payload.timestamp) ?? .now
        return FanWidgetEntryData(
            timestamp: parsedDate,
            fans: payload.fans,
            error: payload.error,
            controlMode: controlState.desiredMode,
            appliedMode: payload.appliedMode
        )
    }
}
