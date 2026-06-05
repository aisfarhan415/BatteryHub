import Foundation
import IOKit.ps

public class MacBatteryReader {
    
    public struct BatteryStatus {
        public let level: Int
        public let chargingStatus: String // "charging", "discharging", "charged"
        public let timeRemaining: String?
    }
    
    public static func readCurrentBattery() -> BatteryStatus {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] {
                let name = description[kIOPSNameKey] as? String ?? ""
                
                // We target the internal MacBook battery
                if name.contains("InternalBattery") {
                    let level = description[kIOPSCurrentCapacityKey] as? Int ?? 100
                    let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
                    
                    // Determine charging state
                    var chargingStatus = "discharging"
                    if isCharging {
                        chargingStatus = "charging"
                    } else if level == 100 {
                        chargingStatus = "charged"
                    }
                    
                    // Parse remaining time if discharging
                    var timeStr: String? = nil
                    if !isCharging && chargingStatus != "charged" {
                        if let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int, timeToEmpty > 0 {
                            let hours = timeToEmpty / 60
                            let minutes = timeToEmpty % 60
                            timeStr = String(format: "%dh %02dm", hours, minutes)
                        }
                    }
                    
                    return BatteryStatus(level: level, chargingStatus: chargingStatus, timeRemaining: timeStr)
                }
            }
        }
        
        // Fallback standard
        return BatteryStatus(level: 100, chargingStatus: "charged", timeRemaining: nil)
    }
}
