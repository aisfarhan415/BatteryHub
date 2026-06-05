import Foundation

#if os(watchOS)
import WatchKit
import WatchConnectivity

final class WatchBatteryReporter {
    static let shared = WatchBatteryReporter()

    private var timer: Timer?

    private init() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        publishNow()

        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.publishNow()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(publishNowFromNotification),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func publishNowFromNotification() {
        publishNow()
    }

    func publishNow() {
        let device = WKInterfaceDevice.current()
        let levelFloat = device.batteryLevel
        let level = levelFloat >= 0 ? Int((levelFloat * 100).rounded()) : 100

        let chargingStatus: String
        switch device.batteryState {
        case .charging:
            chargingStatus = "charging"
        case .full:
            chargingStatus = "charged"
        default:
            chargingStatus = "discharging"
        }

        let watchName = device.name.isEmpty ? "Apple Watch" : device.name
        let stableId = watchName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)

        let payload = DeviceBattery(
            id: "watch_\(stableId)",
            name: watchName,
            type: "watch",
            batteryLevel: max(0, min(100, level)),
            chargingStatus: chargingStatus,
            timeRemaining: nil,
            lastUpdated: Date()
        )

        iCloudSyncManager.shared.updateDevice(payload)
        sendToPhone(payload: payload)
    }

    private func sendToPhone(payload: DeviceBattery) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = WatchSessionDelegateProxy.shared
            session.activate()
        }

        let context: [String: Any] = [
            "watchBatteryPayload": [
                "id": payload.id,
                "name": payload.name,
                "type": payload.type,
                "batteryLevel": payload.batteryLevel,
                "chargingStatus": payload.chargingStatus
            ]
        ]

        do {
            try session.updateApplicationContext(context)
        } catch {
            print("WatchConnectivity context update failed: \(error)")
        }

        if session.isReachable {
            session.sendMessage(context, replyHandler: nil) { error in
                print("WatchConnectivity sendMessage failed: \(error)")
            }
        }
    }
}

private final class WatchSessionDelegateProxy: NSObject, WCSessionDelegate {
    static let shared = WatchSessionDelegateProxy()
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
#endif
