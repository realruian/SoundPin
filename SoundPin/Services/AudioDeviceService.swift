import Foundation
import CoreAudio
import AudioToolbox

class AudioDeviceService: AudioDeviceProviding {
    var onDevicesChanged: (() -> Void)?
    var onMuteOrVolumeChanged: (() -> Void)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var muteVolumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var monitoredDeviceIds: Set<AudioObjectID> = []
    private var pendingDeviceChange: DispatchWorkItem?
    /// One plug or unplug arrives as several notifications in a row (device list, default
    /// input, default output). They are handled once, after they have stopped coming.
    private let deviceChangeDelay: TimeInterval = 0.1

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
            guard AudioObjectGetPropertyDataSize(system, &propertyAddress, 0, nil, &dataSize) == noErr else { continue }

            let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
            var deviceIds = [AudioObjectID](repeating: 0, count: deviceCount)
            guard deviceCount > 0 else { return [] }
            guard AudioObjectGetPropertyData(system, &propertyAddress, 0, nil, &dataSize, &deviceIds) == noErr else { continue }

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

        let status = AudioObjectGetPropertyData(
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

        let status = AudioObjectSetPropertyData(
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
        let status = AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, &volume)
        var settable: DarwinBoolean = false
        let capability = AudioObjectIsPropertySettable(deviceId, &address, &settable)
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
        guard AudioObjectIsPropertySettable(device.id, &address, &settable) == noErr,
              settable.boolValue, isCurrentOutput(device) else { return false }
        var value = volume
        return AudioObjectSetPropertyData(device.id, &address, 0, nil,
                                          UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    /// The target is fixed by the volume gesture, never resolved to a new output here.
    @discardableResult
    func unmuteOutput(for device: AudioDevice) -> Bool {
        guard isCurrentOutput(device) else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(device.id, &address) {
            address.mElement = 1
            // Some devices expose only volume and have no mute property.
            guard AudioObjectHasProperty(device.id, &address) else { return true }
        }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &muted) == noErr else { return false }
        guard muted != 0 else { return true }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device.id, &address, &settable) == noErr,
              settable.boolValue, isCurrentOutput(device) else { return false }
        muted = 0
        guard AudioObjectSetPropertyData(device.id, &address, 0, nil, size, &muted) == noErr else { return false }
        return AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &muted) == noErr && muted == 0
    }

    func isDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        let scope: AudioObjectPropertyScope = type == .input
            ? kAudioDevicePropertyScopeInput
            : kAudioDevicePropertyScopeOutput

        // Try kAudioDevicePropertyMute (per-channel, element 0 is master)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var muted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        var status = AudioObjectGetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &muted
        )

        if status == noErr && muted != 0 {
            return true
        }

        // Try element 1 (first channel) if master didn't work
        propertyAddress.mElement = 1
        status = AudioObjectGetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &muted
        )

        if status == noErr && muted != 0 {
            return true
        }

        // Check if volume is essentially zero (some devices report this as muted)
        if type == .output {
            let volume = getDeviceVolume(deviceId)
            if volume < 0.01 {
                return true
            }
        }

        return false
    }

    func getDeviceVolume(_ deviceId: AudioObjectID) -> Float {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var volume: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)

        let status = AudioObjectGetPropertyData(
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
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

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

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            listenerBlock!
        )

        // Also listen to default device changes
        var inputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputDefaultAddress,
            DispatchQueue.main,
            listenerBlock!
        )

        var outputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputDefaultAddress,
            DispatchQueue.main,
            listenerBlock!
        )

        // Initial setup of mute/volume listeners
        updateMuteVolumeListeners()
    }

    // Called on the main queue, like the listener blocks
    private func scheduleDeviceChange() {
        pendingDeviceChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingDeviceChange = nil
            self.onDevicesChanged?()
            // Re-register mute/volume listeners when devices change
            self.updateMuteVolumeListeners()
        }
        pendingDeviceChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + deviceChangeDelay, execute: work)
    }

    func updateMuteVolumeListeners() {
        // Remove old listeners
        removeMuteVolumeListeners()

        // Create listener block
        muteVolumeListenerBlock = { [weak self] _, _ in
            self?.onMuteOrVolumeChanged?()
        }

        guard let deviceIds = deviceIDs() else { return }

        // Register listeners for each device
        for deviceId in deviceIds {
            // Listen to mute on output scope
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(
                deviceId,
                &muteAddress,
                DispatchQueue.main,
                muteVolumeListenerBlock!
            )

            // Listen to mute on input scope
            muteAddress.mScope = kAudioDevicePropertyScopeInput
            AudioObjectAddPropertyListenerBlock(
                deviceId,
                &muteAddress,
                DispatchQueue.main,
                muteVolumeListenerBlock!
            )

            // Listen to volume changes
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(
                deviceId,
                &volumeAddress,
                DispatchQueue.main,
                muteVolumeListenerBlock!
            )

            monitoredDeviceIds.insert(deviceId)
        }
    }

    private func removeMuteVolumeListeners() {
        guard let block = muteVolumeListenerBlock else { return }

        for deviceId in monitoredDeviceIds {
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceId, &muteAddress, DispatchQueue.main, block)

            muteAddress.mScope = kAudioDevicePropertyScopeInput
            AudioObjectRemovePropertyListenerBlock(deviceId, &muteAddress, DispatchQueue.main, block)

            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceId, &volumeAddress, DispatchQueue.main, block)
        }

        monitoredDeviceIds.removeAll()
        muteVolumeListenerBlock = nil
    }

    func stopListening() {
        pendingDeviceChange?.cancel()
        pendingDeviceChange = nil

        // Remove mute/volume listeners first
        removeMuteVolumeListeners()

        guard let block = listenerBlock else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )

        // Also remove default device change listeners
        var inputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputDefaultAddress,
            DispatchQueue.main,
            block
        )

        var outputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputDefaultAddress,
            DispatchQueue.main,
            block
        )

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
        let hasTransport = AudioObjectHasProperty(id, &address)
        if hasTransport && AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) != noErr {
            throw ReadError.unavailable
        }
        return AudioDevice(id: id, uid: uid, name: name, type: type,
                           transportType: hasTransport ? transport : nil)
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

        guard AudioObjectHasProperty(deviceId, &propertyAddress) else { return true }
        var allowed: UInt32 = 1
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, nil, &dataSize, &allowed)

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
        guard AudioObjectHasProperty(deviceId, &propertyAddress) else { return false }
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
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

        let status = AudioObjectGetPropertyData(
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

        let status = AudioObjectGetPropertyData(
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
