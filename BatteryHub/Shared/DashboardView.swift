import SwiftUI
import Combine

struct DashboardView: View {
    @StateObject private var syncManager = iCloudSyncManager.shared
    @StateObject private var metaStore = DeviceMetaStore.shared
    @StateObject private var automationStore = AutomationStore.shared
    #if os(iOS)
    @StateObject private var watchLinkStatus = WatchConnectivityBridge.shared.statusStore
    #endif
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var selectedFilter: DeviceFilter = .all
    @State private var selectedSort: SortOption = .pinnedThenLow
    @State private var selectedTab: HomeTab = .devices
    @State private var selectedDevice: DeviceBattery?

    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 460), spacing: 16)]

    var body: some View {
        ZStack {
            PremiumBackground(colorScheme: colorScheme).ignoresSafeArea()
            TabView(selection: $selectedTab) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        infoCenter
                        insights
                        #if os(iOS)
                        watchLinkPanel
                        #endif
                        quickDevicesPreview
                        if !smartAlerts.isEmpty { smartAlertPanel }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .tabItem { Label("Overview", systemImage: "square.grid.2x2") }
                .tag(HomeTab.overview)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        controls
                        ForEach(groupedDevices, id: \.owner) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.owner)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.secondary)

                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(group.devices) { device in
                                        DevicePanel(
                                            device: device,
                                            alias: metaStore.alias(for: device.id),
                                            isPinned: metaStore.isPinned(device.id),
                                            accessoryRows: accessoryRows(for: device),
                                            drainRatePerHour: drainRatePerHour(for: device.id),
                                            etaText: etaText(for: device.id, status: device.chargingStatus),
                                            onTap: { selectedDevice = device },
                                            onPinToggle: { metaStore.togglePinned(device.id) }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .tabItem { Label("Devices", systemImage: "iphone.gen3") }
                .tag(HomeTab.devices)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        automationHub
                        if !smartAlerts.isEmpty { smartAlertPanel }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .tabItem { Label("Automation", systemImage: "bolt.badge.automatic") }
                .tag(HomeTab.automation)
            }
            .tint(colorScheme == .dark ? .white : .blue)
            #if os(iOS)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            #endif
        }
        .onAppear {
            metaStore.appendSamples(from: syncManager.devices)
            automationStore.runRules(with: syncManager.devices)
        }
        .onChange(of: syncManager.devices) { _, newValue in
            metaStore.appendSamples(from: newValue)
            automationStore.runRules(with: newValue)
        }
        .sheet(item: $selectedDevice) { device in
            DeviceDetailSheet(
                device: device,
                alias: metaStore.alias(for: device.id),
                isPinned: metaStore.isPinned(device.id),
                lowThreshold: metaStore.threshold(for: device.id),
                isMuted: metaStore.isMuted(device.id),
                samples: metaStore.samples(for: device.id),
                accessoryRows: accessoryRows(for: device),
                onSaveAlias: { metaStore.setAlias($0, for: device.id) },
                onTogglePinned: { metaStore.togglePinned(device.id) },
                onThresholdChange: { metaStore.setThreshold($0, for: device.id) },
                onToggleMute: { metaStore.toggleMute(device.id) }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("BatteryHub")
                    .font(.system(size: 30, weight: .bold))
                Spacer()
                Text("Updated \(lastSyncText)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("Live Sync")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search devices, accessories, owner", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(glassCard(corner: 12))

            HStack(spacing: 10) {
                Menu {
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(DeviceFilter.allCases, id: \.self) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Filter:")
                            .foregroundStyle(.secondary)
                        Text(selectedFilter.rawValue)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(glassCard(corner: 10))
                }

                Menu {
                    Picker("Sort", selection: $selectedSort) {
                        ForEach(SortOption.allCases, id: \.self) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Sort:")
                            .foregroundStyle(.secondary)
                        Text(selectedSort.rawValue)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(glassCard(corner: 10))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var insights: some View {
        let stats = dashboardStats
        return HStack(spacing: 8) {
            InsightTile(title: "Devices", value: "\(stats.total)", tint: .white)
            InsightTile(title: "Charging", value: "\(stats.charging)", tint: .green)
            InsightTile(title: "Low", value: "\(stats.low)", tint: .orange)
            InsightTile(title: "Avg", value: "\(stats.avg)%", tint: .blue)
            InsightTile(title: "Health", value: "\(stats.health)", tint: stats.healthColor)
        }
    }

    private var quickDevicesPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Devices")
                .font(.system(size: 15, weight: .bold))
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(filteredDevices.prefix(2))) { device in
                    DevicePanel(
                        device: device,
                        alias: metaStore.alias(for: device.id),
                        isPinned: metaStore.isPinned(device.id),
                        accessoryRows: accessoryRows(for: device),
                        drainRatePerHour: drainRatePerHour(for: device.id),
                        etaText: etaText(for: device.id, status: device.chargingStatus),
                        onTap: { selectedDevice = device },
                        onPinToggle: { metaStore.togglePinned(device.id) }
                    )
                }
            }
        }
    }

    #if os(iOS)
    private var watchLinkPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Watch Link Status")
                .font(.system(size: 15, weight: .bold))

            HStack {
                Text(linkStateText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(linkStateColor)
                Spacer()
                if let t = watchLinkStatus.lastPayloadAt {
                    Text("Last payload \(relativeTime(from: t))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No payload yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let name = watchLinkStatus.lastWatchName, let level = watchLinkStatus.lastWatchLevel {
                HStack {
                    Image(systemName: "applewatch")
                    Text(name)
                    Spacer()
                    Text("\(level)%")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            if let err = watchLinkStatus.lastError, !err.isEmpty {
                Text("Bridge error: \(err)")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(glassCard(corner: 12, tint: linkStateColor.opacity(0.08)))
    }

    private var linkStateText: String {
        if let last = watchLinkStatus.lastPayloadAt {
            let age = Date().timeIntervalSince(last)
            if age <= 300 { return "Connected" }
            if age <= 1800 { return "Stale" }
            return "Outdated"
        }
        return watchLinkStatus.isSessionReachable ? "Linked (waiting payload)" : "Not linked"
    }

    private var linkStateColor: Color {
        switch linkStateText {
        case "Connected":
            return .green
        case "Stale":
            return .orange
        case "Outdated", "Not linked":
            return .red
        default:
            return .yellow
        }
    }

    private func relativeTime(from date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
    #endif

    private var infoCenter: some View {
        let info = runtimeInfo
        return VStack(alignment: .leading, spacing: 8) {
            Text("Device Info Center")
                .font(.system(size: 15, weight: .bold))
            HStack(spacing: 8) {
                InsightTile(title: "Online", value: "\(info.online)", tint: .green)
                InsightTile(title: "Offline", value: "\(info.offline)", tint: .orange)
                InsightTile(title: "Owners", value: "\(info.owners)", tint: .white)
                InsightTile(title: "Platforms", value: "\(info.platforms)", tint: .blue)
            }
        }
    }

    private var automationHub: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Automation Hub")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Run Now") {
                    automationStore.runRules(with: syncManager.devices)
                }
                .font(.system(size: 12, weight: .bold))
            }

            ForEach(automationStore.rules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.name).font(.system(size: 13, weight: .semibold))
                        Text(rule.description).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { rule.enabled },
                        set: { automationStore.setEnabled($0, for: rule.id) }
                    ))
                    .labelsHidden()
                }
                .padding(10)
                .background(glassCard(corner: 10))
            }

            if !automationStore.events.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Actions")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    ForEach(automationStore.events.prefix(3), id: \.id) { event in
                        Text("• \(event.message)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var smartAlertPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Smart Alerts")
                .font(.system(size: 15, weight: .bold))
            ForEach(smartAlerts.prefix(4), id: \.id) { alert in
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(alert.message).lineLimit(1)
                    Spacer()
                }
                .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(12)
        .background(glassCard(corner: 12, tint: Color.orange.opacity(0.10)))
    }

    private var filteredDevices: [DeviceBattery] {
        var devices = syncManager.devices

        switch selectedFilter {
        case .all: break
        case .charging: devices = devices.filter { $0.chargingStatus == "charging" }
        case .low: devices = devices.filter { $0.batteryLevel <= 25 }
        case .mobile: devices = devices.filter { ["iphone", "ipad", "watch"].contains($0.type) }
        case .accessories: devices = devices.filter { ["airpods", "keyboard", "mouse", "pencil"].contains($0.type) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            devices = devices.filter { d in
                let owner = ownerName(for: d)
                return d.name.lowercased().contains(query) ||
                owner.lowercased().contains(query) ||
                (metaStore.alias(for: d.id) ?? "").lowercased().contains(query)
            }
        }

        switch selectedSort {
        case .pinnedThenLow:
            devices.sort {
                let lp = metaStore.isPinned($0.id)
                let rp = metaStore.isPinned($1.id)
                if lp != rp { return lp && !rp }
                return $0.batteryLevel < $1.batteryLevel
            }
        case .lowest:
            devices.sort { $0.batteryLevel < $1.batteryLevel }
        case .highest:
            devices.sort { $0.batteryLevel > $1.batteryLevel }
        case .name:
            devices.sort { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }
        case .recent:
            devices.sort { $0.lastUpdated > $1.lastUpdated }
        }

        return devices
    }

    private var groupedDevices: [(owner: String, devices: [DeviceBattery])] {
        let grouped = Dictionary(grouping: filteredDevices) { ownerName(for: $0) }
        return grouped.keys.sorted().map { key in
            (owner: key, devices: grouped[key] ?? [])
        }
    }

    private var smartAlerts: [DeviceAlert] {
        filteredDevices.compactMap { d in
            guard !metaStore.isMuted(d.id) else { return nil }
            let threshold = metaStore.threshold(for: d.id)
            if d.chargingStatus != "charging" && d.batteryLevel <= threshold {
                return DeviceAlert(id: d.id, message: "\(displayName(for: d)) low (\(d.batteryLevel)%)")
            }
            return nil
        }
    }

    private var dashboardStats: (total: Int, charging: Int, low: Int, avg: Int, health: Int, healthColor: Color) {
        let devices = filteredDevices
        guard !devices.isEmpty else { return (0, 0, 0, 0, 0, .red) }
        let total = devices.count
        let charging = devices.filter { $0.chargingStatus == "charging" }.count
        let low = devices.filter { $0.batteryLevel <= 20 }.count
        let avg = Int(Double(devices.map(\.batteryLevel).reduce(0, +)) / Double(total))
        let health = max(0, min(100, avg - (low * 8) + (charging * 4)))
        let color: Color = health >= 75 ? .green : (health >= 50 ? .orange : .red)
        return (total, charging, low, avg, health, color)
    }

    private var runtimeInfo: (online: Int, offline: Int, owners: Int, platforms: Int) {
        let devices = syncManager.devices
        let now = Date()
        let online = devices.filter { now.timeIntervalSince($0.lastUpdated) < 20 * 60 }.count
        let offline = max(0, devices.count - online)
        let owners = Set(devices.map { ownerName(for: $0) }).count
        let platforms = Set(devices.map(\.type)).count
        return (online, offline, owners, platforms)
    }

    private var lastSyncText: String {
        guard let latest = syncManager.devices.map(\.lastUpdated).max() else { return "never" }
        return latest.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private func glassCard(corner: CGFloat, tint: Color = .clear) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.16), .clear, .black.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(tint)
            )
    }

    private func accessoryRows(for device: DeviceBattery) -> [AccessoryRow] {
        var rows: [AccessoryRow] = []
        if let l = device.leftBattery { rows.append(AccessoryRow(title: "Left", level: l, symbol: "earbuds")) }
        if let r = device.rightBattery { rows.append(AccessoryRow(title: "Right", level: r, symbol: "earbuds")) }
        if let c = device.caseBattery { rows.append(AccessoryRow(title: "Case", level: c, symbol: "briefcase")) }
        return rows
    }

    private func displayName(for device: DeviceBattery) -> String {
        metaStore.alias(for: device.id) ?? device.name
    }

    private func ownerName(for device: DeviceBattery) -> String {
        let name = displayName(for: device)
        if let idx = name.firstIndex(where: { $0 == "’" || $0 == "'" }) {
            return String(name[...idx])
        }
        if name.lowercased().contains("macbook") { return "Mac" }
        return "Devices"
    }

    private func drainRatePerHour(for deviceId: String) -> Int {
        let samples = metaStore.samples(for: deviceId)
        guard samples.count >= 2 else { return 0 }
        guard let first = samples.first, let last = samples.last else { return 0 }
        let deltaLevel = first.level - last.level
        let deltaHours = max(0.01, last.time.timeIntervalSince(first.time) / 3600.0)
        return Int(Double(deltaLevel) / deltaHours)
    }

    private func etaText(for deviceId: String, status: String) -> String {
        if status == "charging" { return "Charging" }
        let samples = metaStore.samples(for: deviceId)
        guard let latest = samples.last else { return "Unknown" }
        let rate = max(1, drainRatePerHour(for: deviceId))
        let hours = Double(latest.level) / Double(rate)
        if hours >= 24 { return "\(Int(hours / 24))d left" }
        return "\(max(0, Int(hours.rounded())))h left"
    }
}

