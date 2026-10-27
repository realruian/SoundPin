import Foundation
import CoreAudio

/// Never persists to the app's defaults domain or any file.
final class MemoryPreferences: PreferenceStore {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func string(forKey key: String) -> String? { values[key] as? String }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func array(forKey key: String) -> [Any]? { values[key] as? [Any] }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}

/// An in-memory driver. Preview binaries do not link AudioDeviceService at all.
final class SimulatedAudioService: AudioDeviceProviding {
    var onDevicesChanged: (() -> Void)?
    var onMuteOrVolumeChanged: (() -> Void)?
    var devices: [AudioDevice] = []
    var inventoryAvailable = true
    var inventoryReads = 0
    var defaults: [AudioDeviceType: AudioObjectID] = [:]
    var unreadableDefaults: Set<AudioDeviceType> = []
    var rejectedRows: Set<String> = []
    var appliesImmediately = true
    var writes: [AudioDevice] = []
    var mutedRows: Set<String> = []
    var volume: Float = 0.6
    var volumeReadable = true
    var volumeSettable = true
    var rejectsVolume = false
    var appliesVolume = true
    var rejectsUnmute = false
    var volumeWrites: [(String, Float)] = []
    var unmuteWrites: [String] = []
    var beforeVolumeWrite: (() -> Void)?
    var beforeUnmute: (() -> Void)?
    var listening = false
    var beforeWrite: ((AudioDevice) -> Void)?
    func readInventory() -> DeviceInventory {
        inventoryReads += 1
        return inventoryAvailable ? .available(devices) : .unavailable
    }
    func getCurrentDefaultDevice(type: AudioDeviceType) -> AudioObjectID? {
        unreadableDefaults.contains(type) ? nil : (defaults[type] ?? 0)
    }
    func setDefaultDevice(_ device: AudioDevice) -> Bool {
        beforeWrite?(device)
        guard devices.contains(where: { $0.id == device.id && $0.rowID == device.rowID }) else { return false }
        writes.append(device)
        guard !rejectedRows.contains(device.rowID) else { return false }
        if appliesImmediately { defaults[device.type] = device.id }
        return true
    }
    func readOutputVolume() -> OutputVolumeState? {
        guard let id = getCurrentDefaultDevice(type: .output), id != 0 else { return nil }
        return OutputVolumeState(deviceID: id, volume: volumeReadable ? volume : nil, isSettable: volumeSettable)
    }
    private func isCurrentOutput(_ device: AudioDevice) -> Bool {
        device.type == .output && device.isConnected && getCurrentDefaultDevice(type: .output) == device.id
            && devices.contains { $0.id == device.id && $0.rowID == device.rowID }
    }
    func setOutputVolume(_ volume: Float, for device: AudioDevice) -> Bool {
        beforeVolumeWrite?()
        guard volume.isFinite, (0...1).contains(volume), volumeSettable, isCurrentOutput(device) else { return false }
        volumeWrites.append((device.rowID, volume))
        guard !rejectsVolume else { return false }
        if appliesVolume { self.volume = volume }
        return true
    }
    func unmuteOutput(for device: AudioDevice) -> Bool {
        beforeUnmute?()
        guard isCurrentOutput(device) else { return false }
        unmuteWrites.append(device.rowID)
        guard !rejectsUnmute else { return false }
        mutedRows.remove(device.rowID)
        return true
    }
    func isDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        devices.contains { $0.id == deviceId && $0.type == type && mutedRows.contains($0.rowID) }
    }
    func startListening() { listening = true }
}

final class SimulatedListeningModes: ListeningModeProviding {
    var onChange: (() -> Void)?
    var states: [String: ListeningModeState] = [:]
    var unavailableUIDs: Set<String> = []
    var needsObservationRecovery = false
    var observationCalls = 0
    var reads = 0
    var acceptsRequests = true
    var appliesImmediately = true
    var requests: [(AudioDevice, ListeningMode)] = []
    func state(for device: AudioDevice) -> ListeningModeState? {
        reads += 1
        return unavailableUIDs.contains(device.uid) ? nil : states[device.uid]
    }
    func request(_ mode: ListeningMode, for device: AudioDevice) -> Bool {
        guard let state = state(for: device), state.supported.contains(mode) else { return false }
        requests.append((device, mode))
        guard acceptsRequests else { return false }
        guard appliesImmediately else { return true }
        let mask = state.supported.reduce(UInt32(0)) { $0 | $1.supportBit }
        states[device.uid] = ListeningModeState(currentRawValue: mode.rawValue, supportedMask: mask)
        onChange?()
        return true
    }
    func observe(_ devices: [AudioDevice]) { observationCalls += 1 }
}

