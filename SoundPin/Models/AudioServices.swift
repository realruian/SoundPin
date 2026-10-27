import Foundation
import CoreAudio
import os

/// Device events and routing decisions, for tracing a switch after the fact:
/// log show --last 10m --predicate 'subsystem == "io.github.realruian.SoundPin"'
enum AudioLog {
    static let routing = Logger(subsystem: "io.github.realruian.SoundPin", category: "routing")
}

/// Failure is not an empty inventory. A partial read must never drive routing.
enum DeviceInventory {
    case available([AudioDevice])
    case unavailable
}

/// All fields describe the same output. A missing scalar is not zero volume.
struct OutputVolumeState {
    let deviceID: AudioObjectID
    let volume: Float?
    let isSettable: Bool
}

protocol AudioDeviceProviding: AnyObject {
    var onDevicesChanged: (() -> Void)? { get set }
    var onMuteOrVolumeChanged: (() -> Void)? { get set }
    func readInventory() -> DeviceInventory
    func getCurrentDefaultDevice(type: AudioDeviceType) -> AudioObjectID?
    /// Revalidate the UID immediately before writing the transient HAL id.
    func setDefaultDevice(_ device: AudioDevice) -> Bool
    func readOutputVolume() -> OutputVolumeState?
    func setOutputVolume(_ volume: Float, for device: AudioDevice) -> Bool
    func unmuteOutput(for device: AudioDevice) -> Bool
    func isDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool
    func startListening()
}

protocol ListeningModeProviding: AnyObject {
    var needsObservationRecovery: Bool { get }
    var onChange: (() -> Void)? { get set }
    func state(for device: AudioDevice) -> ListeningModeState?
    func request(_ mode: ListeningMode, for device: AudioDevice) -> Bool
    func observe(_ devices: [AudioDevice])
}

protocol PreferenceStore: AnyObject {
    func object(forKey key: String) -> Any?
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func array(forKey key: String) -> [Any]?
    func dictionary(forKey key: String) -> [String: Any]?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: PreferenceStore {}

@MainActor final class ScheduledAudioAction {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}

@MainActor protocol AudioScheduling {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> ScheduledAudioAction
}

@MainActor final class MainQueueAudioScheduler: AudioScheduling {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> ScheduledAudioAction {
        let token = ScheduledAudioAction()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !token.isCancelled else { return }
            action()
        }
        return token
    }
}

/// Runs a default-device write and its read-back, then reports on the main actor.
/// A write to a Bluetooth device in transition can block for most of a second.
@MainActor protocol AudioWriting {
    func write(_ work: @escaping () -> AudioObjectID?, then done: @escaping @MainActor (AudioObjectID?) -> Void)
}

/// Shared by the main actor and the serial writer. Cancelling a queued write prevents
/// it from starting; an executing HAL call cannot be interrupted and remains tracked
/// until its read-back finishes so newer intent can be applied after it.
final class AudioWriteToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var started = false
    private var executing = false
    private var finished = false

    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, !executing, !finished else { return false }
        started = true
        executing = true
        return true
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func finish() {
        lock.lock()
        finished = true
        executing = false
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    var hasStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    var canAffectRoute: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !finished && (executing || !cancelled)
    }
}

/// One serial queue, so that writes land in the order they were asked for.
@MainActor final class BackgroundAudioWriter: AudioWriting {
    private let queue = DispatchQueue(label: "io.github.realruian.SoundPin.route-writes", qos: .userInitiated)
    func write(_ work: @escaping () -> AudioObjectID?, then done: @escaping @MainActor (AudioObjectID?) -> Void) {
        queue.async {
            let result = work()
            DispatchQueue.main.async { MainActor.assumeIsolated { done(result) } }
        }
    }
}

/// Pure selection policy. Inputs are already sorted and filtered for eligibility.
enum RoutingPolicy {
    static func candidate(in devices: [AudioDevice], failedRowIDs: Set<String>,
                          currentID: AudioObjectID?, connected: [AudioDevice],
                          type: AudioDeviceType) -> AudioDevice? {
        guard let first = devices.first else { return nil }
        if !failedRowIDs.contains(first.rowID) { return first }
        // A failed preferred device must not disturb a still-available route.
        if connected.contains(where: { $0.type == type && $0.id == currentID }) { return nil }
        return devices.first { !failedRowIDs.contains($0.rowID) }
    }
}
