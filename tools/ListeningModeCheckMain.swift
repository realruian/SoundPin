import Foundation
import CoreAudio

@main struct ListeningModeCheckMain {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { print("FAIL: \(name)"); exit(1) }
            count += 1
            print("ok: \(name)")
        }
        let all = ListeningModeState(currentRawValue: 2, supportedMask: 7)
        check(all.supported == [.transparency, .adaptive, .noiseCancellation], "system menu order")
        check(all.current == .noiseCancellation, "current noise cancellation")
        check(ListeningModeState(currentRawValue: 4, supportedMask: 3).supported == [.transparency, .noiseCancellation], "no adaptive row without support")
        check(ListeningModeState(currentRawValue: 4, supportedMask: 3).current == nil, "unsupported current value is not shown as selected")
        check(ListeningModeState(currentRawValue: 1, supportedMask: 7).current == nil, "off does not masquerade as a tested mode")
        check(ListeningModeState(currentRawValue: 99, supportedMask: 7).current == nil, "future current value stays unknown")
        check(ListeningModeState(currentRawValue: 2, supportedMask: 0).supported.isEmpty, "empty support mask")
        check(ListeningModeState(currentRawValue: 3, supportedMask: 0x80000002).supported == [.transparency], "unknown support bits ignored")
        let service = ListeningModeService()
        let offline = AudioDevice.disconnected(uid: "check", name: "AirPods Pro 3", type: .output)
        check(service.state(for: offline) == nil && !service.request(.transparency, for: offline), "disconnected device rejected before write")
        let input = AudioDevice(id: 0, uid: "check", name: "AirPods Pro 3", type: .input)
        check(service.state(for: input) == nil && !service.request(.transparency, for: input), "microphone endpoint rejected before write")
        let other = AudioDevice(id: 0, uid: "check", name: "Speakers", type: .output)
        check(service.state(for: other) == nil && !service.request(.transparency, for: other), "non-AirPods device rejected before write")
        service.observe([offline, input, other])
        service.observe([])
        let pods = AudioDevice(id: 101, uid: "pods", name: "AirPods Pro", type: .output,
                               transportType: kAudioDeviceTransportTypeBluetooth)
        let mode: UInt32 = 0x6C73746D, modes: UInt32 = 0x6C736D73
        do {
            let hardware = SimulatedModeHardware()
            hardware.identities[pods.id] = pods.uid
            hardware.failedSelectors = [modes]
            let observer = ListeningModeService(hardware: hardware)
            observer.observe([pods])
            check(observer.needsObservationRecovery && hardware.active.count == 1, "partial listener registration remains recoverable")
            observer.observe([pods])
            check(hardware.addAttempts.filter { $0 == mode }.count == 1
                  && hardware.addAttempts.filter { $0 == modes }.count == 2, "same topology retries only missing property listener")
            hardware.failedSelectors = []
            observer.observe([pods])
            check(!observer.needsObservationRecovery && hardware.active.count == 2, "listener failure recovers without reconnect")
            let attempts = hardware.addAttempts.count
            observer.observe([pods, pods])
            check(hardware.addAttempts.count == attempts && hardware.active.count == 2, "successful listeners are not duplicated")
            var changes = 0
            observer.onChange = { changes += 1 }
            hardware.active.values.forEach { $0() }
            check(changes == 2, "both registered properties deliver changes")
            observer.observe([])
            check(hardware.active.isEmpty && hardware.removed.count == 2, "disconnect removes each successful registration")
        }
        do {
            let hardware = SimulatedModeHardware()
            hardware.identities[pods.id] = pods.uid
            var observer: ListeningModeService? = ListeningModeService(hardware: hardware)
            observer?.observe([pods])
            hardware.identities[pods.id] = "replacement"
            let replacement = AudioDevice(id: pods.id, uid: "replacement", name: pods.name, type: .output,
                                          transportType: kAudioDeviceTransportTypeBluetooth)
            observer?.observe([replacement])
            check(hardware.removed.count == 2 && hardware.active.count == 2 && hardware.addAttempts.count == 4,
                  "same HAL id with new UID replaces old registrations")
            observer = nil
            check(hardware.active.isEmpty && hardware.removed.count == 4, "service teardown releases remaining listeners")
        }
        do {
            let hardware = SimulatedModeHardware()
            let service = ListeningModeService(hardware: hardware)
            service.observe([pods])
            check(service.needsObservationRecovery && hardware.addAttempts.isEmpty,
                  "temporary identity failure requests recovery without registering unknown endpoint")
            hardware.identities[pods.id] = pods.uid
            service.observe([pods])
            check(!service.needsObservationRecovery && hardware.active.count == 2,
                  "identity read recovery installs listeners on unchanged topology")
            check(service.state(for: pods)?.current == .noiseCancellation, "injected hardware state uses actual capability mask")
            check(service.request(.transparency, for: pods) && hardware.writes.count == 1,
                  "supported request writes only the mode property")
            hardware.values[modes] = 3
            check(!service.request(.adaptive, for: pods) && hardware.writes.count == 1,
                  "unsupported mode never reaches hardware write")
            hardware.identityReads = 0
            hardware.invalidateIdentityAtRead = 3
            check(!service.request(.transparency, for: pods) && hardware.writes.count == 1,
                  "identity is checked again immediately before mode write")
        }
        do {
            let hardware = SimulatedModeHardware()
            hardware.identities[pods.id] = pods.uid
            let service = ListeningModeService(hardware: hardware)
            let renamed = AudioDevice(id: pods.id, uid: pods.uid, name: "我的耳机", type: .output,
                                      transportType: kAudioDeviceTransportTypeBluetooth,
                                      listeningModeCapable: true)
            check(service.state(for: renamed)?.supported.count == 3,
                  "confirmed HAL capability keeps modes available after a user rename")
            service.observe([renamed])
            check(hardware.active.count == 2 && service.request(.transparency, for: renamed),
                  "renamed supported device retains observation and guarded requests")
            let ordinary = AudioDevice(id: 102, uid: "ordinary", name: "Bluetooth Speaker", type: .output,
                                       transportType: kAudioDeviceTransportTypeBluetooth)
            hardware.identities[ordinary.id] = ordinary.uid
            let writes = hardware.writes.count
            service.observe([renamed, ordinary])
            check(service.state(for: ordinary) == nil && !service.request(.transparency, for: ordinary)
                  && hardware.writes.count == writes && hardware.active.count == 2 && !service.needsObservationRecovery,
                  "ordinary Bluetooth devices neither write nor schedule observation recovery")
            hardware.identities[renamed.id] = "reused-id"
            check(service.state(for: renamed) == nil && !service.request(.transparency, for: renamed)
                  && hardware.writes.count == writes,
                  "renamed capability does not bypass live endpoint identity checks")
        }
        print("\(count) checks passed. No real device writes.")
    }
}

