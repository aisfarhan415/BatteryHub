import Foundation

public struct DeviceBattery: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var type: String // "macbook", "iphone", "ipad", "watch", "pencil", "airpods"
    public var batteryLevel: Int
    public var chargingStatus: String // "charging", "discharging", "charged"
    public var timeRemaining: String?
    public var lastUpdated: Date
    
    // Supporting multi-battery devices (like AirPods)
    public var leftBattery: Int?
    public var rightBattery: Int?
    public var caseBattery: Int?

    public init(id: String, name: String, type: String, batteryLevel: Int, chargingStatus: String, timeRemaining: String? = nil, lastUpdated: Date = Date(), leftBattery: Int? = nil, rightBattery: Int? = nil, caseBattery: Int? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.batteryLevel = batteryLevel
        self.chargingStatus = chargingStatus
        self.timeRemaining = timeRemaining
        self.lastUpdated = lastUpdated
        self.leftBattery = leftBattery
        self.rightBattery = rightBattery
        self.caseBattery = caseBattery
    }
}
