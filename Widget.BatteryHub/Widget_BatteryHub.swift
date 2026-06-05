import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), devices: getPlaceholderDevices())
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(BatteryEntry(date: Date(), devices: WidgetDeviceStore.placeholderDevices))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        WidgetDeviceStore.loadDevices { devices in
            let entry = BatteryEntry(date: Date(), devices: devices)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func getPlaceholderDevices() -> [WidgetDeviceBattery] {
        WidgetDeviceStore.placeholderDevices
    }
}

struct BatteryEntry: TimelineEntry {
    let date: Date
    let devices: [WidgetDeviceBattery]
}

struct Widget_BatteryHubEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let rows = displayRows()

        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.13, blue: 0.18),
                    Color(red: 0.05, green: 0.06, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                Text("Battery List")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 10) {
                        Image(systemName: row.symbol)
                            .font(.system(size: row.isSubItem ? 13 : 15, weight: .medium))
                            .foregroundColor(.white.opacity(row.isSubItem ? 0.65 : 0.78))
                            .frame(width: 18)

                        Text(row.name)
                            .font(.system(size: row.isSubItem ? 12 : 13, weight: row.isSubItem ? .regular : .semibold))
                            .foregroundColor(.white.opacity(row.isSubItem ? 0.78 : 0.92))
                            .lineLimit(1)

                        Spacer()

                        Text("\(row.level)%")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))

                        Image(systemName: batteryGlyph(for: row.level))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, row.isSubItem ? 7 : 9)

                    if index < rows.count - 1 {
                        Divider().overlay(Color.white.opacity(0.14))
                            .padding(.leading, row.isSubItem ? 30 : 12)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .containerBackground(.clear, for: .widget)
    }

    private func getSFSymbol(for type: String) -> String {
        switch type {
        case "macbook": return "laptopcomputer"
        case "iphone": return "iphone"
        case "ipad": return "ipad"
        case "watch": return "applewatch"
        case "airpods": return "airpodspro"
        default: return "app.badge"
        }
    }

    private func batteryGlyph(for level: Int) -> String {
        if level >= 90 { return "battery.100" }
        if level >= 65 { return "battery.75" }
        if level >= 35 { return "battery.50" }
        if level >= 15 { return "battery.25" }
        return "battery.0"
    }

    private func displayRows() -> [WidgetDisplayRow] {
        let maxBase: Int
        switch family {
        case .systemSmall:
            maxBase = 2
        case .systemMedium:
            maxBase = 4
        default:
            maxBase = 7
        }

        var rows: [WidgetDisplayRow] = []
        let baseDevices = Array(entry.devices.prefix(maxBase))

        for device in baseDevices {
            rows.append(
                WidgetDisplayRow(
                    id: "main_\(device.id)",
                    name: device.name,
                    symbol: getSFSymbol(for: device.type),
                    level: max(0, min(100, device.batteryLevel)),
                    isSubItem: false
                )
            )

            if device.type == "airpods" {
                if let left = device.leftBattery {
                    rows.append(WidgetDisplayRow(id: "left_\(device.id)", name: "\(device.name) Left", symbol: "earbuds", level: left, isSubItem: true))
                }
                if let right = device.rightBattery {
                    rows.append(WidgetDisplayRow(id: "right_\(device.id)", name: "\(device.name) Right", symbol: "earbuds", level: right, isSubItem: true))
                }
                if let caseBattery = device.caseBattery {
                    rows.append(WidgetDisplayRow(id: "case_\(device.id)", name: "\(device.name) Case", symbol: "briefcase", level: caseBattery, isSubItem: true))
                }
            }
        }

        return rows
    }
}

struct Widget_BatteryHub: Widget {
    let kind: String = "Widget_BatteryHub"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            Widget_BatteryHubEntryView(entry: entry)
        }
        .configurationDisplayName("Battery Monitor")
        .description("Pantau semua baterai perangkat Apple Anda.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetDeviceBattery: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let batteryLevel: Int
    let chargingStatus: String
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
        case lastUpdated = "last_updated"
        case leftBattery = "left_battery"
        case rightBattery = "right_battery"
        case caseBattery = "case_battery"
    }
}

enum WidgetDeviceStore {
    static let placeholderDevices: [WidgetDeviceBattery] = [
        WidgetDeviceBattery(id: "1", name: "Farhan's MacBook Air", type: "macbook", batteryLevel: 100, chargingStatus: "charging", lastUpdated: Date(), leftBattery: nil, rightBattery: nil, caseBattery: nil),
        WidgetDeviceBattery(id: "2", name: "Farhan's AirPods", type: "airpods", batteryLevel: 87, chargingStatus: "discharging", lastUpdated: Date(), leftBattery: 100, rightBattery: 100, caseBattery: 67),
        WidgetDeviceBattery(id: "3", name: "Farhan's iPhone", type: "iphone", batteryLevel: 65, chargingStatus: "discharging", lastUpdated: Date(), leftBattery: nil, rightBattery: nil, caseBattery: nil)
    ]

    private static let supabaseURL = "https://rxebegpswrvgcqutnmtn.supabase.co"
    private static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ4ZWJlZ3Bzd3J2Z2NxdXRubXRuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAyNjY1MzcsImV4cCI6MjA5NTg0MjUzN30.sZ6d_1RU44e15b7q4dVu7jT0WHzct5yAMsV5nDUyYfU"

    static func loadDevices(completion: @escaping ([WidgetDeviceBattery]) -> Void) {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/devices?select=*&order=last_updated.desc") else {
            completion(placeholderDevices)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil, let data else {
                completion(placeholderDevices)
                return
            }

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

                let rows = try decoder.decode([WidgetDeviceBattery].self, from: data)
                completion(rows.isEmpty ? placeholderDevices : rows)
            } catch {
                completion(placeholderDevices)
            }
        }.resume()
    }
}

private struct WidgetDisplayRow: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let level: Int
    let isSubItem: Bool
}
