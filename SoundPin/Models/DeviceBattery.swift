import Foundation
import CoreAudio

/// Values reported by macOS, not an independent measurement of the accessory.
struct DeviceBattery: Equatable {
    let main: Int?
    let left: Int?
    let right: Int?
    let chargingCase: Int?

    init?(main: Int? = nil, left: Int? = nil, right: Int? = nil, chargingCase: Int? = nil) {
        func valid(_ value: Int?) -> Int? { value.flatMap { (0...100).contains($0) ? $0 : nil } }
        self.main = valid(main); self.left = valid(left); self.right = valid(right)
        self.chargingCase = valid(chargingCase)
        guard self.main != nil || self.left != nil || self.right != nil || self.chargingCase != nil else { return nil }
    }

    var earLevel: Int? { [left, right].compactMap { $0 }.min() ?? main }
    var displayLevel: Int { earLevel ?? chargingCase ?? 0 }
    var compactText: String { earLevel == nil ? L10n.batteryCaseShort(displayLevel) : "\(displayLevel)%" }
    var symbol: String {
        switch displayLevel {
        case 0...10: return "battery.0percent"
        case 11...37: return "battery.25percent"
        case 38...62: return "battery.50percent"
        case 63...87: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
    var details: String {
        [(L10n.batteryDevice, main), (L10n.batteryLeft, left), (L10n.batteryRight, right), (L10n.batteryCase, chargingCase)]
            .compactMap { label, value in value.map { "\(label) \($0)%" } }.joined(separator: L10n.listSeparator)
    }

    /// Match only an exact hardware address, never a possibly duplicated device name.
    static func address(_ value: String) -> String? {
        let pattern = "^(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$"
        guard value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return value.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").lowercased()
    }
    static func address(for device: AudioDevice) -> String? {
        guard device.isConnected, device.transportType == kAudioDeviceTransportTypeBluetooth
                || device.transportType == kAudioDeviceTransportTypeBluetoothLE else { return nil }
        var uid = device.uid
        for suffix in [":input", ":output"] where uid.hasSuffix(suffix) { uid.removeLast(suffix.count) }
        return address(uid)
    }

    /// system_profiler's battery fields are best-effort report data. Unknown
    /// shapes/values are omitted; disconnected entries must never supply a level.
    static func parseReport(_ data: Data) -> [String: DeviceBattery]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        var result: [String: DeviceBattery] = [:]
        var conflicts: Set<String> = []
        func percent(_ value: Any?) -> Int? {
            guard let value = value as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.range(of: "^[0-9]{1,3}%?$", options: .regularExpression) != nil else { return nil }
            return Int(trimmed.replacingOccurrences(of: "%", with: ""))
        }
        for controller in controllers {
            guard let connected = controller["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for value in entry.values {
                    guard let device = value as? [String: Any], let raw = device["device_address"] as? String,
                          let key = address(raw), !conflicts.contains(key),
                          let battery = DeviceBattery(main: percent(device["device_batteryLevelMain"]),
                                                      left: percent(device["device_batteryLevelLeft"]),
                                                      right: percent(device["device_batteryLevelRight"]),
                                                      chargingCase: percent(device["device_batteryLevelCase"])) else { continue }
                    if let previous = result[key], previous != battery {
                        result.removeValue(forKey: key); conflicts.insert(key)
                    } else { result[key] = battery }
                }
            }
        }
        return result
    }
}

protocol DeviceBatteryProviding {
    func readBatteries() async -> [String: DeviceBattery]?
}
