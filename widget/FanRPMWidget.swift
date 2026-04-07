import SwiftUI
import WidgetKit

struct FanRPMWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: FanRPMEntry

    var body: some View {
        ZStack {
            background

            switch family {
            case .systemSmall:
                smallWidget
            default:
                mediumWidget
            }
        }
        .containerBackground(for: .widget) {
            background
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.09),
                    Color(red: 0.09, green: 0.11, blue: 0.14),
                    accentColor.opacity(0.42),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white.opacity(0.05))
                .padding(6)
        }
    }

    private var accentColor: Color {
        entry.payload.controlMode == .boost ? .orange : .mint
    }

    private var appliedModeTitle: String {
        (entry.payload.appliedMode ?? entry.payload.controlMode).title
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let topFan = entry.payload.topFan {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(topFan.rpm)")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("RPM")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))

                    Gauge(value: topFan.normalizedRPM) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(Gradient(colors: [accentColor, .white]))
                }
            } else {
                fallback
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(spacing: 10) {
                statCard(
                    title: "AVERAGE",
                    value: entry.payload.fans.isEmpty ? "--" : "\(entry.payload.averageRPM)",
                    detail: "RPM"
                )

                statCard(
                    title: "MODE",
                    value: appliedModeTitle,
                    detail: entry.payload.controlMode.subtitle
                )
            }

            if entry.payload.fans.isEmpty {
                fallback
            } else {
                VStack(spacing: 8) {
                    ForEach(entry.payload.fans.prefix(2)) { fan in
                        HStack(spacing: 10) {
                            Image(systemName: "fanblades.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(accentColor)

                            Text("Fan \(fan.index)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.82))

                            Spacer()

                            Text("\(fan.rpm) RPM")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white.opacity(0.08))
                        )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Mac Fan")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(appliedModeTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 10)

            Text(entry.date, style: .time)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
        }
    }

    private var fallback: some View {
        Text(entry.payload.subtitle)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.74))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.08))
            )
    }

    private func statCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text(detail)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.08))
        )
    }
}

struct FanRPMWidget: Widget {
    let kind: String = "FanRPMWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FanRPMProvider()) { entry in
            FanRPMWidgetView(entry: entry)
        }
        .configurationDisplayName("Mac Fan Widget")
        .description("A minimal desktop widget for Apple Silicon fan speed and cooling mode.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
