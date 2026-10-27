import Foundation
import CoreAudio
import AudioToolbox

private struct Property: Hashable {
    let id: AudioObjectID
    let selector: UInt32
    let scope: UInt32
    let element: UInt32
    init(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) {
        self.id = id; selector = address.mSelector; scope = address.mScope; element = address.mElement
    }
}

/// Every HAL call is replaced. These checks cannot affect the real audio route.
private final class Hardware {
    var inventoryFails = false
    var ids: [AudioObjectID] = [101]
    var uid = "fake-usb"
    var uidReadable = true
    var name = "Test USB"
    var transport = kAudioDeviceTransportTypeUSB
    var listeningModes = false
    var masterMute: UInt32? = 0
    var channelMute: UInt32? = 0
    var muteWriteRejected = false
    var muteWriteIgnored = false
    var currentOutput: AudioObjectID = 101
    var muteWrites: [UInt32] = []
    var rejectedSelectors: Set<UInt32> = []
    var attempts: [Property: Int] = [:]
    var listeners: [Property: AudioObjectPropertyListenerBlock] = [:]
    var missingRemovals = 0

    func adapter() -> AudioDeviceHardware {
        var hardware = AudioDeviceHardware()
        hardware.hasProperty = { [self] id, address in
            let a = address.pointee
            if a.mSelector == 0x6C73746D || a.mSelector == 0x6C736D73 { return listeningModes }
            if a.mSelector == kAudioDevicePropertyMute {
                guard a.mScope == kAudioDevicePropertyScopeOutput else { return false }
                return a.mElement == 0 ? masterMute != nil : a.mElement == 1 && channelMute != nil
            }
            return true
        }
        hardware.getPropertyDataSize = { [self] _, address, _, _, size in
            if address.pointee.mSelector == kAudioHardwarePropertyDevices {
                guard !inventoryFails else { return kAudioHardwareUnspecifiedError }
                size.pointee = UInt32(ids.count * MemoryLayout<AudioObjectID>.size)
                return noErr
            }
            if address.pointee.mSelector == kAudioDevicePropertyStreams {
                size.pointee = address.pointee.mScope == kAudioDevicePropertyScopeOutput ? 4 : 0
                return noErr
            }
            return kAudioHardwareUnknownPropertyError
        }
        hardware.getPropertyData = { [self] _, address, _, _, _, data in
            switch address.pointee.mSelector {
            case kAudioHardwarePropertyDevices:
                guard !inventoryFails else { return kAudioHardwareUnspecifiedError }
                for (index, id) in ids.enumerated() { data.assumingMemoryBound(to: UInt32.self)[index] = id }
            case kAudioHardwarePropertyDefaultOutputDevice:
                data.assumingMemoryBound(to: UInt32.self).pointee = currentOutput
            case kAudioDevicePropertyDeviceNameCFString:
                data.assumingMemoryBound(to: Unmanaged<CFString>?.self).pointee = Unmanaged.passRetained(name as CFString)
            case kAudioDevicePropertyDeviceUID:
                guard uidReadable else { return kAudioHardwareUnspecifiedError }
                data.assumingMemoryBound(to: Unmanaged<CFString>?.self).pointee = Unmanaged.passRetained(uid as CFString)
            case kAudioDevicePropertyTransportType:
                data.assumingMemoryBound(to: UInt32.self).pointee = transport
            case kAudioDevicePropertyDeviceCanBeDefaultDevice:
                data.assumingMemoryBound(to: UInt32.self).pointee = 1
            case kAudioDevicePropertyMute:
                guard let value = address.pointee.mElement == 0 ? masterMute : channelMute else { return kAudioHardwareUnknownPropertyError }
                data.assumingMemoryBound(to: UInt32.self).pointee = value
            case kAudioHardwareServiceDeviceProperty_VirtualMainVolume:
                data.assumingMemoryBound(to: Float.self).pointee = 0.5
            default: return kAudioHardwareUnknownPropertyError
            }
            return noErr
        }
        hardware.isPropertySettable = { _, _, result in result.pointee = true; return noErr }
        hardware.setPropertyData = { [self] _, address, _, _, _, data in
            precondition(address.pointee.mSelector == kAudioDevicePropertyMute, "Only fake mute writes are allowed")
            if muteWriteRejected { return kAudioHardwareUnspecifiedError }
            muteWrites.append(address.pointee.mElement)
            if !muteWriteIgnored {
                if address.pointee.mElement == 0 { masterMute = data.assumingMemoryBound(to: UInt32.self).pointee }
                else { channelMute = data.assumingMemoryBound(to: UInt32.self).pointee }
            }
            return noErr
        }
        hardware.addListener = { [self] id, address, _, block in
            let property = Property(id, address.pointee)
            attempts[property, default: 0] += 1
            guard !rejectedSelectors.contains(property.selector) else { return kAudioHardwareUnspecifiedError }
            precondition(listeners[property] == nil, "Successful registrations must never be duplicated")
            listeners[property] = block
            return noErr
        }
        hardware.removeListener = { [self] id, address, _, _ in
            let property = Property(id, address.pointee)
            guard listeners.removeValue(forKey: property) != nil else {
                missingRemovals += 1
                return kAudioHardwareBadObjectError
            }
            return noErr
        }
        return hardware
    }

