import Foundation

#if os(macOS)

public class MacAccessoryReader {
    public static func readAccessoryBatteries() -> [DeviceBattery] {
        let output = runSystemProfilerBluetooth()
        return parseBluetoothDevices(output)
    }

    private static func runSystemProfilerBluetooth() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            print("MacAccessoryReader process run error: \(error)")
            return ""
        }

        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func inferDeviceType(_ name: String, minorType: String?) -> String {
        let lowerName = name.lowercased()
        let lowerMinor = (minorType ?? "").lowercased()

        if lowerName.contains("airpods") || lowerName.contains("buds") || lowerName.contains("headphone") || lowerName.contains("headset") || lowerMinor.contains("headphones") || lowerMinor.contains("headset") {
            return "airpods"
        }
        if lowerName.contains("watch") || lowerMinor.contains("watch") {
            return "watch"
        }
        if lowerName.contains("pencil") {
            return "pencil"
        }
        if lowerName.contains("keyboard") || lowerMinor.contains("keyboard") {
            return "keyboard"
        }
        if lowerName.contains("mouse") || lowerName.contains("trackpad") || lowerMinor.contains("mouse") || lowerMinor.contains("trackpad") {
            return "mouse"
        }
        
        if lowerName.contains("iphone") || lowerMinor.contains("phone") {
            return "iphone"
        }
        if lowerName.contains("ipad") || lowerMinor.contains("tablet") {
            return "ipad"
        }
        
        return "accessory"
    }

    private static func resolveDisplayName(_ name: String, inferredType: String, minorType: String?) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMinor = (minorType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerName = trimmedName.lowercased()

        // Keep the original reported name whenever it is already specific.
        if !trimmedName.isEmpty && lowerName != "iphone" && lowerName != "ipad" {
            return trimmedName
        }

        if (inferredType == "iphone" || inferredType == "ipad"), !trimmedMinor.isEmpty {
            // Fallback for generic names from system_profiler output.
            return "\(inferredType.capitalized) (\(trimmedMinor))"
        }

        if !trimmedName.isEmpty {
            return trimmedName
        }

        return inferredType.capitalized
    }

    private static func parseBluetoothDevices(_ stdout: String) -> [DeviceBattery] {
        struct WorkingDevice {
            var name: String
            var isConnected: Bool
            var batteryLevel: Int?
            var leftBattery: Int?
            var rightBattery: Int?
            var caseBattery: Int?
            var minorType: String?
        }

        var results: [WorkingDevice] = []
        var current: WorkingDevice?
        var connectedSection = false

        let lines = stdout.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if line.hasPrefix("      Connected:") {
                connectedSection = true
                continue
            }
            if line.hasPrefix("      Not Connected:") {
                connectedSection = false
                continue
            }
            if line.hasPrefix("Bluetooth:") {
                continue
            }

            let leadingSpaces = line.count - line.trimmingCharacters(in: .whitespaces).count

            if leadingSpaces == 10 && trimmed.hasSuffix(":") {
                if let current {
                    results.append(current)
                }

                let name = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                current = WorkingDevice(name: name, isConnected: connectedSection)
                continue
            }

            if leadingSpaces == 14, var working = current {
                let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }

                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)

                if key.contains("Battery Level") || key.contains("Battery") {
                    let numeric = value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                    if let pct = Int(numeric) {
                        if key.hasPrefix("Left") {
                            working.leftBattery = pct
                        } else if key.hasPrefix("Right") {
                            working.rightBattery = pct
                        } else if key.hasPrefix("Case") {
                            working.caseBattery = pct
                        } else {
                            working.batteryLevel = pct
                        }
                    }
                } else if key == "Minor Type" || key == "Device Type" {
                    working.minorType = value
                }

                current = working
            }
        }

        if let current {
            results.append(current)
        }

        let mapped: [DeviceBattery] = results.compactMap { item in
            let hasBatteryInfo = item.batteryLevel != nil || item.leftBattery != nil || item.rightBattery != nil || item.caseBattery != nil
            guard hasBatteryInfo || item.isConnected else {
                return nil
            }

            let avgBattery: Int
            if let level = item.batteryLevel {
                avgBattery = level
            } else {
                let parts = [item.leftBattery, item.rightBattery, item.caseBattery].compactMap { $0 }
                avgBattery = parts.isEmpty ? 100 : Int(Double(parts.reduce(0, +)) / Double(parts.count))
            }

            let deviceType = inferDeviceType(item.name, minorType: item.minorType)
            let displayName = resolveDisplayName(item.name, inferredType: deviceType, minorType: item.minorType)

            return DeviceBattery(
                id: "macacc_\(displayName.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression))",
                name: displayName,
                type: deviceType,
                batteryLevel: max(0, min(100, avgBattery)),
                chargingStatus: "discharging",
                timeRemaining: nil,
                lastUpdated: Date(),
                leftBattery: item.leftBattery,
                rightBattery: item.rightBattery,
                caseBattery: item.caseBattery
            )
        }

        return mapped
    }
}

#endif
