import SwiftUI
import WidgetKit

struct FanRPMEntry: TimelineEntry {
    let date: Date
    let fans: [WidgetFan]
    let error: String?
}

struct FanRPMProvider: TimelineProvider {
    func placeholder(in context: Context) -> FanRPMEntry {
        FanRPMEntry(
            date: .now,
            fans: [
                WidgetFan(index: 0, rpm: 2300, target_rpm: nil, min_rpm: nil, max_rpm: nil, mode: nil),
                WidgetFan(index: 1, rpm: 2500, target_rpm: nil, min_rpm: nil, max_rpm: nil, mode: nil),
            ],
            error: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FanRPMEntry) -> Void) {
        let payload = WidgetDataSource.load()
        completion(FanRPMEntry(date: payload.timestamp, fans: payload.fans, error: payload.error))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FanRPMEntry>) -> Void) {
        let payload = WidgetDataSource.load()
        let entry = FanRPMEntry(date: payload.timestamp, fans: payload.fans, error: payload.error)
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct FanRPMWidgetView: View {
    var entry: FanRPMProvider.Entry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.13, blue: 0.18), Color(red: 0.17, green: 0.20, blue: 0.26)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Fan RPM")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))

                if let error = entry.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(3)
                } else if entry.fans.isEmpty {
                    Text("No fan data")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    ForEach(entry.fans.prefix(2)) { fan in
                        HStack {
                            Text("Fan \(fan.index)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Text("\(fan.rpm)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.green)
                            Text("RPM")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                Spacer(minLength: 0)

                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding()
        }
    }
}

struct FanRPMWidget: Widget {
    let kind: String = "FanRPMWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FanRPMProvider()) { entry in
            FanRPMWidgetView(entry: entry)
        }
        .configurationDisplayName("Fan RPM")
        .description("Shows live Mac fan RPM values exported by the Python script.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
