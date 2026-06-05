import Foundation

#if os(macOS)

final class MacAccessorySyncService {
    static let shared = MacAccessorySyncService()

    private var timer: Timer?
    private init() {}

    func start() {
        publishAccessories()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.publishAccessories()
        }
    }

    private func publishAccessories() {
        let accessories = MacAccessoryReader.readAccessoryBatteries()
        print("Accessory sync snapshot count: \(accessories.count)")
        if !accessories.isEmpty {
            let names = accessories.map { "\($0.name) [\($0.type)] \($0.batteryLevel)%" }.joined(separator: ", ")
            print("Accessory sync devices: \(names)")
        }
        for accessory in accessories {
            iCloudSyncManager.shared.updateDevice(accessory)
        }
    }
}

#endif
