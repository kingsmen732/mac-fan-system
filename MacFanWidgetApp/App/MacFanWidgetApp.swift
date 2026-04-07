import SwiftUI

@main
struct MacFanWidgetApp: App {
    @StateObject private var backend = FanBackendService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(backend)
        } label: {
            MenuBarLabelView()
                .environmentObject(backend)
        }
        .menuBarExtraStyle(.window)
    }
}
