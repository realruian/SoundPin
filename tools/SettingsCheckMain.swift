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

        print("Priority order")
        // The list on screen leaves out devices that are disconnected or ignored
        check("a pick while the top device is away keeps that device on top",
              PriorityManager.reorder(["desk-mic", "airpods", "built-in"], shown: ["built-in", "airpods"], moved: "built-in")
                == ["desk-mic", "built-in", "airpods"])
        check("moving to the end goes after the last device shown",
              PriorityManager.reorder(["a", "away", "b", "c"], shown: ["b", "c", "a"], moved: "a") == ["away", "b", "c", "a"])
        check("moving into the middle goes before the device now after it",
              PriorityManager.reorder(["a", "b", "away", "c"], shown: ["b", "a", "c"], moved: "a") == ["b", "away", "a", "c"])
        check("a device never ranked before can be moved to the top",
              PriorityManager.reorder(["a", "away"], shown: ["new", "a"], moved: "new") == ["new", "a", "away"])
        check("devices never ranked before come last, in the order shown",
              PriorityManager.reorder(["a"], shown: ["a", "new1", "moved", "new2"], moved: "moved") == ["a", "new1", "moved", "new2"])
        check("the first order to be stored is the order shown",
              PriorityManager.reorder([], shown: ["b", "a"], moved: "b") == ["b", "a"])
        check("a device that is not shown changes nothing",
              PriorityManager.reorder(["a", "b"], shown: ["a", "b"], moved: "gone") == ["a", "b"])
        check("an entry stored twice is stored once afterwards",
              PriorityManager.reorder(["a", "b", "a"], shown: ["b", "a"], moved: "b") == ["b", "a"])

        // The same through the stored settings: the desk microphone is unplugged, and the
        // built-in one is picked, which moves it to the top of the two that are listed
        let deskMic = AudioDevice(id: 81, uid: "desk-mic", name: "Desk Mic", type: .input)
        let airpods = AudioDevice(id: 82, uid: "airpods", name: "AirPods", type: .input)
        let builtIn = AudioDevice(id: 83, uid: "built-in", name: "Built-in", type: .input)
        defaults.set(["desk-mic", "airpods", "built-in"], forKey: "inputPriorities")
        pm.savePriorities([builtIn, airpods], moved: [builtIn], type: .input)
        check("the stored order still holds the unplugged device",
              (defaults.array(forKey: "inputPriorities") as? [String]) ?? [] == ["desk-mic", "built-in", "airpods"])
        check("plugged in again, it sorts to the top",
              pm.sortByPriority([builtIn, airpods, deskMic], type: .input).map { $0.uid } == ["desk-mic", "built-in", "airpods"])
        pm.savePriorities([airpods, builtIn], moved: [airpods], category: .speaker)
        check("each list has an order of its own",
              (defaults.array(forKey: "speakerPriorities") as? [String]) ?? [] == ["airpods", "built-in"]
                && (defaults.array(forKey: "inputPriorities") as? [String])?.first == "desk-mic")

        print("A list with no order yet")
        let monitor = AudioDevice(id: 91, uid: "monitor", name: "Monitor", type: .output)
        let laptop = AudioDevice(id: 92, uid: "laptop", name: "Laptop Speakers", type: .output)
        let gone = AudioDevice.disconnected(uid: "gone", name: "Gone", type: .output)
        defaults.removeObject(forKey: "speakerPriorities")
        defaults.removeObject(forKey: "headphonePriorities")
        check("with no order, devices sort as the system lists them",
              pm.sortByPriority([monitor, laptop], category: .speaker).map { $0.uid } == ["monitor", "laptop"])
        pm.seedPriorities([monitor, laptop], inUse: 55, category: .speaker)
        check("a device in use that is not in the list seeds nothing", defaults.object(forKey: "speakerPriorities") == nil)
        pm.seedPriorities([gone, monitor, laptop], inUse: 0, category: .speaker)
        check("a disconnected device is never the one in use", defaults.object(forKey: "speakerPriorities") == nil)
        pm.seedPriorities([monitor, laptop], inUse: 92, category: .speaker)
        check("the device in use goes on top",
              pm.sortByPriority([monitor, laptop], category: .speaker).map { $0.uid } == ["laptop", "monitor"])
        check("the other list is left without an order", defaults.object(forKey: "headphonePriorities") == nil)
        pm.seedPriorities([monitor, laptop], inUse: 91, category: .speaker)
        check("a list that has an order is not seeded again",
              (defaults.array(forKey: "speakerPriorities") as? [String]) ?? [] == ["laptop", "monitor"])

        print("Ignoring and forgetting")
        let dac = AudioDevice(id: 95, uid: "dac", name: "USB DAC", type: .output)
        let dacMic = AudioDevice(id: 95, uid: "dac", name: "USB DAC", type: .input)
        pm.hideDevice(dac, inCategory: .speaker)
        pm.hideDevice(dac, inCategory: .headphone)
        pm.hideDevice(dacMic)
        pm.unhideDevice(dac)
        check("an output ignored in both lists is back in both",
              !pm.isHidden(dac, inCategory: .speaker) && !pm.isHidden(dac, inCategory: .headphone))
        check("its microphone is still ignored", pm.isHidden(dacMic))
        pm.unhideDevice(dacMic)
        check("until that is stopped too", !pm.isHidden(dacMic))

        pm.rememberDevices([dac, dacMic, laptop])
        defaults.set(["laptop", "dac"], forKey: "speakerPriorities")
        defaults.set(["dac"], forKey: "headphonePriorities")
        defaults.set(["dac", "built-in"], forKey: "inputPriorities")
        pm.setCategory(.headphone, for: dac)
        pm.hideDevice(dac, inCategory: .headphone)
        pm.setNeverUse(dac, neverUse: true)
        pm.setNeverUse(dacMic, neverUse: true)
        pm.forgetDevice(dac)
        check("a forgotten output is no longer known", pm.getStoredDevice(for: dac) == nil)
        check("its microphone is still known", pm.getStoredDevice(for: dacMic) != nil)
        check("it has left the speaker order", (defaults.array(forKey: "speakerPriorities") as? [String]) ?? [] == ["laptop"])
        check("an order it was alone in is no order any more", defaults.object(forKey: "headphonePriorities") == nil)
        check("its list, ignoring and marking are forgotten",
              (defaults.dictionary(forKey: "deviceCategories") as? [String: String])?["dac"] == nil
                && !pm.isHidden(dac, inCategory: .headphone) && !pm.isNeverUse(dac))
        check("what was set for its microphone stays",
              pm.isNeverUse(dacMic) && (defaults.array(forKey: "inputPriorities") as? [String])?.contains("dac") == true)

        print("Last seen")
        let longAgo = Date(timeIntervalSinceNow: -8 * 3600)
        if var entries = try? JSONDecoder().decode([StoredDevice].self, from: defaults.data(forKey: "knownDevices") ?? Data()) {
            for index in entries.indices { entries[index].lastSeen = longAgo }
            defaults.set(try? JSONEncoder().encode(entries), forKey: "knownDevices")
        }
        check("a device last read hours ago shows as seen hours ago",
              pm.getStoredDevice(for: laptop).map { Date().timeIntervalSince($0.lastSeen) > 7 * 3600 } ?? false)
        pm.markLastSeen(uids: ["laptop"])
        check("once it is disconnected, it was last seen now",
              pm.getStoredDevice(for: laptop).map { Date().timeIntervalSince($0.lastSeen) < 60 } ?? false)
        check("other devices keep their time",
              pm.getStoredDevice(for: dacMic).map { Date().timeIntervalSince($0.lastSeen) > 7 * 3600 } ?? false)

        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
