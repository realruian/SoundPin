import Foundation
import CoreAudio

@MainActor private final class BatteryFixture: DeviceBatteryProviding {
    var result: [String: DeviceBattery]? = [:]
    var reads = 0
    var suspended = false
    var resume: CheckedContinuation<[String: DeviceBattery]?, Never>?
    func readBatteries() async -> [String: DeviceBattery]? {
        reads += 1
        if suspended { return await withCheckedContinuation { resume = $0 } }
        return result
    }
}

@main struct BatteryCheckMain {
    @MainActor static func main() async {
        L10n.persistsSetting = false
        L10n.setting = .english
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message); checks += 1; print("ok: \(message)")
        }
        let address = "aabbccddeeff"
        let pods = AudioDevice(id: 9, uid: "AA-BB-CC-DD-EE-FF:output", name: "Same Name", type: .output,
                               transportType: kAudioDeviceTransportTypeBluetooth)
        check(DeviceBattery.address(for: pods) == address, "HAL endpoint matches normalized Bluetooth address")
        check(DeviceBattery.address("AA:BB:CC:DD:EE:FF") == address, "colon-separated address matches")
        check(DeviceBattery.address("prefix-AA-BB-CC-DD-EE-FF") == nil, "substring address does not match unrelated UID")
        check(DeviceBattery.address(for: .disconnected(uid: pods.uid, name: pods.name, type: .output)) == nil,
              "offline device never displays a cached battery")
        let usb = AudioDevice(id: 10, uid: pods.uid, name: pods.name, type: .output, transportType: kAudioDeviceTransportTypeUSB)
        check(DeviceBattery.address(for: usb) == nil, "non-Bluetooth device never matches by UID alone")
        let low = DeviceBattery(left: 80, right: 45, chargingCase: 100)!
        check(low.displayLevel == 45 && low.compactText == "45%", "lower earbud level is displayed")
        check(low.details.contains("Left 80%") && low.details.contains("Right 45%") && low.details.contains("Case 100%"), "component values remain available")
        check(DeviceBattery(chargingCase: 90)?.compactText == "Case 90%", "case-only reading is explicitly labeled")
        check(DeviceBattery(main: 0)?.displayLevel == 0, "zero percent is a valid reading")
        check(DeviceBattery(main: 101, left: -1) == nil, "invalid percentages are not displayed")
        func report(_ connected: [[String: Any]], disconnected: [[String: Any]] = []) -> Data {
            try! JSONSerialization.data(withJSONObject: ["SPBluetoothDataType": [["device_connected": connected, "device_not_connected": disconnected]]])
        }
        let entry: [String: Any] = ["Same Name": ["device_address":"AA:BB:CC:DD:EE:FF", "device_batteryLevelLeft":"80%", "device_batteryLevelRight":"45%", "device_batteryLevelCase":"100%"]]
        let other: [String: Any] = ["Same Name": ["device_address":"11:22:33:44:55:66", "device_batteryLevelMain":"10%"]]
        let parsed = DeviceBattery.parseReport(report([entry, other]))!
        check(parsed[address] == low && parsed.count == 2, "same-name devices remain separate by address")
        check(DeviceBattery.parseReport(report([], disconnected: [entry]))?.isEmpty == true, "disconnected system report entries are ignored")
        let malformed: [String: Any] = ["X": ["device_address":"AA:BB:CC:DD:EE:FF", "device_batteryLevelMain":"unknown", "device_batteryLevelLeft":"200%", "device_batteryLevelRight":true]]
        check(DeviceBattery.parseReport(report([malformed]))?.isEmpty == true, "malformed and unsupported battery values are omitted")
        let conflict: [String: Any] = ["X": ["device_address":"AA:BB:CC:DD:EE:FF", "device_batteryLevelMain":"12%"]]
        check(DeviceBattery.parseReport(report([entry, conflict, entry]))?.isEmpty == true, "conflicting reports cannot overwrite each other")
        check(DeviceBattery.parseReport(Data("{}".utf8)) == nil, "unknown report schema is a read failure")
        check(DeviceBattery.parseReport(Data("{".utf8)) == nil, "truncated report is a read failure")
        check(DeviceBattery.parseReport(report([entry, entry]))?.count == 1, "identical repeated report is deduplicated")

        let audio = SimulatedAudioService(); audio.devices = [pods]; audio.defaults[.output] = pods.id
        let preferences = MemoryPreferences(); preferences.set(true, forKey: "customMode")
        let battery = BatteryFixture(); battery.result = [address:low, "112233445566": DeviceBattery(main: 10)!]
        let manager = AudioManager(deviceService: audio, listeningModeService: SimulatedListeningModes(),
                                   priorityManager: PriorityManager(defaults: preferences), writer: InlineAudioWriter(),
                                   batteryService: battery)
        let start = Date()
        await manager.refreshBatteryLevels(now: start)
        check(manager.battery(for: pods) == low && manager.batteryLevels.count == 1, "only current audio endpoints receive battery values")
        await manager.refreshBatteryLevels(now: start.addingTimeInterval(20))
        check(battery.reads == 1, "repeated panel opens are throttled")
        battery.result = nil
        await manager.refreshBatteryLevels(now: start.addingTimeInterval(61))
        check(manager.battery(for: pods) == nil, "failed refresh removes stale data")
        battery.result = [address:low]
        await manager.refreshBatteryLevels(now: start.addingTimeInterval(122))
        check(manager.battery(for: pods) == low, "later successful read recovers")
        battery.suspended = true
        let pending = Task { await manager.refreshBatteryLevels(now: start.addingTimeInterval(183)) }
        while battery.resume == nil { await Task.yield() }
        await manager.refreshBatteryLevels(now: start.addingTimeInterval(244))
        check(battery.reads == 4, "overlapping refreshes share one in-flight request")
        check(manager.batteryLevels.isEmpty, "expired values disappear during a slow refresh")
        audio.devices = []; manager.refreshDevices()
        audio.devices = [pods]; manager.refreshDevices()
        battery.resume?.resume(returning: [address:low]); await pending.value
        check(manager.battery(for: pods) == nil, "late result cannot survive disconnect and reconnect")
        battery.suspended = false
        await manager.refreshBatteryLevels(now: start.addingTimeInterval(245))
        check(manager.battery(for: pods) == low, "reconnected device obtains a fresh sample")
        audio.inventoryAvailable = false; manager.refreshDevices()
        check(manager.battery(for: pods) == nil, "unavailable audio inventory hides battery")
        check(audio.writes.isEmpty, "battery reads do not switch audio routes")
        let timeoutStart = Date()
        let timeoutData = await Task.detached { BluetoothBatteryService.reportData(executable: "/bin/sleep", arguments: ["5"], timeout: 0.1) }.value
        check(timeoutData == nil && Date().timeIntervalSince(timeoutStart) < 2, "hung report process is bounded and rejected")
        check(BluetoothBatteryService.reportData(executable: "/nonexistent/soundpin-test") == nil, "launch failure is handled")
        if CommandLine.arguments.contains("--live") {
            let result = await BluetoothBatteryService().readBatteries()
            check(result != nil, "live macOS Bluetooth report parsed")
            print("Live battery records: \(result?.count ?? 0)")
        }
        print("All \(checks) battery checks passed.")
    }
}
