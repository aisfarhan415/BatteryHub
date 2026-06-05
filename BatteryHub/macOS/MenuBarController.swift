import SwiftUI
import AppKit

public class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    
    public override init() {
        super.init()
        setupMenuBar()
        startMonitoring()
    }
    
    private func setupMenuBar() {
        // Create standard system menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bolt.battery.tab.fill", accessibilityDescription: "Battery Dashboard")
            button.action = #selector(menuBarClicked)
            button.target = self
        }
        
        // Add basic dropdown menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: " Open Battery Dashboard", action: #selector(openApp), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Battery Monitor", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        
        // Set target actions
        menu.items.forEach { $0.target = self }
    }
    
    private func startMonitoring() {
        // Read local battery and sync to iCloud immediately
        updateLocalBattery()
        
        // Every 30 seconds, update battery status
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateLocalBattery()
        }
    }
    
    private func updateLocalBattery() {
        let nativeStatus = MacBatteryReader.readCurrentBattery()
        
        let localMac = DeviceBattery(
            id: "macbook_local",
            name: Host.current().localizedName ?? "My MacBook",
            type: "macbook",
            batteryLevel: nativeStatus.level,
            chargingStatus: nativeStatus.chargingStatus,
            timeRemaining: nativeStatus.timeRemaining,
            lastUpdated: Date()
        )
        
        // Push local Mac battery status to cloud
        iCloudSyncManager.shared.updateDevice(localMac)

        // Refresh accessories discovered by macOS Bluetooth stack.
        refreshAccessoryDevices()
        
        // Update menu bar title with MacBook battery %
        if let button = statusItem?.button {
            button.title = " \(nativeStatus.level)%"
            
            // Adapt system symbol based on state
            let symbolName = nativeStatus.chargingStatus == "charging" ? "battery.100.bolt" : "battery.75"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        }
    }

    private func refreshAccessoryDevices() {
        // Upsert accessory snapshot directly. Avoid delete-then-insert because
        // async network calls can race and end up removing current accessories.
        let accessories = MacAccessoryReader.readAccessoryBatteries()
        for accessory in accessories {
            iCloudSyncManager.shared.updateDevice(accessory)
        }
    }
    
    @objc private func menuBarClicked() {
        // Handled by menu popup automatically
    }
    
    @objc private func openApp() {
        // Show main window (standard Appdelegate trigger)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
