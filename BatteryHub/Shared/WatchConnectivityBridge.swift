import Foundation

#if os(iOS)
import WatchConnectivity
import Combine

final class WatchConnectivityBridge: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityBridge()
    let statusStore = WatchLinkStatusStore()

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.statusStore.isSessionReachable = session.isReachable
            self.statusStore.activationState = activationState.rawValue
            self.statusStore.lastError = error?.localizedDescription
        }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        applyContext(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        applyContext(message)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.statusStore.isSessionReachable = session.isReachable
        }
    }

    private func applyContext(_ context: [String: Any]) {
        guard let payload = context["watchBatteryPayload"] as? [String: Any] else { return }
        guard let id = payload["id"] as? String,
              let name = payload["name"] as? String,
              let type = payload["type"] as? String,
              let level = payload["batteryLevel"] as? Int,
              let charging = payload["chargingStatus"] as? String else { return }

        let watchDevice = DeviceBattery(
            id: id,
            name: name,
            type: type,
            batteryLevel: max(0, min(100, level)),
            chargingStatus: charging,
            timeRemaining: nil,
            lastUpdated: Date()
        )

        DispatchQueue.main.async {
            self.statusStore.lastPayloadAt = Date()
            self.statusStore.lastWatchName = name
            self.statusStore.lastWatchLevel = level
            iCloudSyncManager.shared.updateDevice(watchDevice)
        }
    }
}

final class WatchLinkStatusStore: ObservableObject {
    @Published var isSessionReachable: Bool = false
    @Published var activationState: Int = 0
    @Published var lastPayloadAt: Date?
    @Published var lastWatchName: String?
    @Published var lastWatchLevel: Int?
    @Published var lastError: String?
}

#endif
