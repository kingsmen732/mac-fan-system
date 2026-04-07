import Foundation

enum FanControlMode: String, Codable, Equatable {
    case silent
    case boost

    var title: String {
        switch self {
        case .silent:
            return "Silent"
        case .boost:
            return "Boost"
        }
    }

    var subtitle: String {
        switch self {
        case .silent:
            return "Apple auto control"
        case .boost:
            return "Full fan speed"
        }
    }
}

struct WidgetFan: Codable, Identifiable, Equatable {
    let index: Int
    let rpm: Int
    let target_rpm: Int?
    let min_rpm: Int?
    let max_rpm: Int?
    let mode: String?

    var id: Int { index }

    var normalizedRPM: Double {
        guard let maximumRPM = max_rpm, maximumRPM > 0 else {
            return 0
        }
        let normalized = Double(rpm) / Double(maximumRPM)
        return Swift.min(Swift.max(normalized, 0.01), 1.0)
    }

    var rangeLabel: String {
        if let min = min_rpm, let max = max_rpm {
            return "\(min)-\(max) RPM"
        }
        return "Range unavailable"
    }

    var modeLabel: String {
        mode?.capitalized ?? "Auto"
    }
}

struct WidgetPayload: Codable, Equatable {
    let timestamp: String
    let fans: [WidgetFan]
    let error: String?
    let appliedMode: FanControlMode?
}

struct FanWidgetEntryData {
    let timestamp: Date
    let fans: [WidgetFan]
    let error: String?
    let controlMode: FanControlMode
    let appliedMode: FanControlMode?

    var averageRPM: Int {
        guard !fans.isEmpty else {
            return 0
        }
        return fans.map(\.rpm).reduce(0, +) / fans.count
    }

    var topFan: WidgetFan? {
        fans.max { lhs, rhs in
            lhs.rpm < rhs.rpm
        }
    }

    var subtitle: String {
        if let error {
            return error
        }
        if fans.isEmpty {
            return "Waiting for exported fan data"
        }
        return "\(fans.count) fan\(fans.count == 1 ? "" : "s") live"
    }
}

struct FanControlState: Codable, Equatable {
    let desiredMode: FanControlMode
}
