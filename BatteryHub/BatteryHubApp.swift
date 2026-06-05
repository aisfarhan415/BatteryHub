import SwiftUI

@main
struct BatteryHubApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(BatteryHubAppDelegate.self) private var appDelegate
    #endif

    #if os(macOS)
    private let menuBarController = MenuBarController()
    private let accessorySyncService = MacAccessorySyncService.shared
    #endif

    #if os(iOS)
    private let mobileBatteryReporter = MobileBatteryReporter.shared
    @Environment(\.scenePhase) private var scenePhase
    #endif

    #if os(watchOS)
    private let watchBatteryReporter = WatchBatteryReporter()
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .onAppear {
                    accessorySyncService.start()
                }
                #endif
                #if os(iOS)
                .onAppear {
                    WatchConnectivityBridge.shared.start()
                    appDelegate.scheduleRefresh()
                    MobileBatteryReporter.shared.publishNow()
                    iCloudSyncManager.shared.loadDevices()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        MobileBatteryReporter.shared.publishNow()
                        iCloudSyncManager.shared.loadDevices()
                    case .background:
                        MobileBatteryReporter.shared.publishNow()
                        appDelegate.scheduleRefresh()
                    default:
                        break
                    }
                }
                #endif
        }
    }
}

#if os(iOS)
import UIKit
import BackgroundTasks

final class BatteryHubAppDelegate: NSObject, UIApplicationDelegate {
    private let refreshTaskId = "Elevant.BatteryHub.refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerBackgroundTasks()
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        scheduleRefresh()
        return true
    }

    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        MobileBatteryReporter.shared.publishNow()
        iCloudSyncManager.shared.loadDevices()
        completionHandler(.newData)
    }

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskId, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleRefresh(task: task)
        }
    }

    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("BGTask submit failed: \(error)")
        }
    }

    private func handleRefresh(task: BGAppRefreshTask) {
        scheduleRefresh()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        let op = BlockOperation {
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.main.async {
                MobileBatteryReporter.shared.publishNow()
                iCloudSyncManager.shared.loadDevices()
                group.leave()
            }
            _ = group.wait(timeout: .now() + 10)
        }

        task.expirationHandler = {
            queue.cancelAllOperations()
        }

        op.completionBlock = {
            task.setTaskCompleted(success: !op.isCancelled)
        }

        queue.addOperation(op)
    }
}
#endif