    func emit(_ selector: UInt32, element: UInt32 = 0) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                                mElement: element)
        listeners[Property(101, address)]?(1, &address)
    }
    func attemptCount(_ selector: UInt32) -> Int {
        attempts.filter { $0.key.selector == selector }.reduce(0) { $0 + $1.value }
    }
}

private final class RecoveryClock {
    var queued: [DispatchWorkItem] = []
    var delays: [TimeInterval] = []
    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: action)
        queued.append(work); delays.append(delay)
        return work
    }
    func drain() {
        var count = 0
        while !queued.isEmpty {
            count += 1
            precondition(count <= 10, "Recovery must be bounded")
            let work = queued.removeFirst()
            if !work.isCancelled { work.perform() }
        }
    }
}

@main struct AudioDeviceServiceCheckMain {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else { print("FAIL: \(message)"); exit(1) }
            checks += 1; print("ok: \(message)")
        }
        do {
            let hardware = Hardware(), clock = RecoveryClock()
            let service = AudioDeviceService(hardware: hardware.adapter(), scheduleRecovery: clock.schedule)
            var events = 0
            var recoverySnapshots: [Bool] = []
            service.onMuteOrVolumeChanged = { events += 1 }
            service.onDevicesChanged = { [weak service] in
                recoverySnapshots.append(service?.isDeviceMuted(101, type: .output) ?? false)
            }
            service.startListening()
            service.startListening()
            check(hardware.listeners.count == 6, "repeated start preserves one registration per property")
            hardware.inventoryFails = true
            service.updateMuteVolumeListeners()
            hardware.emit(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            check(hardware.listeners.count == 6 && events == 1, "failed inventory retains working volume observation")
            hardware.channelMute = 1 // The event was missed; recovery must explicitly read current state.
            hardware.inventoryFails = false
            clock.drain()
            hardware.emit(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            check(events == 2 && clock.delays == [0.3], "independent listener recovery succeeds without a new HAL event")
            service.updateMuteVolumeListeners()
            check(recoverySnapshots == [true], "successful recovery refreshes missed state once without a replayed HAL event")
            hardware.channelMute = 1
            hardware.emit(kAudioDevicePropertyMute, element: 1)
            check(events == 3 && service.isDeviceMuted(101, type: .output), "channel mute notification and read use the same control")
            hardware.ids = [202]
            service.updateMuteVolumeListeners()
            check(!hardware.listeners.keys.contains { $0.id == 101 }
                  && hardware.listeners.keys.filter { $0.id == 202 }.count == 3,
                  "device replacement removes old observation and installs the new endpoint")
            service.stopListening()
            check(hardware.listeners.isEmpty, "teardown removes every successful registration")
        }
        do {
            let hardware = Hardware(), clock = RecoveryClock()
            hardware.rejectedSelectors = [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume]
            let service = AudioDeviceService(hardware: hardware.adapter(), scheduleRecovery: clock.schedule)
            service.startListening()
            check(hardware.listeners.count == 4, "partial registration retains successful listeners")
            hardware.rejectedSelectors = []
            clock.drain()
            check(hardware.listeners.count == 6
                  && hardware.attemptCount(kAudioHardwarePropertyDefaultOutputDevice) == 2
                  && hardware.attemptCount(kAudioHardwareServiceDeviceProperty_VirtualMainVolume) == 2
                  && hardware.attemptCount(kAudioDevicePropertyMute) == 2,
                  "recovery retries only failed global and device registrations")
        }
        do {
            let hardware = Hardware(), clock = RecoveryClock()
            let service = AudioDeviceService(hardware: hardware.adapter(), scheduleRecovery: clock.schedule)
            var events = 0
            service.onMuteOrVolumeChanged = { events += 1 }
            service.startListening()
            hardware.uidReadable = false
            service.updateMuteVolumeListeners()
            hardware.emit(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            check(events == 1 && hardware.listeners.count == 6 && hardware.attemptCount(kAudioDevicePropertyMute) == 2,
                  "failed UID read preserves existing observation without treating it as a replacement")
            clock.drain()
            check(clock.delays == [0.3, 1, 3] && hardware.listeners.count == 6,
                  "unreadable endpoint identity has only three recovery attempts")
            hardware.uidReadable = true
            service.updateMuteVolumeListeners()
            hardware.uid = "replacement-using-same-id"
            // HAL discarded the old object's registrations when reusing its numeric ID.
            hardware.listeners = hardware.listeners.filter { $0.key.id != 101 }
            service.updateMuteVolumeListeners()
            hardware.emit(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            check(events == 2 && hardware.listeners.count == 6 && hardware.missingRemovals == 3
                  && hardware.attemptCount(kAudioHardwareServiceDeviceProperty_VirtualMainVolume) == 2,
                  "same HAL ID with a new UID replaces dead registrations before adding new listeners")
            service.stopListening()
            check(hardware.listeners.isEmpty && hardware.missingRemovals == 3,
                  "replacement cleanup keeps new registrations intact until normal teardown")
        }
        do {
            let hardware = Hardware(), clock = RecoveryClock()
            hardware.rejectedSelectors = [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume]
            let service = AudioDeviceService(hardware: hardware.adapter(), scheduleRecovery: clock.schedule)
            var refreshedDefaults: [AudioObjectID?] = []
            service.onDevicesChanged = { [weak service] in
                refreshedDefaults.append(service?.getCurrentDefaultDevice(type: .output))
            }
            service.startListening()
            hardware.currentOutput = 202 // No HAL notification was delivered during the registration failure.
            hardware.rejectedSelectors = [kAudioHardwareServiceDeviceProperty_VirtualMainVolume]
            clock.drain()
            check(refreshedDefaults == [202] && hardware.attemptCount(kAudioHardwarePropertyDefaultOutputDevice) == 2,
                  "partial recovery refreshes a missed default route despite another listener staying unavailable")
            check(hardware.attemptCount(kAudioHardwareServiceDeviceProperty_VirtualMainVolume) == 4
                  && clock.delays == [0.3, 1, 3],
                  "remaining failed retries are bounded and do not repeat partial-recovery refreshes")
        }
        do {
            let hardware = Hardware(), clock = RecoveryClock()
            hardware.rejectedSelectors = [kAudioHardwareServiceDeviceProperty_VirtualMainVolume]
            let service = AudioDeviceService(hardware: hardware.adapter(), scheduleRecovery: clock.schedule)
            service.startListening(); clock.drain()
            check(hardware.attemptCount(kAudioHardwareServiceDeviceProperty_VirtualMainVolume) == 4
                  && clock.delays == [0.3, 1, 3], "persistent listener failure has only three recovery attempts")
            service.stopListening(); service.startListening(); service.stopListening(); clock.drain()
            check(hardware.listeners.isEmpty, "stopping cancels queued recovery and cannot recreate observation")
        }
        do {
            let hardware = Hardware()
            let service = AudioDeviceService(hardware: hardware.adapter())
            let device = AudioDevice(id: 101, uid: hardware.uid, name: hardware.name, type: .output)
            hardware.channelMute = 1
            check(service.unmuteOutput(for: device) && hardware.muteWrites == [1]
                  && !service.isDeviceMuted(101, type: .output), "unmute clears channel mute even when master exists and is already clear")
            hardware.masterMute = 1; hardware.channelMute = 1; hardware.muteWrites = []
            check(service.unmuteOutput(for: device) && Set(hardware.muteWrites) == [0, 1]
                  && !service.isDeviceMuted(101, type: .output), "unmute verifies both master and channel controls")
            hardware.channelMute = 1; hardware.muteWriteIgnored = true
            check(!service.unmuteOutput(for: device), "accepted mute write with unchanged read-back is a failure")
            hardware.muteWriteIgnored = false; hardware.muteWriteRejected = true
            check(!service.unmuteOutput(for: device), "rejected mute write remains a failure")
            hardware.muteWriteRejected = false; hardware.masterMute = nil; hardware.channelMute = 1
            check(service.unmuteOutput(for: device) && hardware.channelMute == 0,
                  "channel-only mute still works when no master property exists")
            hardware.channelMute = 1; hardware.currentOutput = 202
            let beforeRouteChange = hardware.muteWrites.count
            check(!service.unmuteOutput(for: device) && hardware.muteWrites.count == beforeRouteChange,
                  "route change rejects unmute without writing to the old or new endpoint")
            hardware.currentOutput = 101
            hardware.masterMute = nil; hardware.channelMute = nil
            check(service.unmuteOutput(for: device), "volume-only device has no mute control to clear")
        }
        do {
            let hardware = Hardware()
            hardware.name = "我的耳机"; hardware.transport = kAudioDeviceTransportTypeBluetooth
            hardware.listeningModes = true
            let service = AudioDeviceService(hardware: hardware.adapter())
            func output() -> AudioDevice? {
                guard case .available(let devices) = service.readInventory() else { return nil }
                return devices.first { $0.type == .output }
            }
            check(output()?.isListeningModeCandidate == true, "renamed Bluetooth device is detected by actual listening-mode properties")
            hardware.listeningModes = false
            check(output()?.isListeningModeCandidate == true, "temporarily missing properties retain previously confirmed capability")
            hardware.uid = "ordinary-speaker"; hardware.name = "蓝牙音箱"
            check(output()?.isListeningModeCandidate == false, "ordinary Bluetooth device does not enter mode recovery")
        }
        print("All \(checks) AudioDeviceService checks passed. No real HAL access or audio writes.")
    }
}