@MainActor final class TestAudioScheduler: AudioScheduling {
    private var now: TimeInterval = 0
    private var jobs: [(TimeInterval, ScheduledAudioAction, @MainActor () -> Void)] = []
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> ScheduledAudioAction {
        let token = ScheduledAudioAction()
        jobs.append((now + delay, token, action))
        return token
    }
    func advance(by interval: TimeInterval) {
        let end = now + interval
        var executions = 0
        while let index = jobs.indices.filter({ jobs[$0].0 <= end }).min(by: { jobs[$0].0 < jobs[$1].0 }) {
            let job = jobs.remove(at: index)
            now = job.0
            if !job.1.isCancelled { job.2() }
            executions += 1
            precondition(executions < 1000, "Unbounded scheduled work")
        }
        now = end
    }
}

/// Writes on the spot, so that checks see a route settle within the call that asked for it.
@MainActor final class InlineAudioWriter: AudioWriting {
    func write(_ work: @escaping () -> AudioObjectID?, then done: @escaping @MainActor (AudioObjectID?) -> Void) {
        done(work())
    }
}

/// Holds writes until `flush`. A service's `beforeWrite` hook runs after the token
/// starts, allowing checks to issue new intent while the old HAL call is in progress.
@MainActor final class DeferredAudioWriter: AudioWriting {
    private var queued: [(() -> AudioObjectID?, @MainActor (AudioObjectID?) -> Void)] = []
    var pendingCount: Int { queued.count }
    func write(_ work: @escaping () -> AudioObjectID?, then done: @escaping @MainActor (AudioObjectID?) -> Void) {
        queued.append((work, done))
    }
    /// Writes in order, then reports each in order. Work enqueued by a started-write
    /// hook is left for the next flush, after the current HAL write returns.
    func flush() {
        let jobs = queued
        queued = []
        let results = jobs.map { $0.0() }
        for (job, result) in zip(jobs, results) { job.1(result) }
    }
}

/// A thread-safe fake HAL boundary for exercising the production background writer.
/// The first matching write blocks after entering HAL, while the main actor can
/// receive a pause or newer selection. It never uses real audio or preferences.
final class BlockingRouteService: AudioDeviceProviding, @unchecked Sendable {
    var onDevicesChanged: (() -> Void)?
    var onMuteOrVolumeChanged: (() -> Void)?
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private let devices: [AudioDevice]
    private let blockedUID: String
    private var current: AudioObjectID
    private var entered = false
    private var recordedWrites: [String] = []

    init(devices: [AudioDevice], current: AudioObjectID, blockedUID: String) {
        self.devices = devices
        self.current = current
        self.blockedUID = blockedUID
    }

    private func locked<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }

    var writeHasStarted: Bool { locked { entered } }
    var writes: [String] { locked { recordedWrites } }
    func releaseWrite() { release.signal() }

    func readInventory() -> DeviceInventory { .available(devices) }
    func getCurrentDefaultDevice(type: AudioDeviceType) -> AudioObjectID? {
        type == .output ? locked { current } : 0
    }
    func setDefaultDevice(_ device: AudioDevice) -> Bool {
        let shouldBlock = locked {
            guard device.uid == blockedUID, !entered else { return false }
            entered = true
            return true
        }
        if shouldBlock, release.wait(timeout: .now() + 5) != .success { return false }
        return locked {
            guard device.type == .output, devices.contains(where: { $0.rowID == device.rowID && $0.id == device.id }) else {
                return false
            }
            recordedWrites.append(device.uid)
            current = device.id
            return true
        }
    }
    func readOutputVolume() -> OutputVolumeState? {
        OutputVolumeState(deviceID: locked { current }, volume: 0.6, isSettable: true)
    }
    func setOutputVolume(_ volume: Float, for device: AudioDevice) -> Bool { false }
    func unmuteOutput(for device: AudioDevice) -> Bool { false }
    func isDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool { false }
    func startListening() {}
}
