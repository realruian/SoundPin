import Foundation
import CoreAudio
import AudioToolbox

/// Injectable HAL boundary. Tests use the production listener/read/write logic
/// with in-memory properties, without registering or changing real audio devices.
struct AudioDeviceHardware {
    var hasProperty: (AudioObjectID, UnsafePointer<AudioObjectPropertyAddress>) -> Bool = AudioObjectHasProperty
    var getPropertyDataSize: (AudioObjectID, UnsafePointer<AudioObjectPropertyAddress>, UInt32, UnsafeRawPointer?, UnsafeMutablePointer<UInt32>) -> OSStatus = AudioObjectGetPropertyDataSize
    var getPropertyData: (AudioObjectID, UnsafePointer<AudioObjectPropertyAddress>, UInt32, UnsafeRawPointer?, UnsafeMutablePointer<UInt32>, UnsafeMutableRawPointer) -> OSStatus = AudioObjectGetPropertyData
    var setPropertyData: (AudioObjectID, UnsafePointer<AudioObjectPropertyAddress>, UInt32, UnsafeRawPointer?, UInt32, UnsafeRawPointer) -> OSStatus = AudioObjectSetPropertyData
    var isPropertySettable: (AudioObjectID, UnsafePointer<AudioObjectPropertyAddress>, UnsafeMutablePointer<DarwinBoolean>) -> OSStatus = AudioObjectIsPropertySettable
    var addListener: (AudioObjectID, UnsafePointer<AudioObjectPropertyAddress>, DispatchQueue?, @escaping AudioObjectPropertyListenerBlock) -> OSStatus = AudioObjectAddPropertyListenerBlock
    var removeListener: (AudioObjectID, UnsafePointer<AudioObjectPropertyAddress>, DispatchQueue?, @escaping AudioObjectPropertyListenerBlock) -> OSStatus = AudioObjectRemovePropertyListenerBlock
}

