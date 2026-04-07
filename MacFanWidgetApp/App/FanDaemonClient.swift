import Foundation

private let daemonMachServiceName = "com.bmithilesh.macfanwidget.daemon"
private let daemonRequestTimeoutNanoseconds: UInt64 = 3_000_000_000

enum FanDaemonClientError: LocalizedError {
    case connectionUnavailable
    case invalidSnapshot
    case timedOut

    var errorDescription: String? {
        switch self {
        case .connectionUnavailable:
            return "The privileged fan daemon is unavailable."
        case .invalidSnapshot:
            return "The privileged fan daemon returned invalid telemetry."
        case .timedOut:
            return "The privileged fan daemon didn't respond in time."
        }
    }
}

final class FanDaemonClient {
    private func connection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: daemonMachServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanDaemonXPCProtocol.self)
        connection.resume()
        return connection
    }

    func setMode(_ mode: FanControlMode) async throws {
        let result: (Bool, String?) = try await performRequest { proxy, resume in
            proxy.setMode(mode.rawValue) { success, message in
                resume(.success((success, message)))
            }
        }

        if result.0 {
            return
        }

        throw NSError(domain: "MacFanWidgetDaemon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: result.1 ?? "The privileged fan daemon rejected the mode change."
        ])
    }

    func fetchSnapshotPayload() async throws -> WidgetPayload {
        let snapshot: (Data?, String?) = try await performRequest { proxy, resume in
            proxy.fetchSnapshot { data, error in
                resume(.success((data, error)))
            }
        }

        if let error = snapshot.1 {
            throw NSError(domain: "MacFanWidgetDaemon", code: 2, userInfo: [
                NSLocalizedDescriptionKey: error
            ])
        }

        guard
            let data = snapshot.0,
            let payload = try? JSONDecoder().decode(WidgetPayload.self, from: data)
        else {
            throw FanDaemonClientError.invalidSnapshot
        }
        return payload
    }

    private func performRequest<T>(
        _ body: @escaping (FanDaemonXPCProtocol, @escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        let connection = connection()

        return try await withCheckedThrowingContinuation { continuation in
            let state = XPCRequestState(continuation: continuation, connection: connection)

            connection.interruptionHandler = {
                state.resume(with: .failure(FanDaemonClientError.connectionUnavailable))
            }
            connection.invalidationHandler = {
                state.resume(with: .failure(FanDaemonClientError.connectionUnavailable))
            }

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                state.resume(with: .failure(error))
            }) as? FanDaemonXPCProtocol else {
                state.resume(with: .failure(FanDaemonClientError.connectionUnavailable))
                return
            }

            Task.detached {
                try? await Task.sleep(nanoseconds: daemonRequestTimeoutNanoseconds)
                state.resume(with: .failure(FanDaemonClientError.timedOut))
            }

            body(proxy) { result in
                state.resume(with: result)
            }
        }
    }
}

private final class XPCRequestState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var connection: NSXPCConnection?

    init(continuation: CheckedContinuation<Value, Error>, connection: NSXPCConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func resume(with result: Result<Value, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }

        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        lock.unlock()

        connection?.invalidate()

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