private struct DevicePanel: View {
    let device: DeviceBattery
    let alias: String?
    let isPinned: Bool
    let accessoryRows: [AccessoryRow]
    let drainRatePerHour: Int
    let etaText: String
    let onTap: () -> Void
    let onPinToggle: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: symbol(for: device.type))
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    Text(displayName)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Button(action: onPinToggle) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Text(statusText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 8) {
                        Text("\(device.batteryLevel)%")
                            .font(.system(size: 31, weight: .semibold))
                            .monospacedDigit()
                        Image(systemName: batteryGlyph(for: device.batteryLevel, charging: device.chargingStatus == "charging"))
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().overlay(Color.primary.opacity(0.12))

                if !accessoryRows.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(accessoryRows, id: \.title) { row in
                            HStack {
                                Label(row.title, systemImage: row.symbol)
                                Spacer()
                                Text("\(row.level)%")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Text("Drain \(drainRatePerHour)/h")
                    Spacer()
                    Text(etaText)
                }
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.14), .clear, .black.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var displayName: String { alias ?? device.name }

    private func symbol(for type: String) -> String {
        switch type {
        case "macbook": return "laptopcomputer"
        case "iphone": return "iphone"
        case "ipad": return "ipad"
        case "watch": return "applewatch"
        case "airpods": return "airpodspro"
        case "keyboard": return "keyboard"
        case "mouse": return "magicmouse"
        case "pencil": return "applepencil"
        default: return "app.badge"
        }
    }

    private var statusText: String {
        if device.chargingStatus == "charging" { return "Charging" }
        if device.chargingStatus == "charged" { return "Fully Charged" }
        return "Discharging"
    }

    private func batteryGlyph(for level: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        if level >= 90 { return "battery.100" }
        if level >= 65 { return "battery.75" }
        if level >= 35 { return "battery.50" }
        if level >= 15 { return "battery.25" }
        return "battery.0"
    }
}

