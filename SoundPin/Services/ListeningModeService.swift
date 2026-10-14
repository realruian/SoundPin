import Foundation
import CoreAudio

/// The hardware boundary makes registration failures and UID reuse testable without HAL writes.
protocol ListeningModeHardwareProviding: AnyObject {
    func hasIdentity(of device: AudioDevice) -> Bool
    func read(_ id: AudioObjectID, _ selector: UInt32) -> UInt32?
    func isSettable(_ id: AudioObjectID, _ selector: UInt32) -> Bool
    func write(_ value: UInt32, to id: AudioObjectID, selector: UInt32) -> Bool
    /// A successful registration returns its exact removal operation.
    func observe(_ id: AudioObjectID, selector: UInt32, onChange: @escaping () -> Void) -> (() -> Void)?
}

/// Only lstm is written. This service never changes routing, priority or volume.
final class ListeningModeService: ListeningModeProviding {
    var onChange: (() -> Void)?
    private(set) var needsObservationRecovery = false
    private struct ObservationKey: Hashable {
        let uid: String
        let id: AudioObjectID
        let selector: UInt32
    }
    private var observations: [ObservationKey: () -> Void] = [:]
    private let hardware: ListeningModeHardwareProviding
    private static let mode: UInt32 = 0x6C73746D // lstm
    private static let modes: UInt32 = 0x6C736D73 // lsms

    init(hardware: ListeningModeHardwareProviding = CoreAudioListeningModeHardware()) {
        self.hardware = hardware
    }

    func state(for device: AudioDevice) -> ListeningModeState? {
        guard device.isListeningModeCandidate, hardware.hasIdentity(of: device),
              hardware.isSettable(device.id, Self.mode),
              let current = hardware.read(device.id, Self.mode),
              let supported = hardware.read(device.id, Self.modes),
              hardware.hasIdentity(of: device) else { return nil }
        let state = ListeningModeState(currentRawValue: current, supportedMask: supported)
        return state.supported.isEmpty ? nil : state
    }

    /// Success means HAL accepted the request, not a hardware acknowledgement.
    func request(_ mode: ListeningMode, for device: AudioDevice) -> Bool {
        guard let current = state(for: device), current.supported.contains(mode),
              hardware.hasIdentity(of: device) else { return false }
        return hardware.write(mode.rawValue, to: device.id, selector: Self.mode)
    }

    /// Retain successful listeners and retry only missing registrations. Same device
    /// IDs do not imply both properties were registered successfully last time.
    func observe(_ devices: [AudioDevice]) {
        let candidates = devices.filter(\.isListeningModeCandidate)
        let eligible = candidates.filter { hardware.hasIdentity(of: $0) }
        let desired = Set(eligible.flatMap { device in
            [Self.mode, Self.modes].map { ObservationKey(uid: device.uid, id: device.id, selector: $0) }
        })
        for key in Array(observations.keys) where !desired.contains(key) {
            observations.removeValue(forKey: key)?()
        }
        for key in desired where observations[key] == nil {
            if let remove = hardware.observe(key.id, selector: key.selector, onChange: { [weak self] in
                self?.onChange?()
            }) {
                observations[key] = remove
            }
        }
        needsObservationRecovery = eligible.count != candidates.count || observations.count != desired.count
    }

    deinit { for remove in observations.values { remove() } }
}

final class CoreAudioListeningModeHardware: ListeningModeHardwareProviding {
    private func address(_ selector: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    func hasIdentity(of device: AudioDevice) -> Bool {
        guard device.isListeningModeCandidate else { return false }
        var a = address(kAudioDevicePropertyDeviceUID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device.id, &a, 0, nil, &size, &value) == noErr,
              let value else { return false }
        return value.takeRetainedValue() as String == device.uid
    }

    func read(_ id: AudioObjectID, _ selector: UInt32) -> UInt32? {
        var a = address(selector), size: UInt32 = 0
        guard AudioObjectHasProperty(id, &a),
              AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size == 4 else { return nil }
        var value: UInt32 = 0
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr, size == 4 else { return nil }
        return value
    }

    func isSettable(_ id: AudioObjectID, _ selector: UInt32) -> Bool {
        var a = address(selector), settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &a, &settable) == noErr && settable.boolValue
    }

    func write(_ value: UInt32, to id: AudioObjectID, selector: UInt32) -> Bool {
        var a = address(selector), mutableValue = value
        return AudioObjectSetPropertyData(id, &a, 0, nil, 4, &mutableValue) == noErr
    }

    func observe(_ id: AudioObjectID, selector: UInt32, onChange: @escaping () -> Void) -> (() -> Void)? {
        var a = address(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        guard AudioObjectAddPropertyListenerBlock(id, &a, DispatchQueue.main, block) == noErr else { return nil }
        return { [self] in
            var a = address(selector)
            AudioObjectRemovePropertyListenerBlock(id, &a, DispatchQueue.main, block)
        }
    }
}
