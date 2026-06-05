//
//  BatteryHubWatchApp.swift
//  BatteryHubWatch Watch App
//
//  Created by Ais Farhan on 6/1/26.
//

import SwiftUI
#if os(watchOS)
import WatchKit
import WatchConnectivity
#endif

@main
struct BatteryHubWatch_Watch_AppApp: App {
    private let watchBatteryReporter = WatchBatteryReporter.shared
    #if os(watchOS)
    @WKApplicationDelegateAdaptor(WatchExtensionDelegate.self) private var extensionDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#if os(watchOS)
final class WatchExtensionDelegate: NSObject, WKApplicationDelegate {
    private let reporter = WatchBatteryReporter.shared
    private let wcDelegate = WatchSessionBootstrap.shared

    func applicationDidBecomeActive() {
        wcDelegate.activate()
        reporter.publishNow()
        scheduleNextRefresh()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        reporter.publishNow()
        iCloudSyncManager.shared.loadDevices()
        scheduleNextRefresh()

        for task in backgroundTasks {
            task.setTaskCompletedWithSnapshot(false)
        }
    }

    private func scheduleNextRefresh() {
        let preferredDate = Date().addingTimeInterval(15 * 60)
        WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: preferredDate, userInfo: nil) { _ in }
    }
}

final class WatchSessionBootstrap: NSObject, WCSessionDelegate {
    static let shared = WatchSessionBootstrap()
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
#endif
