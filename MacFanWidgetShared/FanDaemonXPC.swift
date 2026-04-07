import Foundation

@objc(FanDaemonXPCProtocol)
protocol FanDaemonXPCProtocol {
    func fetchSnapshot(_ reply: @escaping (Data?, String?) -> Void)
    func setMode(_ rawMode: String, reply: @escaping (Bool, String?) -> Void)
}
