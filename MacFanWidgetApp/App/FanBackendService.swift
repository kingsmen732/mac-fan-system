import AppKit
import Foundation
import LocalAuthentication
import ServiceManagement
import WidgetKit

@MainActor
final class FanBackendService: ObservableObject {
    @Published private(set) var entry = FanDataStore.load()
    @Published private(set) var helperStatusMessage: String?
    @Published private(set) var authInFlight = false

    private let helperService = SMAppService.daemon(plistName: "com.bmithilesh.macfanwidget.daemon.plist")
    private let daemonClient = FanDaemonClient()
    private var pollTask: Task<Void, Never>?

    init() {
        registerHelperIfNeeded()
        pollTask = Task {
            await runLoop()
        }
    }

    deinit {
        pollTask?.cancel()
    }

    func setControlMode(_ mode: FanControlMode) async {
        guard await authenticate(reason: authenticationReason(for: mode)) else {
            return
        }

        do {
            try await daemonClient.setMode(mode)
            if let payload = try? await daemonClient.fetchSnapshotPayload() {
                try? FanDataStore.write(payload)
            }
            entry = FanDataStore.load()
            WidgetCenter.shared.reloadTimelines(ofKind: "FanRPMWidget")
        } catch {
            helperStatusMessage = "Couldn't set \(mode.title.lowercased()) mode: \(error.localizedDescription)"
        }
    }

    func quitApplication() async {
        guard await authenticate(reason: "Authenticate to quit Mac Fan.") else {
            return
        }

        NSApplication.shared.terminate(nil)
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await refreshFromDaemon()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func refresh() {
        entry = FanDataStore.load()
    }

    private func refreshFromDaemon() async {
        do {
            let payload = try await daemonClient.fetchSnapshotPayload()
            try? FanDataStore.write(payload)
            helperStatusMessage = nil
            refresh()
        } catch {
            helperStatusMessage = daemonStatusMessage(for: error)
            refresh()
        }
    }

    private func authenticationReason(for mode: FanControlMode) -> String {
        switch mode {
        case .boost:
            return "Authenticate to enable Boost mode and request maximum fan speed."
        case .silent:
            return "Authenticate to return fan control to Apple's automatic mode."
        }
    }

    private func authenticate(reason: String) async -> Bool {
        if authInFlight {
            return false
        }

        authInFlight = true
        defer { authInFlight = false }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            helperStatusMessage = authError?.localizedDescription
                ?? "This Mac can't authenticate with Touch ID or your password right now."
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            if success {
                helperStatusMessage = nil
            }
            return success
        } catch {
            helperStatusMessage = error.localizedDescription
            return false
        }
    }

    private func registerHelperIfNeeded() {
        do {
            switch helperService.status {
            case .enabled:
                helperStatusMessage = nil
            case .requiresApproval:
                try helperService.register()
                helperStatusMessage = "Allow the privileged fan daemon in Login Items and Background Items."
            case .notRegistered:
                try helperService.register()
                helperStatusMessage = "macOS is registering the privileged fan daemon. If this is an ad hoc build, the daemon may still remain unavailable."
            case .notFound:
                helperStatusMessage = "Bundled privileged fan daemon is missing from this build."
            @unknown default:
                helperStatusMessage = "Privileged daemon status is unavailable on this macOS build."
            }
        } catch {
            helperStatusMessage = "Couldn't register the privileged fan daemon: \(error.localizedDescription)"
        }
    }

    private func daemonStatusMessage(for error: Error) -> String {
        if let daemonError = error as? FanDaemonClientError {
            switch daemonError {
            case .connectionUnavailable:
                return "The privileged fan daemon is unavailable. This local build is likely ad hoc signed, so macOS won't install the daemon as a real privileged service."
            case .invalidSnapshot, .timedOut:
                return daemonError.localizedDescription
            }
        }
        return "The privileged fan daemon couldn't provide fan data: \(error.localizedDescription)"
    }
}
