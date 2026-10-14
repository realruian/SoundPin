import Foundation
import CoreAudio

@main struct InteractionCheckMain {
    @MainActor static func main() async {
        L10n.persistsSetting = false
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            count += 1
            print("ok: \(name)")
        }
        let a = AudioDevice(id: 101, uid: "a", name: "Speaker A", type: .output)
        let b = AudioDevice(id: 102, uid: "b", name: "Speaker B", type: .output)
        let c = AudioDevice(id: 103, uid: "c", name: "Speaker C", type: .output)
        let headphones = AudioDevice(id: 104, uid: "h", name: "USB Headphones", type: .output)
        func fixture(_ devices: [AudioDevice] = [a, b, c], current: UInt32 = 101)
            -> (AudioManager, SimulatedAudioService, MemoryPreferences, TestAudioScheduler) {
            let audio = SimulatedAudioService()
            audio.devices = devices
            audio.defaults[.output] = current
            let prefs = MemoryPreferences()
            prefs.set(true, forKey: "customMode")
            prefs.set(["a", "b", "c"], forKey: "speakerPriorities")
            let clock = TestAudioScheduler()
            let manager = AudioManager(deviceService: audio, listeningModeService: SimulatedListeningModes(),
                                       priorityManager: PriorityManager(defaults: prefs), scheduler: clock)
            return (manager, audio, prefs, clock)
        }
        func notify(_ audio: SimulatedAudioService) async {
            audio.onDevicesChanged?()
            for _ in 0..<10 { await Task.yield() }
        }
        do {
            let (m, audio, prefs, _) = fixture()
            m.moveSpeakerDevice(DeviceMove(rowID: c.rowID, to: 0, in: m.speakerDevices)!)
            check(m.speakerDevices.map(\.uid) == ["c", "a", "b"], "identity move to top moves the intended row")
            m.moveSpeakerDevice(DeviceMove(rowID: c.rowID, to: 3, in: m.speakerDevices)!)
            check(m.speakerDevices.map(\.uid) == ["a", "b", "c"], "identity move to end preserves neighbor order")
            m.moveSpeakerDevice(DeviceMove(rowID: a.rowID, to: 2, in: m.speakerDevices)!)
            check(m.speakerDevices.map(\.uid) == ["b", "a", "c"], "move down matches VoiceOver action semantics")
            check(prefs.array(forKey: "speakerPriorities") as? [String] == ["b", "a", "c"] && audio.writes.isEmpty,
                  "paused reorder persists order without routing")
            check(DeviceMove(rowID: b.rowID, to: 1, in: m.speakerDevices) == nil,
                  "adjacent insertion is a no-op")
        }
        do {
            let (m, audio, prefs, clock) = fixture()
            let move = DeviceMove(rowID: c.rowID, to: 0, in: m.speakerDevices)!
            audio.devices = [b, c]
            await notify(audio)
            let order = prefs.array(forKey: "speakerPriorities") as? [String]
            audio.rejectedRows = [b.rowID]
            m.selectOutputDevice(b, in: .speaker)
            m.moveSpeakerDevice(move)
            check(prefs.array(forKey: "speakerPriorities") as? [String] == order,
                  "removing an earlier row cancels stale drag without writing priorities")
            clock.advance(by: 10)
            check(audio.writes.count == 3, "cancelled drag does not cancel unrelated pending selection")
        }
        do {
            let (m, audio, _, _) = fixture()
            let move = DeviceMove(rowID: c.rowID, to: 0, in: m.speakerDevices)!
            m.hideDevice(b, category: .speaker)
            m.moveSpeakerDevice(move)
            check(m.speakerDevices.map(\.uid) == ["a", "c"], "hiding a row during drag cancels stale intent")
            audio.devices = [a, b, c, headphones]
            await notify(audio)
            let hMove = DeviceMove(rowID: c.rowID, to: 0, in: m.speakerDevices)!
            m.setCategory(.headphone, for: c)
            m.moveSpeakerDevice(hMove)
            check(m.speakerDevices.map(\.uid) == ["a"], "changing source category cannot move a replacement row")
        }
        do {
            let move = DeviceMove(rowID: c.rowID, to: 0, in: [a, b, c])!
            let recycled = AudioDevice(id: c.id, uid: "other", name: "Other", type: .output)
            check(move.resolve(in: [a, b, recycled]) == nil, "reused HAL id does not preserve drag identity")
            let reconnected = AudioDevice(id: 303, uid: c.uid, name: c.name, type: .output)
            check(move.resolve(in: [a, b, reconnected]) == nil, "reconnection cancels gesture even with same UID")
            let offline = AudioDevice.disconnected(uid: c.uid, name: c.name, type: .output)
            check(move.resolve(in: [a, b, offline]) == nil, "disconnection in editor cancels active gesture")
            check(move.resolve(in: [b, a, c]) == nil, "concurrent reorder cancels old gesture")
            let renamed = AudioDevice(id: c.id, uid: c.uid, name: "New Name", type: .output)
            check(move.resolve(in: [a, b, renamed]) != nil, "display-only rename does not cancel gesture")
            let (m, audio, _, _) = fixture()
            audio.devices = [a, b]
            await notify(audio)
            m.toggleEditMode()
            m.moveSpeakerDevice(DeviceMove(rowID: c.rowID, to: 0, in: m.speakerDevices)!)
            check(m.speakerDevices.first?.uid == "c" && m.speakerDevices.first?.isConnected == false,
                  "offline devices can still be intentionally reordered in editor")
        }
        do {
            let mic = AudioDevice(id: a.id, uid: a.uid, name: "Microphone", type: .input)
            let (m, audio, _, _) = fixture([a, mic, headphones])
            audio.mutedRows = [a.rowID]
            m.hideDevice(a, category: .speaker)
            m.refreshMuteStatus()
            check(m.isActiveOutputMuted && m.menuBarSymbol.name == "speaker.slash.fill",
                  "hidden active speaker still reports mute in menu bar")
            check(m.isDeviceMuted(a) && !m.isDeviceMuted(mic), "duplex mute stays endpoint-specific")
            m.hideDevice(headphones, category: .headphone)
            audio.defaults[.output] = headphones.id
            m.refreshVolume()
            m.refreshMuteStatus()
            check(m.menuBarSymbol.name == DeviceGlyph.symbol(for: headphones, category: .headphone),
                  "hidden active headphones still supply the menu bar glyph")
            check(m.hasVolumeControl && m.setVolume(0.4), "hidden current output retains usable volume control")
            audio.defaults[.output] = a.id
            audio.inventoryAvailable = false
            await notify(audio)
            check(m.isDeviceReadUnavailable && m.currentOutputId == a.id && m.isActiveOutputMuted,
                  "inventory failure does not freeze independently readable active status")
        }
        do {
            let (m, audio, _, _) = fixture()
            audio.mutedRows = [a.rowID]
            audio.rejectsVolume = true
            check(!m.setVolume(0.8) && m.volume == 0.6, "rejected write rolls slider back to actual volume")
            check(audio.unmuteWrites.isEmpty && m.isActiveOutputMuted, "rejected volume write never unmutes")
            audio.rejectsVolume = false
            audio.appliesVolume = false
            check(!m.setVolume(0.8) && m.volume == 0.6 && audio.unmuteWrites.isEmpty,
                  "accepted but unapplied volume write is not shown as successful")
            audio.appliesVolume = true
            check(m.setVolume(0.8) && m.volume == 0.8 && !m.isActiveOutputMuted,
                  "confirmed positive volume unmutes and refreshes status")
            audio.mutedRows = [a.rowID]
            let unmutes = audio.unmuteWrites.count
            check(m.setVolume(-1) && m.volume == 0 && audio.unmuteWrites.count == unmutes,
                  "zero-clamped volume does not unmute")
            check(m.setVolume(2) && m.volume == 1, "finite out-of-range volume is clamped")
            let writes = audio.volumeWrites.count
            check(!m.setVolume(.nan) && !m.setVolume(.infinity) && audio.volumeWrites.count == writes,
                  "non-finite volume never reaches the audio service")
        }
        do {
            let (m, audio, _, _) = fixture()
            audio.volumeReadable = false
            m.refreshVolume()
            check(!m.hasVolumeControl && m.volume == 0.6 && !m.setVolume(0.8),
                  "unreadable volume disables slider without inventing zero")
            audio.volumeReadable = true
            audio.volumeSettable = false
            m.refreshVolume()
            check(!m.hasVolumeControl && !m.setVolume(0.8) && audio.volumeWrites.isEmpty,
                  "fixed-volume outputs cannot be written")
            audio.volumeSettable = true
            audio.volume = .nan
            m.refreshVolume()
            check(!m.hasVolumeControl && m.volume.isFinite, "invalid driver scalar cannot poison slider")
        }
        do {
            let (m, audio, _, _) = fixture()
            audio.mutedRows = [a.rowID, b.rowID]
            audio.beforeVolumeWrite = { audio.defaults[.output] = b.id }
            check(!m.setVolume(0.8) && audio.volumeWrites.isEmpty && audio.unmuteWrites.isEmpty,
                  "route change before volume write never modifies replacement output")
            check(m.currentOutputId == b.id && m.isActiveOutputMuted, "rejected gesture refreshes replacement status")
        }
        do {
            let (m, audio, _, _) = fixture()
            audio.mutedRows = [a.rowID, b.rowID]
            audio.beforeUnmute = { audio.defaults[.output] = b.id; audio.volume = 0.2 }
            check(!m.setVolume(0.8) && audio.unmuteWrites.isEmpty && audio.mutedRows.contains(b.rowID),
                  "route change after write never unmutes replacement output")
            check(m.currentOutputId == b.id && m.volume == 0.2, "post-unmute refresh follows actual new output")
        }
        do {
            let (m, audio, _, _) = fixture()
            audio.beforeVolumeWrite = {
                audio.devices = [AudioDevice(id: a.id, uid: "replacement", name: "Other", type: .output), b, c]
            }
            check(!m.setVolume(0.8) && audio.volumeWrites.isEmpty, "volume write rejects recycled device ID")
        }
        do {
            let (m, audio, _, _) = fixture()
            audio.rejectsUnmute = true
            audio.mutedRows = [a.rowID]
            check(!m.setVolume(0.8) && m.volume == 0.8 && m.isActiveOutputMuted,
                  "failed unmute retains actual mute state alongside accepted volume")
        }
        print("\(count) interaction checks passed. No real audio service or persistent settings used.")
    }
}
