import Foundation
import CoreAudio

@main struct RoutingCheckMain {
    @MainActor static func main() async {
        L10n.persistsSetting = false
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            count += 1
            print("ok: \(name)")
        }
        func device(_ id: UInt32, _ uid: String, _ type: AudioDeviceType = .output,
                    name: String? = nil) -> AudioDevice {
            AudioDevice(id: id, uid: uid, name: name ?? uid, type: type)
        }
        let a = device(101, "a"), b = device(102, "b"), c = device(103, "c")
        func fixture(_ devices: [AudioDevice] = [a, b, c], current: UInt32 = 103,
                     paused: Bool = true, inventoryReady: Bool = true) -> (AudioManager, SimulatedAudioService, MemoryPreferences, TestAudioScheduler) {
            let audio = SimulatedAudioService()
            audio.devices = devices
            audio.inventoryAvailable = inventoryReady
            audio.defaults[.output] = current
            let prefs = MemoryPreferences()
            prefs.set(paused, forKey: "customMode")
            prefs.set(["a", "b", "c"], forKey: "speakerPriorities")
            let clock = TestAudioScheduler()
            let manager = AudioManager(deviceService: audio, listeningModeService: SimulatedListeningModes(),
                                       priorityManager: PriorityManager(defaults: prefs), scheduler: clock)
            return (manager, audio, prefs, clock)
        }
        func notify(_ audio: SimulatedAudioService) async {
            audio.onDevicesChanged?()
            // Drain main-actor callbacks without advancing the virtual retry clock.
            for _ in 0..<10 { await Task.yield() }
        }

