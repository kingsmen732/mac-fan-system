import SwiftUI

struct MenuBarLabelView: View {
    @EnvironmentObject private var backend: FanBackendService

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "fanblades.fill")
                .foregroundStyle(backend.entry.controlMode == .boost ? .orange : .mint)

            if let topFan = backend.entry.topFan {
                Text("\(topFan.rpm)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            } else {
                Text("--")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
        }
    }
}
