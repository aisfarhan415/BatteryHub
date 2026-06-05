import Foundation

#if os(iOS)
import UIKit

final class MobileBatteryReporter {
    static let shared = MobileBatteryReporter()

    private var timer: Timer?

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        publishNow()

        // Keep local iPhone/iPad battery in sync to iCloud periodically.
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.publishNow()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(publishNowFromNotification),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(publishNowFromNotification),
            name: UIDevice.batteryStateDidChangeNotification,
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
        let device = UIDevice.current
        let levelFloat = device.batteryLevel
        let level = levelFloat >= 0 ? Int((levelFloat * 100).rounded()) : 100

        let type: String
        switch device.userInterfaceIdiom {
        case .pad:
            type = "ipad"
        default:
            type = "iphone"
        }

        let chargingStatus: String
        switch device.batteryState {
        case .charging:
            chargingStatus = "charging"
        case .full:
            chargingStatus = "charged"
        default:
            chargingStatus = "discharging"
        }

        let displayName = resolvedDisplayName(for: device)
        let stableId = device.identifierForVendor?.uuidString ?? displayName.replacingOccurrences(of: " ", with: "_")

        let payload = DeviceBattery(
            id: "ios_\(stableId)",
            name: displayName,
            type: type,
            batteryLevel: max(0, min(100, level)),
            chargingStatus: chargingStatus,
            timeRemaining: nil,
            lastUpdated: Date()
        )

        iCloudSyncManager.shared.updateDevice(payload)
    }

    private func resolvedDisplayName(for device: UIDevice) -> String {
        let rawName = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = rawName.lowercased()
        let isGeneric = lower == "iphone" || lower == "ipad" || lower == "ipod touch"

        guard isGeneric else {
            return rawName.isEmpty ? fallbackGenericDisplayName(for: device) : rawName
        }

        return fallbackGenericDisplayName(for: device)
    }

    private func fallbackGenericDisplayName(for device: UIDevice) -> String {
        let base = device.userInterfaceIdiom == .pad ? "iPad" : "iPhone"

        if let ownerPrefix = inferOwnerPrefixFromSyncedDevices() {
            return "\(ownerPrefix) \(base)"
        }

        return "My \(base)"
    }

    private func inferOwnerPrefixFromSyncedDevices() -> String? {
        let devices = iCloudSyncManager.shared.devices
        for item in devices where item.type == "macbook" {
            let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = trimmed.range(of: "MacBook") {
                let prefix = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                    return prefix
                }
            }

            if let firstSpace = trimmed.firstIndex(of: " ") {
                let firstToken = String(trimmed[..<firstSpace])
                if firstToken.contains("'") || firstToken.contains("’") {
                    return firstToken
                }
            }
        }
        return nil
    }
}
#endif
