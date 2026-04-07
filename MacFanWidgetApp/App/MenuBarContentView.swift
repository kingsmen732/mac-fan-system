import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var backend: FanBackendService

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.09),
                    Color(red: 0.09, green: 0.11, blue: 0.14),
                    backend.entry.controlMode == .boost ? Color.orange.opacity(0.34) : Color.mint.opacity(0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 16) {
                header
                modePicker
                stats

                if let message = backend.helperStatusMessage ?? backend.entry.error {
                    Text(message)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .overlay(.white.opacity(0.10))

                Button("Quit") {
                    Task {
                        await backend.quitApplication()
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.80))
                .buttonStyle(.plain)
                .disabled(backend.authInFlight)
            }
            .padding(18)
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mac Fan")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text((backend.entry.appliedMode ?? backend.entry.controlMode).subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer()

            Text(backend.entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            modeButton(for: .silent)
            modeButton(for: .boost)
        }
    }

    private var stats: some View {
        VStack(spacing: 10) {
            summaryCard

            if backend.entry.fans.isEmpty {
                emptyState
            } else {
                ForEach(backend.entry.fans.prefix(2)) { fan in
                    HStack(spacing: 10) {
                        Image(systemName: "fanblades.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(backend.entry.controlMode == .boost ? .orange : .mint)

                        Text("Fan \(fan.index)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.84))

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
    }

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AVERAGE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))

                Text(backend.entry.fans.isEmpty ? "--" : "\(backend.entry.averageRPM)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            Text("RPM")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.08))
        )
    }

    private var emptyState: some View {
        Text(backend.entry.subtitle)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.08))
            )
    }

    private func modeButton(for mode: FanControlMode) -> some View {
        let isActive = backend.entry.controlMode == mode

        return Button {
            Task {
                await backend.setControlMode(mode)
            }
        } label: {
            Text(mode.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? Color.black.opacity(0.84) : .white.opacity(0.88))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isActive ? Color.white : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .disabled(backend.authInFlight)
    }
}
