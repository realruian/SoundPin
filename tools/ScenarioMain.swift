import AppKit
import CoreAudio

// Prints which list and which icon each kind of device gets. Reads only; creates no AudioManager.
@main struct ScenarioMain {
    static func main() {
        let BT = kAudioDeviceTransportTypeBluetooth, USB = kAudioDeviceTransportTypeUSB
        let builtIn = kAudioDeviceTransportTypeBuiltIn, DP = kAudioDeviceTransportTypeDisplayPort
        let HDMI = kAudioDeviceTransportTypeHDMI, airPlay = kAudioDeviceTransportTypeAirPlay
        let virtual = kAudioDeviceTransportTypeVirtual, cont = kAudioDeviceTransportTypeContinuityCaptureWired
        let pm = PriorityManager()
        let outputs: [(String, UInt32)] = [
            ("AirPods 4 ANC", BT), ("AirPods Pro 3", BT), ("小明的 AirPods Pro", BT), ("AirPods", BT), ("AirPods Max", BT),
            ("Beats Studio Pro", BT), ("Powerbeats Pro 2", BT), ("Beats Flex", BT),
            ("WH-1000XM5", BT), ("Bose QC Ultra Headphones", BT), ("Soundcore Life Q30", BT), ("QCY T13", BT), ("EDIFIER W820NB", BT),
            ("External Headphones", builtIn), ("外置耳机", builtIn),
            ("Jabra Evolve2 65", USB), ("Logitech USB Headset", USB),
            ("MacBook Pro Speakers", builtIn), ("Mac mini Speakers", builtIn),
            ("Mi Monitor", DP), ("LG UltraGear", HDMI), ("Studio Display Speakers", USB), ("SAMSUNG TV", HDMI),
            ("JBL Flip 6", BT), ("Sony SRS-XB13", BT), ("EDIFIER R1700BT", BT), ("Marshall Stanmore", BT),
            ("Scarlett Solo USB", USB), ("HomePod", airPlay), ("客厅", airPlay), ("Apple TV", airPlay),
            ("BlackHole 2ch", virtual), ("Multi-Output Device", kAudioDeviceTransportTypeAggregate),
        ]
        let inputs: [(String, UInt32)] = [
            ("Wireless Mic Rx", USB), ("MacBook Pro Microphone", builtIn), ("External Microphone", builtIn),
            ("AirPods 4 ANC", BT), ("AirPods Pro 3", BT), ("WH-1000XM5", BT), ("QCY T13", BT),
            ("小明的 iPhone Microphone", cont), ("Studio Display Microphone", USB),
            ("Logitech USB Headset", USB), ("Yeti Stereo Microphone", USB), ("ZoomAudioDevice", virtual), ("BlackHole 2ch", virtual),
        ]
        func pad(_ s: String, _ n: Int) -> String {
            let w = s.unicodeScalars.reduce(0) { $0 + ($1.value > 0x2E80 ? 2 : 1) }
            return s + String(repeating: " ", count: max(1, n - w))
        }
        print("OUTPUTS: name | list it lands in | icon")
        for (name, t) in outputs {
            // Name-based part of the category rule; the screen guard needs a live device and is checked below
            var cat: OutputCategory = HeadphoneDetection.isHeadphone(deviceName: name) ? .headphone : .speaker
            if cat == .headphone && (t == DP || t == HDMI) { cat = .speaker }
            let sym = DeviceGlyph.symbol(name: name, type: .output, category: cat, transport: t)
            let ok = NSImage(systemSymbolName: sym, accessibilityDescription: nil) != nil
            print("  " + pad(name, 28) + pad(cat == .headphone ? "耳机" : "扬声器", 9) + sym + (ok ? "" : "  <-- MISSING SYMBOL"))
        }
        print("INPUTS: name | icon")
        for (name, t) in inputs {
            let sym = DeviceGlyph.symbol(name: name, type: .input, category: nil, transport: t)
            let ok = NSImage(systemSymbolName: sym, accessibilityDescription: nil) != nil
            print("  " + pad(name, 37) + sym + (ok ? "" : "  <-- MISSING SYMBOL"))
        }
        // Screen guard against a live DisplayPort/HDMI device, with a name that contains "ear"
        if CommandLine.arguments.count > 1, let liveId = UInt32(CommandLine.arguments[1]) {
            let fake = AudioDevice(id: liveId, uid: "scenario-test-uid", name: "LG UltraGear", type: .output)
            print("screen guard (live id \(liveId), named LG UltraGear): transport=\(fake.transportType.map(String.init) ?? "nil") -> \(pm.getCategory(for: fake))")
        }
    }
}