class AudioDeviceService: AudioDeviceProviding {
    var onDevicesChanged: (() -> Void)?
    var onMuteOrVolumeChanged: (() -> Void)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var muteVolumeListenerBlock: AudioObjectPropertyListenerBlock?
    private struct ObservedProperty: Hashable {
        let id: AudioObjectID
        let uid: String
        let selector: AudioObjectPropertySelector
        let scope: AudioObjectPropertyScope
        let element: AudioObjectPropertyElement
        var address: AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        }
    }
    private let hardware: AudioDeviceHardware
    private let scheduleRecovery: (TimeInterval, @escaping () -> Void) -> DispatchWorkItem
    private var systemSelectors: Set<AudioObjectPropertySelector> = []
    private var monitoredProperties: Set<ObservedProperty> = []
    private var isListening = false
    private var needsDeviceListenerRecovery = false
    private var needsStateRefreshAfterRecovery = false
    private var restoredListenersNeedRefresh = false
    private var listenerRecovery: DispatchWorkItem?
    private var listenerRecoveryCount = 0
    private let listenerRecoveryDelays: [TimeInterval] = [0.3, 1, 3]
    // Inventory can also be read by background route validation. Only the small
    // capability cache is locked; HAL reads do not block the main-thread path.
    private let listeningModeCacheLock = NSLock()
    private var knownListeningModeUIDs: Set<String> = []
    private var pendingDeviceChange: DispatchWorkItem?
    /// One plug or unplug arrives as several notifications in a row (device list, default
    /// input, default output). They are handled once, after they have stopped coming.
    private let deviceChangeDelay: TimeInterval = 0.1

    init(hardware: AudioDeviceHardware = AudioDeviceHardware(),
         scheduleRecovery: @escaping (TimeInterval, @escaping () -> Void) -> DispatchWorkItem = { delay, action in
             let work = DispatchWorkItem(block: action)
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
             return work
         }) {
        self.hardware = hardware
        self.scheduleRecovery = scheduleRecovery
    }

    /// One incomplete endpoint invalidates this read. Keep the previous display
    /// until a complete snapshot is available; do not interpret errors as unplugging.
    func readInventory() -> DeviceInventory {
        guard let deviceIds = deviceIDs() else { return .unavailable }
        do {
            var devices: [AudioDevice] = []
            for id in deviceIds {
                if let input = try createDevice(id: id, type: .input) { devices.append(input) }
                if let output = try createDevice(id: id, type: .output) { devices.append(output) }
            }
            guard let finalIDs = deviceIDs(), Set(finalIDs) == Set(deviceIds) else { return .unavailable }
            listeningModeCacheLock.lock()
            defer { listeningModeCacheLock.unlock() }
            for index in devices.indices where devices[index].type == .output {
                if devices[index].listeningModeCapable { knownListeningModeUIDs.insert(devices[index].uid) }
                if knownListeningModeUIDs.contains(devices[index].uid) { devices[index].listeningModeCapable = true }
            }
            return .available(devices)
        } catch {
            return .unavailable
        }
    }

    /// The ids of all audio devices. The list is asked for in two steps, its size and then
    /// its content; when a device arrives in between, the second step fails and both are
    /// tried again.
    private func deviceIDs() -> [AudioObjectID]? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)

        for _ in 0..<3 {
            var dataSize: UInt32 = 0
            guard hardware.getPropertyDataSize(system, &propertyAddress, 0, nil, &dataSize) == noErr else { continue }

            let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
            var deviceIds = [AudioObjectID](repeating: 0, count: deviceCount)
            guard deviceCount > 0 else { return [] }
            guard hardware.getPropertyData(system, &propertyAddress, 0, nil, &dataSize, &deviceIds) == noErr else { continue }

            // Fewer than asked for when a device left in between
            return Array(deviceIds.prefix(Int(dataSize) / MemoryLayout<AudioObjectID>.size))
        }
        return nil
    }

    func getCurrentDefaultDevice(type: AudioDeviceType) -> AudioObjectID? {
        let selector: AudioObjectPropertySelector = type == .input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceId: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = hardware.getPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceId
        )

        return status == noErr ? deviceId : nil
    }

    /// False when the system did not accept the device
    @discardableResult
    func setDefaultDevice(_ device: AudioDevice) -> Bool {
        guard device.isConnected, device.id != 0,
              getDeviceUID(id: device.id) == device.uid,
              let current = try? createDevice(id: device.id, type: device.type),
              current.rowID == device.rowID else { return false }
        let deviceId = device.id
        let type = device.type
        let selector: AudioObjectPropertySelector = type == .input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceId = deviceId
        let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = hardware.setPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableDeviceId
        )
        return status == noErr
    }

    func readOutputVolume() -> OutputVolumeState? {
        guard let deviceId = getCurrentDefaultDevice(type: .output), deviceId != 0 else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = hardware.getPropertyData(deviceId, &address, 0, nil, &size, &volume)
        var settable: DarwinBoolean = false
        let capability = hardware.isPropertySettable(deviceId, &address, &settable)
        guard getCurrentDefaultDevice(type: .output) == deviceId else { return nil }
        return OutputVolumeState(deviceID: deviceId,
                                 volume: status == noErr && volume.isFinite ? volume : nil,
                                 isSettable: capability == noErr && settable.boolValue)
    }

    private func isCurrentOutput(_ device: AudioDevice) -> Bool {
        device.type == .output && device.isConnected && device.id != 0
            && getDeviceUID(id: device.id) == device.uid
            && getCurrentDefaultDevice(type: .output) == device.id
    }

    @discardableResult
    func setOutputVolume(_ volume: Float, for device: AudioDevice) -> Bool {
        guard volume.isFinite, (0...1).contains(volume), isCurrentOutput(device) else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var settable: DarwinBoolean = false
        guard hardware.isPropertySettable(device.id, &address, &settable) == noErr,
              settable.boolValue, isCurrentOutput(device) else { return false }
        var value = volume
        return hardware.setPropertyData(device.id, &address, 0, nil,
                                          UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    /// The target is fixed by the volume gesture, never resolved to a new output here.
    @discardableResult
    func unmuteOutput(for device: AudioDevice) -> Bool {
        guard isCurrentOutput(device) else { return false }
        for var address in muteAddresses(device.id, scope: kAudioDevicePropertyScopeOutput) {
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard hardware.getPropertyData(device.id, &address, 0, nil, &size, &muted) == noErr else { return false }
            guard muted != 0 else { continue }
            var settable: DarwinBoolean = false
            guard hardware.isPropertySettable(device.id, &address, &settable) == noErr,
                  settable.boolValue, isCurrentOutput(device) else { return false }
            muted = 0
            guard hardware.setPropertyData(device.id, &address, 0, nil, size, &muted) == noErr,
                  hardware.getPropertyData(device.id, &address, 0, nil, &size, &muted) == noErr,
                  muted == 0 else { return false }
        }
        return true
    }

    /// Reading, unmuting and observation use the same supported mute controls.
    /// Keep the channel fallback even when a separate master control exists.
    private func muteAddresses(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> [AudioObjectPropertyAddress] {
        [kAudioObjectPropertyElementMain, 1].compactMap { element in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                    mScope: scope, mElement: element)
            return hardware.hasProperty(deviceID, &address) ? address : nil
        }
    }

    func isDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        let scope = type == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        for var address in muteAddresses(deviceId, scope: scope) {
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if hardware.getPropertyData(deviceId, &address, 0, nil, &size, &muted) == noErr && muted != 0 {
                return true
            }
        }
        // Some devices represent zero output volume without a mute property.
        return type == .output && getDeviceVolume(deviceId) < 0.01
    }

    func getDeviceVolume(_ deviceId: AudioObjectID) -> Float {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var volume: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)

        let status = hardware.getPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &volume
        )

        return status == noErr ? volume : 1.0
    }

    func startListening() {
        if !isListening {
            isListening = true
            listenerBlock = { [weak self] count, addresses in
                let fired = (0..<Int(count)).map { index -> String in
                    switch addresses[index].mSelector {
                    case kAudioHardwarePropertyDevices: return "devices"
                    case kAudioHardwarePropertyDefaultInputDevice: return "defaultInput"
                    case kAudioHardwarePropertyDefaultOutputDevice: return "defaultOutput"
                    default: return "other"
                    }
                }
                AudioLog.routing.notice("HAL notification: \(fired.joined(separator: ","), privacy: .public)")
                self?.scheduleDeviceChange()
            }
            muteVolumeListenerBlock = { [weak self] _, _ in self?.onMuteOrVolumeChanged?() }
        }
        updateSystemListeners()
        updateMuteVolumeListeners()
    }

    private static let desiredSystemSelectors: Set<AudioObjectPropertySelector> = [
        kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
        kAudioHardwarePropertyDefaultOutputDevice
    ]

    private func updateSystemListeners() {
        guard isListening, let block = listenerBlock else { return }
        for selector in Self.desiredSystemSelectors.subtracting(systemSelectors) {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                    mElement: kAudioObjectPropertyElementMain)
            if hardware.addListener(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block) == noErr {
                systemSelectors.insert(selector)
                if needsStateRefreshAfterRecovery { restoredListenersNeedRefresh = true }
            }
        }
    }

    // Called on the main queue, like the listener blocks.
    private func scheduleDeviceChange() {
        pendingDeviceChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isListening else { return }
            self.pendingDeviceChange = nil
            self.needsStateRefreshAfterRecovery = false
            self.restoredListenersNeedRefresh = false
            self.onDevicesChanged?()
            self.listenerRecovery?.cancel()
            self.listenerRecovery = nil
            self.listenerRecoveryCount = 0
            self.updateSystemListeners()
            self.updateMuteVolumeListeners()
        }
        pendingDeviceChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + deviceChangeDelay, execute: work)
    }

    func updateMuteVolumeListeners() {
        guard isListening, let block = muteVolumeListenerBlock else { return }
        // A failed snapshot must not tear down working observation. Retry independently
        // of AudioManager's inventory retries, including when its own read succeeds.
        guard let deviceIds = deviceIDs() else {
            needsDeviceListenerRecovery = true
            reconcileListenerRecovery()
            return
        }
        // HAL IDs can be reused without an observable empty-inventory interval.
        // An uncertain identity keeps the old registrations until a bounded retry.
        var identities: [AudioObjectID: String] = [:]
        for deviceID in deviceIds {
            guard let uid = getDeviceUID(id: deviceID) else {
                needsDeviceListenerRecovery = true
                reconcileListenerRecovery()
                return
            }
            identities[deviceID] = uid
        }
        var desired: Set<ObservedProperty> = []
        for deviceID in deviceIds {
            guard let uid = identities[deviceID] else { continue }
            for scope in [kAudioDevicePropertyScopeOutput, kAudioDevicePropertyScopeInput] {
                for address in muteAddresses(deviceID, scope: scope) {
                    desired.insert(ObservedProperty(id: deviceID, uid: uid, selector: address.mSelector,
                                                    scope: address.mScope, element: address.mElement))
                }
            }
            var volume = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                    mScope: kAudioDevicePropertyScopeOutput,
                                                    mElement: kAudioObjectPropertyElementMain)
            if hardware.hasProperty(deviceID, &volume) {
                desired.insert(ObservedProperty(id: deviceID, uid: uid, selector: volume.mSelector,
                                                scope: volume.mScope, element: volume.mElement))
            }
        }
        for deviceID in deviceIds where getDeviceUID(id: deviceID) != identities[deviceID] {
            needsDeviceListenerRecovery = true
            reconcileListenerRecovery()
            return
        }
        for property in monitoredProperties.subtracting(desired) {
            var address = property.address
            _ = hardware.removeListener(property.id, &address, DispatchQueue.main, block)
            monitoredProperties.remove(property)
        }
        for property in desired.subtracting(monitoredProperties) {
            var address = property.address
            if hardware.addListener(property.id, &address, DispatchQueue.main, block) == noErr {
                monitoredProperties.insert(property)
                if needsStateRefreshAfterRecovery { restoredListenersNeedRefresh = true }
            }
        }
        needsDeviceListenerRecovery = monitoredProperties != desired
        reconcileListenerRecovery()
    }

    private func reconcileListenerRecovery() {
        guard isListening else { return }
        let needsRecovery = needsDeviceListenerRecovery || systemSelectors != Self.desiredSystemSelectors
        // HAL does not replay missed events. A recovered property must refresh its
        // state even if another property's listener continues to fail.
        let shouldRefresh = restoredListenersNeedRefresh || (!needsRecovery && needsStateRefreshAfterRecovery)
        restoredListenersNeedRefresh = false
        if !needsRecovery {
            listenerRecovery?.cancel()
            listenerRecovery = nil
            listenerRecoveryCount = 0
            needsStateRefreshAfterRecovery = false
        } else {
            needsStateRefreshAfterRecovery = true
            if listenerRecovery == nil, listenerRecoveryCount < listenerRecoveryDelays.count {
                let delay = listenerRecoveryDelays[listenerRecoveryCount]
                listenerRecoveryCount += 1
                listenerRecovery = scheduleRecovery(delay) { [weak self] in
                    guard let self, self.isListening else { return }
                    self.listenerRecovery = nil
                    self.updateSystemListeners()
                    self.updateMuteVolumeListeners()
                }
            }
        }
        if shouldRefresh { onDevicesChanged?() }
    }

    func stopListening() {
        isListening = false
        pendingDeviceChange?.cancel()
        pendingDeviceChange = nil
        listenerRecovery?.cancel()
        listenerRecovery = nil
        listenerRecoveryCount = 0
        needsDeviceListenerRecovery = false
        needsStateRefreshAfterRecovery = false
        restoredListenersNeedRefresh = false
        if let block = muteVolumeListenerBlock {
            for property in monitoredProperties {
                var address = property.address
                _ = hardware.removeListener(property.id, &address, DispatchQueue.main, block)
            }
        }
        monitoredProperties.removeAll()
        muteVolumeListenerBlock = nil
        if let block = listenerBlock {
            for selector in systemSelectors {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                        mElement: kAudioObjectPropertyElementMain)
                _ = hardware.removeListener(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
            }
        }
        systemSelectors.removeAll()
        listenerBlock = nil
    }

    private enum ReadError: Error { case unavailable }

    private func createDevice(id: AudioObjectID, type: AudioDeviceType) throws -> AudioDevice? {
        let scope: AudioObjectPropertyScope = type == .input
            ? kAudioDevicePropertyScopeInput
            : kAudioDevicePropertyScopeOutput

        guard try hasStreams(deviceId: id, scope: scope) else { return nil }
        guard try canBeDefault(deviceId: id, scope: scope) else { return nil }

        guard let name = getDeviceName(id: id) else { throw ReadError.unavailable }
        guard let uid = getDeviceUID(id: id) else { throw ReadError.unavailable }

        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let hasTransport = hardware.hasProperty(id, &address)
        if hasTransport && hardware.getPropertyData(id, &address, 0, nil, &size, &transport) != noErr {
            throw ReadError.unavailable
        }
        // Probe capability without depending on the user-editable Bluetooth name.
        // This path is also used by background routing validation; it must stay read-only.
        var listeningModeCapable = false
        if type == .output, transport == kAudioDeviceTransportTypeBluetooth {
            var mode = AudioObjectPropertyAddress(mSelector: 0x6C73746D, mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain) // lstm
            var modes = AudioObjectPropertyAddress(mSelector: 0x6C736D73, mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain) // lsms
            listeningModeCapable = hardware.hasProperty(id, &mode) && hardware.hasProperty(id, &modes)
        }
        return AudioDevice(id: id, uid: uid, name: name, type: type,
                           transportType: hasTransport ? transport : nil,
                           listeningModeCapable: listeningModeCapable)
    }

    /// False for a device the system does not allow as the default one on that side, such
    /// as the capture device a conferencing app installs for itself. The system's Sound
    /// settings do not offer such a device either, and picking it would do nothing.
    /// True when the property is absent; a failed read is uncertain.
    private func canBeDefault(deviceId: AudioObjectID, scope: AudioObjectPropertyScope) throws -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        guard hardware.hasProperty(deviceId, &propertyAddress) else { return true }
        var allowed: UInt32 = 1
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = hardware.getPropertyData(deviceId, &propertyAddress, 0, nil, &dataSize, &allowed)

        guard status == noErr else { throw ReadError.unavailable }
        return allowed != 0
    }

    private func hasStreams(deviceId: AudioObjectID, scope: AudioObjectPropertyScope) throws -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        // Some output-only drivers do not expose the input-scope property at all.
        guard hardware.hasProperty(deviceId, &propertyAddress) else { return false }
        var dataSize: UInt32 = 0
        let status = hardware.getPropertyDataSize(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { throw ReadError.unavailable }
        return dataSize > 0
    }

    private func getDeviceName(id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // The property hands back a string the caller owns
        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = hardware.getPropertyData(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private func getDeviceUID(id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = hardware.getPropertyData(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &uid
        )

        guard status == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    deinit {
        stopListening()
    }
}
