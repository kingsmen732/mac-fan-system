import Foundation

enum WidgetDataSource {
    static let defaultJSONPath =
        NSString(string: "~/Library/Application Support/MacFanSystem/fan_rpm.json")
            .expandingTildeInPath

    static func load() -> FanWidgetEntryData {
        let url = URL(fileURLWithPath: defaultJSONPath)
        guard
            let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(WidgetPayload.self, from: data)
        else {
            return FanWidgetEntryData(
                timestamp: .now,
                fans: [],
                error: "No exported fan data"
            )
        }

        let parsedDate = ISO8601DateFormatter().date(from: payload.timestamp) ?? .now
        return FanWidgetEntryData(
            timestamp: parsedDate,
            fans: payload.fans,
            error: payload.error
        )
    }
}