private struct DeviceDetailSheet: View {
    let device: DeviceBattery
    let alias: String?
    let isPinned: Bool
    let lowThreshold: Int
    let isMuted: Bool
    let samples: [BatterySample]
    let accessoryRows: [AccessoryRow]
    let onSaveAlias: (String?) -> Void
    let onTogglePinned: () -> Void
    let onThresholdChange: (Int) -> Void
    let onToggleMute: () -> Void

    @State private var draftAlias: String = ""
    @State private var draftThreshold: Double = 20

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Alias", text: $draftAlias)
                    Button(isPinned ? "Unpin Device" : "Pin Device") { onTogglePinned() }
                    Button("Save Alias") {
                        let trimmed = draftAlias.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSaveAlias(trimmed.isEmpty ? nil : trimmed)
                    }
                }

                Section("Alert Rules") {
                    HStack {
                        Text("Low Battery Threshold")
                        Spacer()
                        Text("\(Int(draftThreshold))%")
                    }
                    Slider(value: $draftThreshold, in: 5...50, step: 1)
                    Button(isMuted ? "Unmute Alerts" : "Mute Alerts") { onToggleMute() }
                }

                Section("Battery Trend (24h)") {
                    SparklineView(samples: samples)
                        .frame(height: 100)
                    if let metric = detailMetric {
                        Text(metric).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Activity Timeline") {
                    ForEach(activityTimeline, id: \.id) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.system(size: 12, weight: .semibold))
                            Text(event.time.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !accessoryRows.isEmpty {
                    Section("Accessories") {
                        ForEach(accessoryRows, id: \.title) { row in
                            HStack {
                                Label(row.title, systemImage: row.symbol)
                                Spacer()
                                Text("\(row.level)%")
                            }
                        }
                    }
                }
            }
            .navigationTitle(alias ?? device.name)
            .onAppear {
                draftAlias = alias ?? ""
                draftThreshold = Double(lowThreshold)
            }
            .onChange(of: draftThreshold) { _, newValue in
                onThresholdChange(Int(newValue))
            }
        }
    }

    private var detailMetric: String? {
        guard samples.count >= 2, let first = samples.first, let last = samples.last else { return nil }
        let delta = first.level - last.level
        let hours = max(0.1, last.time.timeIntervalSince(first.time) / 3600)
        let rate = Double(delta) / hours
        return "Estimated drain rate: \(Int(rate))/h"
    }

    private var activityTimeline: [DetailEvent] {
        guard !samples.isEmpty else { return [] }
        var items: [DetailEvent] = []
        for i in samples.indices {
            let s = samples[i]
            if i == 0 {
                items.append(DetailEvent(id: "start_\(i)", title: "Tracking started at \(s.level)%", time: s.time))
            } else {
                let prev = samples[i - 1]
                let delta = s.level - prev.level
                if abs(delta) >= 3 {
                    let label = delta > 0 ? "Charged +\(delta)%" : "Dropped \(delta)%"
                    items.append(DetailEvent(id: "delta_\(i)", title: label, time: s.time))
                }
            }
        }
        return Array(items.suffix(8)).reversed()
    }
}

