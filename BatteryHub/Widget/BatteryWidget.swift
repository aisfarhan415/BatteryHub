// Only compile the widget entry point when building the Widget Extension target.
#if WIDGET_EXTENSION
import WidgetKit
import SwiftUI

// Basic Widget Provider
struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), devices: getPlaceholderDevices())
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> ()) {
        let entry = BatteryEntry(date: Date(), devices: iCloudSyncManager.shared.devices)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        iCloudSyncManager.shared.loadDevices()
        let entry = BatteryEntry(date: Date(), devices: iCloudSyncManager.shared.devices)
        
        // Refresh timeline every 15 minutes (or on iCloud push automatically)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func getPlaceholderDevices() -> [DeviceBattery] {
        return [
            DeviceBattery(id: "1", name: "MacBook", type: "macbook", batteryLevel: 90, chargingStatus: "discharging"),
            DeviceBattery(id: "2", name: "iPhone", type: "iphone", batteryLevel: 75, chargingStatus: "charging")
        ]
    }
}

// Widget Data Entry
struct BatteryEntry: TimelineEntry {
    let date: Date
    let devices: [DeviceBattery]
}

// SwiftUI Widget Layout View
struct BatteryWidgetEntryView : View {
    var entry: BatteryProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.08)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bolt.battery.tab.fill")
                        .foregroundColor(.blue)
                    Text("Baterai")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                }
                
                // Displays up to 3 devices in small/medium widgets
                VStack(spacing: 8) {
                    ForEach(entry.devices.prefix(3)) { device in
                        HStack {
                            Image(systemName: getSFSymbol(for: device.type))
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 20, height: 20)
                            
                            Text(device.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text("\(device.batteryLevel)%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(getBatteryColor(level: device.batteryLevel))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(12)
        }
    }
    
    private func getSFSymbol(for type: String) -> String {
        switch type {
        case "macbook": return "laptopcomputer"
        case "iphone": return "iphone"
        case "ipad": return "ipad"
        case "watch": return "applewatch"
        default: return "app.badge"
        }
    }
    
    private func getBatteryColor(level: Int) -> Color {
        if level > 20 { return .green }
        if level > 10 { return .orange }
        return .red
    }
}

// Widget Configurations
@main
struct BatteryWidget: Widget {
    let kind: String = "BatteryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryProvider()) { entry in
            BatteryWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Battery Monitor")
        .description("Pantau semua baterai perangkat Apple Anda.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium]
        #if os(iOS)
        families.append(.systemLarge)
        #endif
        #if os(macOS)
        families.append(.systemLarge)
        #endif
        return families
    }
}

#endif
