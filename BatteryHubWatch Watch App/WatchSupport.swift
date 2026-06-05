import Foundation
import SwiftUI
import WatchKit
import Combine
import WatchConnectivity

struct DeviceBattery: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var type: String
    var batteryLevel: Int
    var chargingStatus: String
    var timeRemaining: String?
    var lastUpdated: Date
}

final class iCloudSyncManager: ObservableObject {
    @Published var devices: [DeviceBattery] = []
    static let shared = iCloudSyncManager()

    private let supabaseURL = "https://rxebegpswrvgcqutnmtn.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ4ZWJlZ3Bzd3J2Z2NxdXRubXRuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAyNjY1MzcsImV4cCI6MjA5NTg0MjUzN30.sZ6d_1RU44e15b7q4dVu7jT0WHzct5yAMsV5nDUyYfU"

    func loadDevices() {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/devices?select=*&order=last_updated.desc") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self, let data else { return }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let rows = try decoder.decode([SupabaseDeviceRow].self, from: data)
                DispatchQueue.main.async {
                    self.devices = rows.map { $0.toDeviceBattery() }
                }
            } catch {
                // Ignore transient decoding/network errors on watch.
            }
        }.resume()
    }

    func updateDevice(_ device: DeviceBattery) {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/devices?on_conflict=id") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        do {
            let row = SupabaseDeviceRow(from: device)
            request.httpBody = try JSONEncoder().encode([row])
        } catch {
            return
        }

        URLSession.shared.dataTask(with: request).resume()
    }
}

final class WatchBatteryReporter {
    static let shared = WatchBatteryReporter()
    private init() {}

    func publishNow() {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true

        let rawLevel = device.batteryLevel
        let level = rawLevel >= 0 ? Int((rawLevel * 100).rounded()) : 100

        let status: String
        switch device.batteryState {
        case .charging: status = "charging"
        case .full: status = "charged"
        default: status = "discharging"
        }

        let name = device.name.isEmpty ? "Apple Watch" : device.name
        let stableId = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
        let payload = DeviceBattery(
            id: "watch_\(stableId)",
            name: name,
            type: "watch",
            batteryLevel: max(0, min(100, level)),
            chargingStatus: status,
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

struct DashboardView: View {
    @StateObject private var store = iCloudSyncManager.shared

    var body: some View {
        List {
            ForEach(store.devices.prefix(8)) { device in
                HStack {
                    Text(device.name)
                        .lineLimit(1)
                    Spacer()
                    Text("\(device.batteryLevel)%")
                        .foregroundColor(.green)
                }
            }
        }
        .onAppear {
            store.loadDevices()
            WatchBatteryReporter.shared.publishNow()
        }
    }
}

private struct SupabaseDeviceRow: Codable {
    let id: String
    let name: String
    let type: String
    let batteryLevel: Int
    let chargingStatus: String
    let timeRemaining: String?
    let lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case batteryLevel = "battery_level"
        case chargingStatus = "charging_status"
        case timeRemaining = "time_remaining"
        case lastUpdated = "last_updated"
    }

    init(from device: DeviceBattery) {
        self.id = device.id
        self.name = device.name
        self.type = device.type
        self.batteryLevel = device.batteryLevel
        self.chargingStatus = device.chargingStatus
        self.timeRemaining = device.timeRemaining
        self.lastUpdated = device.lastUpdated
    }

    func toDeviceBattery() -> DeviceBattery {
        DeviceBattery(
            id: id,
            name: name,
            type: type,
            batteryLevel: batteryLevel,
            chargingStatus: chargingStatus,
            timeRemaining: timeRemaining,
            lastUpdated: lastUpdated
        )
    }
}
