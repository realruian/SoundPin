import Foundation

// Checks what PriorityManager stores about devices: the list of known devices and the
// "never select automatically" list. Runs in this executable's own settings domain,
// which tools/check-settings.sh removes afterwards. Touches no audio device.
@main struct SettingsCheckMain {
    static func main() {
        let pm = PriorityManager()
        let defaults = UserDefaults.standard
        var failures = 0
        func check(_ what: String, _ ok: Bool) {
            print((ok ? "ok   " : "FAIL ") + what)
            if !ok { failures += 1 }
        }

        // A USB headset: one id and one UID for its microphone and its speaker
        let mic = AudioDevice(id: 71, uid: "usb-headset", name: "USB Headset", type: .input)
        let out = AudioDevice(id: 71, uid: "usb-headset", name: "USB Headset", type: .output)
        let other = AudioDevice(id: 72, uid: "other-mic", name: "Other Mic", type: .input)

        print("Known devices")
        pm.rememberDevices([mic, out, other])
        var known = pm.getKnownDevices()
        check("three entries are stored", known.count == 3)
        check("the headset is stored as an input", known.contains { $0.uid == "usb-headset" && $0.isInput })
        check("the headset is stored as an output", known.contains { $0.uid == "usb-headset" && !$0.isInput })
        pm.rememberDevices([mic, out, other])
        check("remembering again adds nothing", pm.getKnownDevices().count == 3)
        pm.forgetDevice(mic)
        known = pm.getKnownDevices()
        check("forgetting the microphone removes one entry", known.count == 2)
        check("the headset's output is still known", known.contains { $0.uid == "usb-headset" && !$0.isInput })

        print("Row identities")
        check("the two sides of one device differ", mic.rowID != out.rowID)
        let gone1 = AudioDevice.disconnected(uid: "a", name: "A", type: .output)
        let gone2 = AudioDevice.disconnected(uid: "b", name: "B", type: .output)
        check("two disconnected devices share id 0 but not a row identity", gone1.id == gone2.id && gone1.rowID != gone2.rowID)

        print("Never select automatically")
        pm.setNeverUse(mic, neverUse: true)
        check("marking the microphone marks the microphone", pm.isNeverUse(mic))
        check("marking the microphone leaves the speaker alone", !pm.isNeverUse(out))
        pm.setNeverUse(mic, neverUse: true)
        check("marking twice stores one entry", (defaults.array(forKey: "neverUseDevices") as? [String])?.count == 1)
        pm.setNeverUse(mic, neverUse: false)
        check("unmarking clears it", !pm.isNeverUse(mic) && !pm.isNeverUse(out))

        // An entry as 2.2.1 and earlier wrote it: a bare UID that covers both sides
        defaults.set(["usb-headset", "someone-else"], forKey: "neverUseDevices")
        check("an older entry still covers both sides", pm.isNeverUse(mic) && pm.isNeverUse(out))
        pm.setNeverUse(mic, neverUse: false)
        check("unmarking one side of an older entry frees that side", !pm.isNeverUse(mic))
        check("and keeps the other side marked", pm.isNeverUse(out))
        check("other devices' entries are untouched", (defaults.array(forKey: "neverUseDevices") as? [String])?.contains("someone-else") == true)

        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
