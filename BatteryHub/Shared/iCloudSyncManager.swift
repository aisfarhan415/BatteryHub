import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

public class iCloudSyncManager: ObservableObject {
    @Published public var devices: [DeviceBattery] = []

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    public static let shared = iCloudSyncManager()

    private let supabaseURL = "https://rxebegpswrvgcqutnmtn.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ4ZWJlZ3Bzd3J2Z2NxdXRubXRuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAyNjY1MzcsImV4cCI6MjA5NTg0MjUzN30.sZ6d_1RU44e15b7q4dVu7jT0WHzct5yAMsV5nDUyYfU"

    private var isConfigured: Bool {
        return !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }

    private init() {
        loadDevices()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.loadDevices()
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    public func loadDevices() {
        guard isConfigured else {
            DispatchQueue.main.async {
                self.devices = []
            }
            return
        }

        guard let url = URL(string: "\(supabaseURL)/rest/v1/devices?select=*&order=last_updated.desc") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            
            if error != nil { return }
            guard let data = data else { return }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let raw = try container.decode(String.self)

                    let fractional = ISO8601DateFormatter()
                    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = fractional.date(from: raw) {
                        return date
                    }

                    let standard = ISO8601DateFormatter()
                    standard.formatOptions = [.withInternetDateTime]
                    if let date = standard.date(from: raw) {
                        return date
                    }

                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(raw)")
                }
                
                let rows = try decoder.decode([SupabaseDeviceRow].self, from: data)
                let mapped = rows.map { $0.toDeviceBattery() }
                let deduped = self.deduplicateDevices(mapped)

                DispatchQueue.main.async {
                    if self.devices != deduped {
                        self.devices = deduped
                        self.reloadWidgetsIfAvailable()
                    }
                }
            } catch {
                print(error)
            }
        }.resume()
    }

    public func updateDevice(_ device: DeviceBattery) {
        DispatchQueue.main.async {
            if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                self.devices[index] = device
            } else {
                self.devices.append(device)
                self.devices.sort { $0.lastUpdated > $1.lastUpdated }
            }
            self.reloadWidgetsIfAvailable()
        }

        guard isConfigured else { return }
        guard let url = URL(string: "\(supabaseURL)/rest/v1/devices?on_conflict=id") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")

        let row = SupabaseDeviceRow(from: device)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode([row])
        } catch {
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                print("Supabase updateDevice error for \(device.id): \(error)")
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                print("Supabase updateDevice failed for \(device.id). status=\(http.statusCode) body=\(body)")
                return
            }

            self?.loadDevices()
        }.resume()
    }

    public func deleteDevice(id: String) {
        DispatchQueue.main.async {
            self.devices.removeAll(where: { $0.id == id })
            self.reloadWidgetsIfAvailable()
        }

        guard isConfigured else { return }

        guard let safeId = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(supabaseURL)/rest/v1/devices?id=eq.\(safeId)") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if error != nil { return }
            self?.loadDevices()
        }.resume()
    }

    private func reloadWidgetsIfAvailable() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

private extension iCloudSyncManager {
    func deduplicateDevices(_ devices: [DeviceBattery]) -> [DeviceBattery] {
        var bestByKey: [String: DeviceBattery] = [:]

        for device in devices {
            let key = "\(device.type)|\(normalize(device.name))"
            if let existing = bestByKey[key] {
                if device.lastUpdated > existing.lastUpdated {
                    bestByKey[key] = device
                }
            } else {
                bestByKey[key] = device
            }
        }

        return bestByKey.values.sorted { $0.lastUpdated > $1.lastUpdated }
    }

    func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    let leftBattery: Int?
    let rightBattery: Int?
    let caseBattery: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case batteryLevel = "battery_level"
        case chargingStatus = "charging_status"
        case timeRemaining = "time_remaining"
        case lastUpdated = "last_updated"
        case leftBattery = "left_battery"
        case rightBattery = "right_battery"
        case caseBattery = "case_battery"
    }

    init(from device: DeviceBattery) {
        self.id = device.id
        self.name = device.name
        self.type = device.type
        self.batteryLevel = device.batteryLevel
        self.chargingStatus = device.chargingStatus
        self.timeRemaining = device.timeRemaining
        self.lastUpdated = device.lastUpdated
        self.leftBattery = device.leftBattery
        self.rightBattery = device.rightBattery
        self.caseBattery = device.caseBattery
    }

    func toDeviceBattery() -> DeviceBattery {
        DeviceBattery(
            id: id,
            name: name,
            type: type,
            batteryLevel: batteryLevel,
            chargingStatus: chargingStatus,
            timeRemaining: timeRemaining,
            lastUpdated: lastUpdated,
            leftBattery: leftBattery,
            rightBattery: rightBattery,
            caseBattery: caseBattery
        )
    }
}
