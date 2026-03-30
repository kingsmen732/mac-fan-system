import Foundation

struct WidgetFan: Codable, Identifiable {
    let index: Int
    let rpm: Int
    let target_rpm: Int?
    let min_rpm: Int?
    let max_rpm: Int?
    let mode: String?

    var id: Int { index }
}

struct WidgetPayload: Codable {
    let timestamp: String
    let fans: [WidgetFan]
    let error: String?
}

struct FanWidgetEntryData {
    let timestamp: Date
    let fans: [WidgetFan]
    let error: String?
}