/// These closures and property values live only in this test process.
private final class SimulatedModeHardware: ListeningModeHardwareProviding {
    var identities: [AudioObjectID: String] = [:]
    var values: [UInt32: UInt32] = [0x6C73746D: 2, 0x6C736D73: 7]
    var failedSelectors: Set<UInt32> = []
    var addAttempts: [UInt32] = []
    var active: [UUID: () -> Void] = [:]
    var removed: [UUID] = []
    var writes: [UInt32] = []
    var identityReads = 0
    var invalidateIdentityAtRead: Int?
    func hasIdentity(of device: AudioDevice) -> Bool {
        identityReads += 1
        if identityReads == invalidateIdentityAtRead { identities[device.id] = nil }
        return identities[device.id] == device.uid
    }
    func read(_ id: AudioObjectID, _ selector: UInt32) -> UInt32? { values[selector] }
    func isSettable(_ id: AudioObjectID, _ selector: UInt32) -> Bool { true }
    func write(_ value: UInt32, to id: AudioObjectID, selector: UInt32) -> Bool {
        precondition(selector == 0x6C73746D, "Only listening mode may be written")
        writes.append(value)
        return true
    }
    func observe(_ id: AudioObjectID, selector: UInt32, onChange: @escaping () -> Void) -> (() -> Void)? {
        addAttempts.append(selector)
        guard !failedSelectors.contains(selector) else { return nil }
        let token = UUID()
        active[token] = onChange
        return { [weak self] in
            self?.active[token] = nil
            self?.removed.append(token)
        }
    }
}