private struct SparklineView: View {
    let samples: [BatterySample]

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(width: geo.size.width, height: geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func normalizedPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }
        let minLevel = samples.map(\.level).min() ?? 0
        let maxLevel = samples.map(\.level).max() ?? 100
        let span = max(1, maxLevel - minLevel)
        let stepX = width / CGFloat(max(1, samples.count - 1))
        return samples.enumerated().map { idx, sample in
            let x = CGFloat(idx) * stepX
            let normalized = CGFloat(sample.level - minLevel) / CGFloat(span)
            let y = height - (normalized * (height - 10)) - 5
            return CGPoint(x: x, y: y)
        }
    }
}

private struct InsightTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .regular)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct BatteryPill: View {
    let level: Int
    let chargingStatus: String

    var body: some View {
        HStack(spacing: 4) {
            if chargingStatus == "charging" {
                Image(systemName: "bolt.fill").font(.system(size: 9, weight: .black))
            }
            Text("\(level)%").font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.16))
        .clipShape(Capsule())
    }

    private var color: Color {
        if chargingStatus == "charging" { return .green }
        if level > 20 { return .primary }
        if level > 10 { return .orange }
        return .red
    }
}

private struct PremiumBackground: View {
    let colorScheme: ColorScheme
    var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.13), Color(red: 0.07, green: 0.08, blue: 0.10)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.white.opacity(0.08), .clear], center: .topLeading, startRadius: 10, endRadius: 300)
            } else {
                LinearGradient(colors: [Color(red: 0.95, green: 0.96, blue: 0.98), Color(red: 0.90, green: 0.92, blue: 0.95)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.white.opacity(0.22), .clear], center: .topLeading, startRadius: 20, endRadius: 320)
            }
        }
    }
}

