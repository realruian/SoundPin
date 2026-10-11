import Foundation
import CoreAudio

/// Only lstm is written. This service never changes routing, priority or volume.
final class ListeningModeService {
    var onChange: (() -> Void)?
    private struct Observation {
        let id: AudioObjectID
        let selector: AudioObjectPropertySelector
        let block: AudioObjectPropertyListenerBlock
    }
    private var observations: [Observation] = []
    private var observedDevices: [String: AudioObjectID] = [:]
    private static let mode: UInt32 = 0x6C73746D // lstm
    private static let modes: UInt32 = 0x6C736D73 // lsms

    private func address(_ selector: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func read(_ id: AudioObjectID, _ selector: UInt32) -> UInt32? {
        var a = address(selector), size: UInt32 = 0
        guard AudioObjectHasProperty(id, &a),
              AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size == 4 else { return nil }
        var value: UInt32 = 0
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr, size == 4 else { return nil }
        return value
    }

    private func hasIdentity(of device: AudioDevice) -> Bool {
        guard device.isConnected, device.type == .output,
              device.name.localizedCaseInsensitiveContains("AirPods"),
              device.transportType == kAudioDeviceTransportTypeBluetooth else { return false }
        var a = address(kAudioDevicePropertyDeviceUID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device.id, &a, 0, nil, &size, &value) == noErr,
              let value else { return false }
        return value.takeRetainedValue() as String == device.uid
    }

    func state(for device: AudioDevice) -> ListeningModeState? {
        guard hasIdentity(of: device) else { return nil }
        var a = address(Self.mode), settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device.id, &a, &settable) == noErr, settable.boolValue,
              let current = read(device.id, Self.mode), let supported = read(device.id, Self.modes) else { return nil }
        let state = ListeningModeState(currentRawValue: current, supportedMask: supported)
        return state.supported.isEmpty ? nil : state
    }

    /// Success means HAL accepted the request. The caller refreshes from the system;
    /// it must not claim that a cache echo is confirmation from the headphones.
    func request(_ mode: ListeningMode, for device: AudioDevice) -> Bool {
        guard let current = state(for: device), current.supported.contains(mode) else { return false }
        var a = address(Self.mode), value = mode.rawValue
        return AudioObjectSetPropertyData(device.id, &a, 0, nil, 4, &value) == noErr
    }

    /// Observe both properties, including devices whose capability reads temporarily
    /// fail. Device-list notifications replace these observations on disconnect/reconnect.
    func observe(_ devices: [AudioDevice]) {
        let eligible = devices.filter { hasIdentity(of: $0) }
        let next = Dictionary(eligible.map { ($0.uid, $0.id) }, uniquingKeysWith: { first, _ in first })
        guard next != observedDevices else { return }
        stopObserving()
        observedDevices = next
        for id in next.values {
            for selector in [Self.mode, Self.modes] {
                var a = address(selector)
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.onChange?() }
                if AudioObjectAddPropertyListenerBlock(id, &a, DispatchQueue.main, block) == noErr {
                    observations.append(Observation(id: id, selector: selector, block: block))
                }
            }
        }
    }

    private func stopObserving() {
        for observation in observations {
            var a = address(observation.selector)
            AudioObjectRemovePropertyListenerBlock(observation.id, &a, DispatchQueue.main, observation.block)
        }
        observations = []
        observedDevices = [:]
    }

    deinit { stopObserving() }
}
