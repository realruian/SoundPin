import Foundation
import CoreAudio

@main struct ListeningModeRequestCheckMain {
    @MainActor static func main() async {
        L10n.persistsSetting = false
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            count += 1
            print("ok: \(name)")
        }
        let pods = AudioDevice(id: 101, uid: "pods", name: "AirPods Pro", type: .output,
                               transportType: kAudioDeviceTransportTypeBluetooth)
        let speaker = AudioDevice(id: 102, uid: "speaker", name: "MacBook Speakers", type: .output)
        func state(_ mode: ListeningMode, mask: UInt32 = 7) -> ListeningModeState {
            ListeningModeState(currentRawValue: mode.rawValue, supportedMask: mask)
        }
        func fixture(initiallyUnreadable: Bool = false, observerFailure: Bool = false)
            -> (AudioManager, SimulatedAudioService, SimulatedListeningModes, MemoryPreferences, TestAudioScheduler) {
            let audio = SimulatedAudioService()
            audio.devices = [pods, speaker]
            audio.defaults[.output] = speaker.id
            let modes = SimulatedListeningModes()
            modes.states[pods.uid] = state(.noiseCancellation)
            modes.appliesImmediately = false
            modes.needsObservationRecovery = observerFailure
            if initiallyUnreadable { modes.unavailableUIDs = [pods.uid] }
            let prefs = MemoryPreferences()
            prefs.set(true, forKey: "customMode")
            let clock = TestAudioScheduler()
            let manager = AudioManager(deviceService: audio, listeningModeService: modes,
                                       priorityManager: PriorityManager(defaults: prefs), scheduler: clock,
                                       writer: InlineAudioWriter())
            return (manager, audio, modes, prefs, clock)
        }
        func drain() async { for _ in 0..<10 { await Task.yield() } }
        do {
            let (m, audio, modes, prefs, clock) = fixture()
            let preferences = prefs.values as NSDictionary
            check(m.setListeningMode(.transparency, for: pods), "accepted write starts request")
            check(m.listeningModeRequests[pods.uid] == .pending(.transparency), "pending target is distinct from reported state")
            check(m.listeningModes[pods.uid]?.current == .noiseCancellation, "pending request does not invent a checkmark")
            check(!m.setListeningMode(.adaptive, for: pods) && modes.requests.count == 1, "repeated clicks do not write or replace pending intent")
            modes.states[pods.uid] = state(.transparency)
            clock.advance(by: 0.21)
            check(m.listeningModeRequests[pods.uid] == nil && m.listeningModes[pods.uid]?.current == .transparency,
                  "scheduled read-back recovers even without a property notification")
            let reads = modes.reads
            clock.advance(by: 100)
            check(modes.reads == reads, "reported target cancels all remaining request polls")
            check(audio.writes.isEmpty && audio.volumeWrites.isEmpty && audio.unmuteWrites.isEmpty
                  && audio.defaults[.output] == speaker.id, "mode request never changes route volume or mute")
            check(preferences.isEqual(to: prefs.values), "mode request does not change saved priorities or settings")
        }
        do {
            let (m, _, modes, _, clock) = fixture()
            m.setListeningMode(.adaptive, for: pods)
            clock.advance(by: 3.69)
            check(m.listeningModeRequests[pods.uid] == .pending(.adaptive), "request remains pending through final read-back window")
            clock.advance(by: 0.02)
            check(m.listeningModeRequests[pods.uid] == .failed(.adaptive, .timedOut), "unmatched system state produces a bounded timeout")
            check(modes.requests.count == 1 && m.listeningModes[pods.uid]?.current == .noiseCancellation,
                  "timeout neither rewrites mode nor changes reported checkmark")
            let reads = modes.reads
            clock.advance(by: 100)
            check(modes.reads == reads, "timeout does not leave perpetual polling")
            modes.appliesImmediately = true
            m.retryListeningMode(for: pods)
            check(modes.requests.count == 2 && m.listeningModes[pods.uid]?.current == .adaptive
                  && m.listeningModeRequests[pods.uid] == nil, "explicit retry writes once and uses new read-back")
            clock.advance(by: 100)
            check(m.listeningModeRequests[pods.uid] == nil, "old timeout cannot fail a completed retry")
        }
        do {
            let (m, _, modes, _, clock) = fixture()
            modes.acceptsRequests = false
            check(!m.setListeningMode(.transparency, for: pods)
                  && m.listeningModeRequests[pods.uid] == .failed(.transparency, .rejected), "rejected write exposes failure immediately")
            let reads = modes.reads
            clock.advance(by: 100)
            check(modes.requests.count == 1 && modes.reads == reads, "rejected write never starts retry writes or polls")
            modes.acceptsRequests = true
            m.retryListeningMode(for: pods)
            modes.states[pods.uid] = state(.transparency)
            modes.onChange?()
            await drain()
            check(m.listeningModeRequests[pods.uid] == nil, "listener notification completes an explicit retry")
        }
        do {
            let (m, audio, modes, _, clock) = fixture()
            m.setListeningMode(.transparency, for: pods)
            audio.devices = [speaker]
            audio.onDevicesChanged?()
            await drain()
            check(m.listeningModes[pods.uid] == nil && m.listeningModeRequests[pods.uid] == nil,
                  "disconnect clears state and cancels pending request")
            let reads = modes.reads
            clock.advance(by: 100)
            check(modes.reads == reads && modes.requests.count == 1, "disconnect cannot trigger delayed mode writes or reads")
            let reconnected = AudioDevice(id: 201, uid: pods.uid, name: pods.name, type: .output,
                                      transportType: kAudioDeviceTransportTypeBluetooth)
            audio.devices = [reconnected, speaker]
            modes.states[pods.uid] = state(.noiseCancellation)
            audio.onDevicesChanged?()
            await drain()
            check(m.listeningModeRequests[pods.uid] == nil && modes.requests.count == 1,
                  "reconnection never replays the old request")
            check(!m.setListeningMode(.adaptive, for: pods), "stale row cannot write a reconnected HAL id")
            m.setListeningMode(.adaptive, for: reconnected)
            check(modes.requests.last?.0.id == 201, "new request resolves to current connected identity")
        }
        do {
            let (m, audio, modes, _, clock) = fixture()
            m.setListeningMode(.adaptive, for: pods)
            audio.devices = [AudioDevice(id: pods.id, uid: "replacement", name: "AirPods Max", type: .output,
                                         transportType: kAudioDeviceTransportTypeBluetooth), speaker]
            audio.onDevicesChanged?()
            await drain()
            modes.states[pods.uid] = state(.adaptive)
            modes.onChange?()
            await drain()
            clock.advance(by: 100)
            check(m.listeningModeRequests[pods.uid] == nil && m.listeningModes[pods.uid] == nil,
                  "recycled HAL id and late callback cannot restore removed endpoint")
        }
        do {
            let (m, _, modes, _, clock) = fixture()
            modes.unavailableUIDs = [pods.uid]
            m.refreshListeningModes()
            check(m.listeningModes[pods.uid]?.supported.count == 3 && m.listeningModes[pods.uid]?.current == nil
                  && m.unavailableListeningModeUIDs.contains(pods.uid), "transient read failure retains controls but clears stale checkmark")
            check(!m.setListeningMode(.adaptive, for: pods) && modes.requests.isEmpty,
                  "cached supported modes never authorize a write")
            modes.unavailableUIDs = []
            clock.advance(by: 0.31)
            check(m.unavailableListeningModeUIDs.isEmpty && m.listeningModes[pods.uid]?.current == .noiseCancellation,
                  "bounded read recovery restores current state")
        }
        do {
            let (m, _, modes, _, clock) = fixture(initiallyUnreadable: true)
            check(m.listeningModes.isEmpty, "initial read failure does not invent supported modes")
            modes.unavailableUIDs = []
            clock.advance(by: 0.31)
            check(m.listeningModes[pods.uid]?.current == .noiseCancellation,
                  "initial capability failure recovers without topology change")
        }
        do {
            let (m, _, modes, _, clock) = fixture(initiallyUnreadable: true, observerFailure: true)
            for _ in 0..<10 { m.refreshListeningModes() }
            let calls = modes.observationCalls
            clock.advance(by: 100)
            check(modes.observationCalls == calls + 3, "notification bursts do not replenish recovery budget")
            let reads = modes.reads
            clock.advance(by: 100)
            check(modes.reads == reads, "read and listener recovery stop after three scheduled attempts")
            modes.unavailableUIDs = []
            modes.needsObservationRecovery = false
            m.retryListeningModeRead()
            check(m.listeningModes[pods.uid] != nil && m.unavailableListeningModeUIDs.isEmpty,
                  "explicit refresh recovers after exhausted read budget")
        }
        do {
            let (m, _, modes, _, clock) = fixture(observerFailure: true)
            let calls = modes.observationCalls
            modes.needsObservationRecovery = false
            clock.advance(by: 0.31)
            check(modes.observationCalls == calls + 1, "missing listener is retried even when state reads succeed")
            clock.advance(by: 100)
            check(modes.observationCalls == calls + 1, "successful listener recovery cancels remaining recovery work")
            m.setListeningMode(.adaptive, for: pods)
            modes.states[pods.uid] = state(.noiseCancellation, mask: 3)
            m.refreshListeningModes()
            check(m.listeningModeRequests[pods.uid] == .failed(.adaptive, .unavailable),
                  "capability removal ends incompatible pending request")
        }
        do {
            let (m, _, modes, _, clock) = fixture()
            check(m.setListeningMode(.noiseCancellation, for: pods) && modes.requests.isEmpty,
                  "already reported mode does not produce a redundant write")
            m.setListeningMode(.adaptive, for: pods)
            modes.unavailableUIDs = [pods.uid]
            clock.advance(by: 100)
            check(m.listeningModeRequests[pods.uid] == .failed(.adaptive, .timedOut),
                  "unreadable state cannot keep request pending indefinitely")
            modes.unavailableUIDs = []
            modes.states[pods.uid] = state(.adaptive)
            modes.onChange?()
            await drain()
            check(m.listeningModeRequests[pods.uid] == nil && m.listeningModes[pods.uid]?.current == .adaptive,
                  "late system update clears stale timeout without another write")
        }
        do {
            let (m, audio, modes, _, _) = fixture()
            audio.inventoryAvailable = false
            audio.onDevicesChanged?()
            await drain()
            modes.appliesImmediately = true
            check(m.isDeviceReadUnavailable && m.setListeningMode(.transparency, for: pods),
                  "independent identity-validated mode control survives unavailable full inventory")
            m.retryListeningModeRead()
            check(audio.writes.isEmpty && audio.defaults[.output] == speaker.id,
                  "mode read retry never invokes routing recovery")
        }
        print("\(count) listening-mode request checks passed. In-memory services only.")
    }
}