private final class DeviceMetaStore: ObservableObject {
    static let shared = DeviceMetaStore()
    @Published private var prefs: [String: DevicePreference] = [:]
    @Published private var history: [String: [BatterySample]] = [:]

    private let prefsKey = "batteryhub.device.preferences"
    private let historyKey = "batteryhub.device.history"

    private init() { load() }

    func alias(for id: String) -> String? { prefs[id]?.alias }
    func isPinned(_ id: String) -> Bool { prefs[id]?.pinned ?? false }
    func threshold(for id: String) -> Int { prefs[id]?.lowThreshold ?? 20 }
    func isMuted(_ id: String) -> Bool { prefs[id]?.muted ?? false }
    func samples(for id: String) -> [BatterySample] { history[id] ?? [] }

    func setAlias(_ alias: String?, for id: String) {
        var pref = prefs[id] ?? DevicePreference()
        pref.alias = alias
        prefs[id] = pref
        save()
    }

    func togglePinned(_ id: String) {
        var pref = prefs[id] ?? DevicePreference()
        pref.pinned.toggle()
        prefs[id] = pref
        save()
    }

    func setThreshold(_ value: Int, for id: String) {
        var pref = prefs[id] ?? DevicePreference()
        pref.lowThreshold = max(5, min(50, value))
        prefs[id] = pref
        save()
    }

    func toggleMute(_ id: String) {
        var pref = prefs[id] ?? DevicePreference()
        pref.muted.toggle()
        prefs[id] = pref
        save()
    }

    func appendSamples(from devices: [DeviceBattery]) {
        let now = Date()
        for device in devices {
            var list = history[device.id] ?? []
            if let last = list.last, now.timeIntervalSince(last.time) < 300, abs(last.level - device.batteryLevel) < 2 {
                continue
            }
            list.append(BatterySample(time: now, level: device.batteryLevel))
            let cutoff = now.addingTimeInterval(-7 * 24 * 3600)
            list.removeAll(where: { $0.time < cutoff })
            history[device.id] = list
        }
        save()
    }

