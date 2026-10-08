import Foundation
import CoreAudio

// Checks that a burst of device-list notifications is handled once. The changes are made
// with private aggregate devices: only this process sees them, and no default device moves.
@main struct EventsCheckMain {
    static func main() {
        let service = AudioDeviceService()
        var handled = 0, raw = 0, failures = 0
        service.onDevicesChanged = { handled += 1 }
        service.startListening()

        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddress, DispatchQueue.main) { _, _ in raw += 1 }

        func create() -> AudioObjectID {
            let description: [String: Any] = [
                kAudioAggregateDeviceNameKey: "SoundPin events check",
                kAudioAggregateDeviceUIDKey: "soundpin-events-check-\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: 1,
            ]
            var id: AudioObjectID = 0
            let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
            if status != noErr { print("could not create a test device: \(status)"); exit(1) }
            return id
        }
        func report(_ what: String, expected: Int) {
            let ok = handled == expected && raw >= expected
            print((ok ? "ok   " : "FAIL ") + "\(what): \(raw) notifications, handled \(handled) time(s), expected \(expected)")
            if !ok { failures += 1 }
            raw = 0
            handled = 0
        }

        let main = DispatchQueue.main
        // Four changes 30 ms apart, all inside the 100 ms the service waits
        var a: AudioObjectID = 0, b: AudioObjectID = 0, c: AudioObjectID = 0
        main.asyncAfter(deadline: .now() + 0.20) { a = create() }
        main.asyncAfter(deadline: .now() + 0.23) { AudioHardwareDestroyAggregateDevice(a) }
        main.asyncAfter(deadline: .now() + 0.26) { b = create() }
        main.asyncAfter(deadline: .now() + 0.29) { AudioHardwareDestroyAggregateDevice(b) }
        main.asyncAfter(deadline: .now() + 1.20) { report("a burst of four changes", expected: 1) }
        // Two changes half a second apart
        main.asyncAfter(deadline: .now() + 1.30) { c = create() }
        main.asyncAfter(deadline: .now() + 1.80) { AudioHardwareDestroyAggregateDevice(c) }
        main.asyncAfter(deadline: .now() + 2.80) {
            report("two changes half a second apart", expected: 2)
            print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
            exit(failures == 0 ? 0 : 1)
        }
        dispatchMain()
    }
}
