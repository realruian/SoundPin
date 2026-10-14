import Foundation
import CoreAudio

@MainActor enum PreviewSupport {
    static func manager(listeningModes: Bool = false, delayedModes: Bool = false, battery: Bool = false) -> AudioManager {
        L10n.persistsSetting = false
        let audio = SimulatedAudioService()
        func device(_ id: UInt32, _ name: String, _ type: AudioDeviceType) -> AudioDevice {
            AudioDevice(id: id, uid: battery && id == 9001 ? "AA-BB-CC-DD-EE-FF:output" : "demo-\(id)", name: name, type: type,
                        transportType: id == 9001 ? kAudioDeviceTransportTypeBluetooth : nil)
        }
        audio.devices = [device(9001, "AirPods Pro", .output),
                         device(9002, "MacBook Pro Speakers", .output),
                         device(9003, "Studio Display Speakers", .output),
                         device(9004, "Shure MV7+", .input),
                         device(9005, "AirPods Pro", .input),
                         device(9006, "MacBook Pro Microphone", .input)]
        audio.defaults = [.input: 9004, .output: 9001]
        let preferences = MemoryPreferences()
        let priority = PriorityManager(defaults: preferences)
        priority.rememberDevices([.disconnected(uid: "demo-gone", name: "Old Speaker", type: .output)])
        let modes = SimulatedListeningModes()
        if listeningModes { modes.states[battery ? "AA-BB-CC-DD-EE-FF:output" : "demo-9001"] = ListeningModeState(currentRawValue: 2, supportedMask: 7) }
        modes.appliesImmediately = !delayedModes
        return AudioManager(deviceService: audio, listeningModeService: modes, priorityManager: priority,
                            batteryService: battery ? PreviewBattery() : nil)
    }
}

private struct PreviewBattery: DeviceBatteryProviding {
    func readBatteries() async -> [String: DeviceBattery]? {
        ["aabbccddeeff": DeviceBattery(left: 85, right: 73, chargingCase: 91)!]
    }
}