        do {
            let (m, audio, prefs, clock) = fixture()
            audio.rejectedRows = [a.rowID]
            m.setCustomMode(false)
            check(audio.writes.count == 1 && m.currentOutputId == c.id, "failed write keeps confirmed output")
            for _ in 0..<20 { await notify(audio) }
            check(audio.writes.count == 1, "notification burst cannot replenish attempts")
            clock.advance(by: 10)
            check(audio.writes.count == 3 && m.routingFailure != nil, "initial attempt plus two bounded retries")
            for _ in 0..<10 { await notify(audio) }
            clock.advance(by: 10)
            check(audio.writes.count == 3, "failed target stays suppressed across duplicate events")
            check(audio.defaults[.output] == c.id, "failed preference preserves available current route")
            check(prefs.array(forKey: "speakerPriorities") as? [String] == ["a", "b", "c"], "automatic failure preserves priorities")
            audio.rejectedRows = []
            m.retryRoutingFailure()
            check(m.currentOutputId == a.id && m.routingFailure == nil, "explicit retry can recover")
        }
        do {
            let (m, audio, _, clock) = fixture()
            audio.rejectedRows = [a.rowID]
            m.setCustomMode(false)
            m.setCustomMode(true)
            await notify(audio)
            clock.advance(by: 10)
            check(audio.writes.count == 1 && m.pendingRouteRows.isEmpty, "pause cancels queued routing work")
            audio.devices = [b, c]
            await notify(audio)
            check(audio.writes.count == 1, "paused topology changes never write a route")
        }
        do {
            let (m, audio, prefs, clock) = fixture(current: a.id, paused: false)
            audio.appliesImmediately = false
            m.selectOutputDevice(b, in: .speaker)
            check(m.pendingRouteRows == [b.rowID] && m.currentOutputId == a.id, "manual request waits for read-back")
            check((prefs.array(forKey: "speakerPriorities") as? [String])?.first == "a", "unconfirmed request is not promoted")
            await notify(audio)
            check(audio.writes.count == 1, "old priority does not fight pending manual intent")
            audio.defaults[.output] = b.id
            await notify(audio)
            check(m.currentOutputId == b.id && m.pendingRouteRows.isEmpty, "delayed read-back confirms selection")
            check((prefs.array(forKey: "speakerPriorities") as? [String])?.first == "b", "confirmed manual selection is promoted")
            clock.advance(by: 10)
            check(audio.writes.count == 1, "confirmation cancels stale retries")
        }
        do {
            let (m, audio, prefs, clock) = fixture(current: a.id, paused: false)
            audio.rejectedRows = [b.rowID]
            m.selectOutputDevice(b, in: .speaker)
            clock.advance(by: 10)
            check(m.currentOutputId == a.id && m.routingFailure?.device.rowID == b.rowID, "manual failure remains visible")
            check((prefs.array(forKey: "speakerPriorities") as? [String])?.first == "a", "failed manual selection never changes priority")
        }
        do {
            let (m, audio, _, clock) = fixture()
            audio.rejectedRows = [a.rowID]
            m.setInputDevice(device(200, "missing", .input))
            m.selectOutputDevice(a, in: .speaker)
            m.selectOutputDevice(b, in: .speaker)
            clock.advance(by: 10)
            check(audio.writes.map(\.uid) == ["a", "b"], "new manual intent cancels previous retries")
            check(audio.defaults[.output] == b.id, "manual selection still works while paused")
        }
        do {
            let (m, audio, _, clock) = fixture()
            audio.inventoryAvailable = false
            m.setCustomMode(false)
            check(m.isDeviceReadUnavailable && m.speakerDevices.count == 3, "unavailable inventory preserves display")
            for _ in 0..<20 { await notify(audio) }
            clock.advance(by: 10)
            check(audio.writes.isEmpty, "no routing writes from stale inventory")
            let reads = audio.inventoryReads
            clock.advance(by: 100)
            check(audio.inventoryReads == reads, "inventory recovery has no perpetual polling")
            audio.inventoryAvailable = true
            m.retryDeviceRead()
            check(!m.isDeviceReadUnavailable && m.currentOutputId == a.id, "explicit refresh recovers routing")
        }
        do {
            let (m, audio, _, clock) = fixture()
            audio.inventoryAvailable = false
            await notify(audio)
            audio.inventoryAvailable = true
            clock.advance(by: 0.31)
            check(!m.isDeviceReadUnavailable && audio.writes.isEmpty, "read retry recovers without routing while paused")
            audio.devices = []
            await notify(audio)
            check(m.speakerDevices.isEmpty && !m.isDeviceReadUnavailable, "confirmed empty inventory is different from failure")
        }
        do {
            let mic = device(104, "duplex", .input, name: "USB Headphones")
            let out = device(104, "duplex", .output, name: "USB Headphones")
            let (m, audio, _, _) = fixture([a, mic], current: a.id, paused: false)
            audio.devices = [a, mic, out]
            await notify(audio)
            check(m.currentMode == .headphone && m.currentOutputId == out.id, "output arriving after microphone is a new headphone endpoint")
            audio.devices = [a, out]
            await notify(audio)
            m.toggleEditMode()
            check(m.inputDevices.contains { $0.rowID == mic.rowID && !$0.isConnected }, "offline microphone remains listed while its output is connected")
            check(m.headphoneDevices.contains { $0.rowID == out.rowID && $0.isConnected }, "output endpoint remains connected independently")
        }
        do {
            let (m, audio, _, clock) = fixture([a, b], current: 0)
            audio.rejectedRows = [a.rowID]
            m.setCustomMode(false)
            clock.advance(by: 10)
            check(audio.writes.map(\.uid) == ["a", "a", "a", "b"], "automatic failure falls back only when current route is absent")
            check(m.currentOutputId == b.id, "fallback is confirmed from system read-back")
        }
        do {
            let (m, audio, _, clock) = fixture()
            audio.appliesImmediately = false
            m.selectOutputDevice(a, in: .speaker)
            audio.devices = [b, c]
            await notify(audio)
            clock.advance(by: 10)
            check(audio.writes.count == 1 && m.pendingRouteRows.isEmpty, "disconnection cancels target retries")
        }
        do {
            let (m, audio, _, clock) = fixture()
            audio.appliesImmediately = false
            m.selectOutputDevice(a, in: .speaker)
            let reconnected = device(111, "a")
            audio.devices = [reconnected, b, c]
            audio.appliesImmediately = true
            clock.advance(by: 0.31)
            check(audio.writes.map(\.id) == [101, 111], "retry resolves stable identity to fresh HAL id")
            check(m.currentOutputId == 111, "reconnected device uses confirmed new id")
        }
        do {
            let (m, audio, _, clock) = fixture()
            audio.unreadableDefaults = [.output]
            m.selectOutputDevice(a, in: .speaker)
            clock.advance(by: 10)
            check(audio.writes.isEmpty && m.routingFailure != nil, "unreadable default does not justify a route write")
        }
        do {
            let (m, audio, _, clock) = fixture()
            audio.beforeWrite = { _ in audio.devices = [device(101, "different-uid"), b, c] }
            m.selectOutputDevice(a, in: .speaker)
            clock.advance(by: 10)
            check(audio.writes.isEmpty, "reused HAL id cannot route to a different UID")
        }
        do {
            let (m, audio, _, clock) = fixture(current: a.id, paused: false)
            m.setNeverUse(b, neverUse: true)
            m.selectOutputDevice(b, in: .speaker)
            await notify(audio)
            clock.advance(by: 10)
            check(audio.defaults[.output] == b.id, "manual never-auto-select exception survives device events")
            m.hideDevice(b, category: .speaker)
            check(audio.defaults[.output] == a.id, "ignoring the hand-picked device restores eligible priority")
        }
        do {
            let (m, audio, _, clock) = fixture()
            audio.rejectedRows = [a.rowID]
            m.setCustomMode(false)
            let headphones = device(200, "headphones", name: "USB Headphones")
            audio.devices.append(headphones)
            await notify(audio)
            clock.advance(by: 10)
            check(audio.writes.map(\.uid) == ["a", "headphones"], "new headphones supersede a pending automatic speaker request")
            check(m.currentOutputId == headphones.id, "new connection event is not lost during a retry")
        }
        do {
            let mic = device(201, "mic", .input)
            let (m, audio, _, clock) = fixture([a, b, c, mic])
            audio.rejectedRows = [a.rowID]
            m.selectOutputDevice(a, in: .speaker)
            m.setInputDevice(mic)
            check(m.currentInputId == mic.id && m.pendingRouteRows.contains(a.rowID), "input confirmation leaves output request intact")
            clock.advance(by: 10)
            check(m.currentInputId == mic.id && m.routingFailure?.device.type == .output, "output failure never rolls back confirmed input")
        }
        do {
            let (m, audio, _, clock) = fixture()
            audio.appliesImmediately = false
            m.selectOutputDevice(b, in: .speaker)
            clock.advance(by: 1.31)
            check(audio.writes.count == 3 && m.routingFailure == nil, "final accepted write still has a confirmation window")
            audio.defaults[.output] = b.id
            clock.advance(by: 0.3)
            check(m.currentOutputId == b.id && m.routingFailure == nil, "delayed final confirmation succeeds without a fourth write")
        }
        do {
            let headphones = device(200, "headphones", name: "USB Headphones")
            let (m, audio, _, clock) = fixture([a, headphones], current: a.id, paused: false, inventoryReady: false)
            audio.inventoryAvailable = true
            clock.advance(by: 0.31)
            check(m.currentMode == .speaker && audio.writes.isEmpty, "startup read recovery respects the existing speaker route")
        }
        do {
            let headphones = device(200, "headphones", name: "USB Headphones")
            let (m, audio, _, clock) = fixture([a, headphones], current: a.id)
            audio.defaults[.output] = headphones.id
            audio.inventoryAvailable = false
            m.setCustomMode(false)
            audio.inventoryAvailable = true
            clock.advance(by: 0.31)
            check(m.currentMode == .headphone && audio.writes.isEmpty, "resume read recovery follows the route chosen while paused")
        }
        print("\(count) routing checks passed. No real audio service or persistent settings used.")
    }
}
