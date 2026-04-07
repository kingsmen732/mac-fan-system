import Foundation

private let daemonMachServiceName = "com.bmithilesh.macfanwidget.daemon"

@main
struct MacFanWidgetDaemonMain {
    static func main() {
        let daemon = FanDaemonService()
        daemon.start()
        RunLoop.current.run()
    }
}

final class FanDaemonService: NSObject, NSXPCListenerDelegate, FanDaemonXPCProtocol {
    private let runtime = FanDaemonRuntime()
    private let listener = NSXPCListener(machServiceName: daemonMachServiceName)

    func start() {
        listener.delegate = self
        listener.resume()
        runtime.start()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: FanDaemonXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func fetchSnapshot(_ reply: @escaping (Data?, String?) -> Void) {
        let snapshot = runtime.fetchSnapshot()
        reply(snapshot.data, snapshot.error)
    }

    func setMode(_ rawMode: String, reply: @escaping (Bool, String?) -> Void) {
        let result = runtime.setMode(rawMode)
        reply(result.success, result.message)
    }
}

final class FanDaemonRuntime {
    private let maxFans = 8
    private let errorBufferSize = 256
    private let timestampFormatter = ISO8601DateFormatter()
    private let queue = DispatchQueue(label: "com.bmithilesh.macfanwidget.daemon.runtime")

    private var timer: DispatchSourceTimer?
    private var bridgeOpen = false

    func start() {
        refreshOnce()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.refreshOnce()
        }
        timer.resume()
        self.timer = timer
    }

    func fetchSnapshot() -> (data: Data?, error: String?) {
        queue.sync {
            if let data = try? Data(contentsOf: SharedContainer.snapshotURL) {
                return (data, nil)
            }

            let payload = WidgetPayload(
                timestamp: timestampFormatter.string(from: .now),
                fans: [],
                error: "The privileged fan daemon hasn't produced a sample yet.",
                appliedMode: nil
            )
            let data = (try? JSONEncoder().encode(payload)) ?? Data()
            return (data, nil)
        }
    }

    func setMode(_ rawMode: String) -> (success: Bool, message: String?) {
        queue.sync {
            guard let mode = FanControlMode(rawValue: rawMode) else {
                return (false, "Unknown cooling mode.")
            }

            do {
                try FanDataStore.writeControlState(FanControlState(desiredMode: mode))
            } catch {
                return (false, "Couldn't persist the requested fan mode.")
            }

            refreshOnce()

            let entry = FanDataStore.load()
            if let error = entry.error {
                return (false, error)
            }

            return (true, nil)
        }
    }

    private func refreshOnce() {
        let desiredMode = FanDataStore.loadControlState().desiredMode

        guard ensureBridgeOpen() else {
            writePayload(
                WidgetPayload(
                    timestamp: timestampFormatter.string(from: .now),
                    fans: [],
                    error: "The privileged fan daemon could not connect to AppleSMC.",
                    appliedMode: nil
                )
            )
            return
        }

        let controlError = applyDesiredMode(desiredMode)
        let payload = readPayload(
            desiredMode: desiredMode,
            appliedMode: controlError == nil ? desiredMode : nil,
            controlError: controlError
        )
        writePayload(payload)
    }

    private func ensureBridgeOpen() -> Bool {
        guard !bridgeOpen else {
            return true
        }

        var errorBuffer = Array(repeating: CChar(0), count: errorBufferSize)
        let result = errorBuffer.withUnsafeMutableBufferPointer { pointer in
            fan_bridge_open(pointer.baseAddress, errorBufferSize)
        }
        bridgeOpen = result == 0
        return bridgeOpen
    }

    private func applyDesiredMode(_ mode: FanControlMode) -> String? {
        var errorBuffer = Array(repeating: CChar(0), count: errorBufferSize)
        let result = errorBuffer.withUnsafeMutableBufferPointer { pointer in
            switch mode {
            case .boost:
                fan_bridge_force_high(pointer.baseAddress, errorBufferSize)
            case .silent:
                fan_bridge_restore_auto(pointer.baseAddress, errorBufferSize)
            }
        }

        guard result >= 0 else {
            let message = String(cString: errorBuffer).trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "The privileged fan daemon couldn't apply \(mode.title.lowercased()) mode." : message
        }

        return nil
    }

    private func readPayload(
        desiredMode: FanControlMode,
        appliedMode: FanControlMode?,
        controlError: String?
    ) -> WidgetPayload {
        var fansBuffer = Array(repeating: fan_info_t(), count: maxFans)
        var errorBuffer = Array(repeating: CChar(0), count: errorBufferSize)

        let count = fansBuffer.withUnsafeMutableBufferPointer { fansPointer in
            errorBuffer.withUnsafeMutableBufferPointer { errorPointer in
                fan_bridge_read(
                    fansPointer.baseAddress,
                    Int32(maxFans),
                    errorPointer.baseAddress,
                    errorBufferSize
                )
            }
        }

        let timestamp = timestampFormatter.string(from: .now)

        guard count > 0 else {
            let readError = String(cString: errorBuffer).trimmingCharacters(in: .whitespacesAndNewlines)
            let message = [controlError, readError.isEmpty ? nil : readError]
                .compactMap { $0 }
                .joined(separator: " ")
            return WidgetPayload(
                timestamp: timestamp,
                fans: [],
                error: message.isEmpty ? "No fan data available from the privileged fan daemon." : message,
                appliedMode: appliedMode
            )
        }

        let fans = fansBuffer.prefix(Int(count)).map { item in
            WidgetFan(
                index: Int(item.id),
                rpm: Int(item.actualRPM),
                target_rpm: item.targetRPM > 0 ? Int(item.targetRPM) : nil,
                min_rpm: item.minRPM > 0 ? Int(item.minRPM) : nil,
                max_rpm: item.maxRPM > 0 ? Int(item.maxRPM) : nil,
                mode: modeString(for: Int(item.mode))
            )
        }

        let postReadError = controlError ?? verifyControlState(desiredMode: desiredMode, fans: fans)

        return WidgetPayload(
            timestamp: timestamp,
            fans: fans,
            error: postReadError,
            appliedMode: postReadError == nil ? (appliedMode ?? desiredMode) : nil
        )
    }

    private func verifyControlState(desiredMode: FanControlMode, fans: [WidgetFan]) -> String? {
        guard !fans.isEmpty else {
            return nil
        }

        switch desiredMode {
        case .boost:
            let boostApplied = fans.allSatisfy { fan in
                guard
                    fan.mode?.lowercased() == "manual",
                    let target = fan.target_rpm,
                    let maximum = fan.max_rpm
                else {
                    return false
                }
                return abs(target - maximum) <= 50
            }
            return boostApplied
                ? nil
                : "Boost was requested, but macOS kept the fans out of full manual max mode."
        case .silent:
            let stillManual = fans.contains { $0.mode?.lowercased() == "manual" }
            return stillManual
                ? "Silent was requested, but manual fan control is still active."
                : nil
        }
    }

    private func writePayload(_ payload: WidgetPayload) {
        try? FanDataStore.write(payload)
    }

    private func modeString(for value: Int) -> String? {
        switch value {
        case 0:
            return "auto"
        case 1:
            return "manual"
        case 3:
            return "system"
        default:
            return value == 0 ? nil : String(value)
        }
    }
}