    private func load() {
        if let prefsData = UserDefaults.standard.data(forKey: prefsKey),
           let decoded = try? JSONDecoder().decode([String: DevicePreference].self, from: prefsData) {
            prefs = decoded
        }
        if let historyData = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([String: [BatterySample]].self, from: historyData) {
            history = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: prefsKey)
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
}

private struct DevicePreference: Codable {
    var alias: String?
    var pinned: Bool = false
    var lowThreshold: Int = 20
    var muted: Bool = false
}

private struct BatterySample: Codable {
    let time: Date
    let level: Int
}

private struct AccessoryRow {
    let title: String
    let level: Int
    let symbol: String
}

private struct DeviceAlert {
    let id: String
    let message: String
}

private struct DetailEvent {
    let id: String
    let title: String
    let time: Date
}

private enum DeviceFilter: String, CaseIterable {
    case all = "All"
    case charging = "Charging"
    case low = "Low"
    case mobile = "Mobile"
    case accessories = "Accessory"
}

private enum SortOption: String, CaseIterable {
    case pinnedThenLow = "Pinned + Low"
    case lowest = "Lowest Battery"
    case highest = "Highest Battery"
    case name = "Name A-Z"
    case recent = "Recently Updated"
}

private enum HomeTab: String, CaseIterable {
    case overview = "Overview"
    case devices = "Devices"
    case automation = "Automation"
}

private final class AutomationStore: ObservableObject {
    static let shared = AutomationStore()
    @Published var rules: [AutomationRule] = [
        AutomationRule(id: "stale_sync", name: "Stale Sync Guard", description: "Flag devices not updated for > 90 minutes.", enabled: true),
        AutomationRule(id: "critical_offline", name: "Critical Offline Escalation", description: "Escalate if iPhone/iPad offline > 3 hours.", enabled: true),
        AutomationRule(id: "owner_presence", name: "Owner Presence Check", description: "Warn when owner has no active mobile device.", enabled: true)
    ]
    @Published var events: [AutomationEvent] = []

    private let key = "batteryhub.automation.rules"

    private init() { load() }

    func setEnabled(_ value: Bool, for id: String) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[idx].enabled = value
        save()
    }

    func runRules(with devices: [DeviceBattery]) {
        let now = Date()
        var generated: [AutomationEvent] = []

        if isEnabled("stale_sync") {
            let stale = devices.filter { now.timeIntervalSince($0.lastUpdated) > 90 * 60 }
            for d in stale.prefix(3) {
                generated.append(AutomationEvent(id: "stale_\(d.id)", message: "Stale sync: \(d.name) inactive > 90m", time: now))
            }
        }

        if isEnabled("critical_offline") {
            let critical = devices.filter {
                ["iphone", "ipad"].contains($0.type) && now.timeIntervalSince($0.lastUpdated) > 180 * 60
            }
            for d in critical.prefix(2) {
                generated.append(AutomationEvent(id: "offline_\(d.id)", message: "Critical offline: \(d.name) > 3h", time: now))
            }
        }

        if isEnabled("owner_presence") {
            let grouped = Dictionary(grouping: devices) { device in
                let name = device.name
                if let idx = name.firstIndex(where: { $0 == "’" || $0 == "'" }) {
                    return String(name[...idx])
                }
                return "Unknown"
            }
            for (owner, list) in grouped {
                let hasMobileOnline = list.contains {
                    ["iphone", "ipad", "watch"].contains($0.type) && now.timeIntervalSince($0.lastUpdated) < 45 * 60
                }
                if !hasMobileOnline {
                    generated.append(AutomationEvent(id: "owner_\(owner)", message: "Owner check: \(owner) has no active mobile device", time: now))
                }
            }
        }

        DispatchQueue.main.async {
            self.events = generated
        }
    }

    private func isEnabled(_ id: String) -> Bool {
        rules.first(where: { $0.id == id })?.enabled ?? false
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AutomationRule].self, from: data) else { return }
        rules = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct AutomationRule: Codable, Identifiable {
    let id: String
    var name: String
    var description: String
    var enabled: Bool
}

private struct AutomationEvent {
    let id: String
    let message: String
    let time: Date
}

#Preview {
    DashboardView()
}
