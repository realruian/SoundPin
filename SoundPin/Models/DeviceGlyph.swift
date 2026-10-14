import AppKit
import CoreAudio

// Picks the symbol shown in a device's round icon
enum DeviceGlyph {
    static func symbol(for device: AudioDevice, category: OutputCategory?) -> String {
        symbol(name: device.name, type: device.type, category: category, transport: device.transportType)
    }

    static func symbol(name: String, type: AudioDeviceType, category: OutputCategory?, transport: UInt32?) -> String {
        candidates(name: name.lowercased(), type: type, category: category, transport: transport)
            .first(where: exists) ?? (type == .input ? "mic.fill" : "hifispeaker.fill")
    }

    // Most specific first; a symbol this macOS does not have is skipped
    private static func candidates(name: String, type: AudioDeviceType, category: OutputCategory?, transport: UInt32?) -> [String] {
        func has(_ words: String...) -> Bool {
            words.contains { name.contains($0) }
        }

        // Apple and Beats products, recognised by name
        if has("airpods max") { return ["airpods.max", "headphones"] }
        if has("airpods pro 3") { return ["airpods.pro.gen3", "airpods.pro"] }
        if has("airpods pro") { return ["airpods.pro"] }
        if has("airpods 4", "airpods4") { return ["airpods.gen4", "airpods"] }
        if has("airpods 3", "airpods3") { return ["airpods.gen3", "airpods"] }
        if has("airpods") { return ["airpods"] }
        if has("earpods") { return ["earpods", "headphones"] }
        if has("powerbeats pro") { return ["beats.powerbeats.pro", "beats.earphones", "headphones"] }
        if has("powerbeats") { return ["beats.powerbeats", "beats.earphones", "headphones"] }
        if has("beats fit") { return ["beats.fit.pro", "beats.earphones", "headphones"] }
        if has("studio buds") { return ["beats.studiobuds", "beats.earphones", "headphones"] }
        if has("solo buds") { return ["beats.solobuds", "beats.earphones", "headphones"] }
        if has("beats flex", "beatsx", "urbeats") { return ["beats.earphones", "headphones"] }
        if has("beats pill") { return ["beats.pill", "hifispeaker.fill"] }
        if has("beats") { return ["beats.headphones", "headphones"] }
        if has("iphone") { return ["iphone"] }
        if has("ipad") { return ["ipad"] }
        if has("homepod mini") { return ["homepodmini.fill", "homepod.fill"] }
        if has("homepod") { return ["homepod.fill"] }
        if has("apple tv") { return ["appletv.fill", "tv"] }
        if has("vision pro") { return ["vision.pro", "headphones"] }
        if has("macbook") { return ["macbook", "laptopcomputer"] }
        if has("mac mini") { return ["macmini.fill", "desktopcomputer"] }
        if has("mac studio") { return ["macstudio.fill", "desktopcomputer"] }
        if has("imac", "mac pro") { return ["desktopcomputer"] }

        if has("电视") || name.hasSuffix(" tv") || name.hasPrefix("tv ") || name.contains(" tv ") {
            return ["tv"]
        }
        // Screens: by name, or anything that plays over HDMI / DisplayPort
        if has("monitor", "display", "显示器")
            || transport == kAudioDeviceTransportTypeDisplayPort
            || transport == kAudioDeviceTransportTypeHDMI {
            return ["display"]
        }
        if transport == kAudioDeviceTransportTypeAirPlay { return ["airplayaudio"] }

        if type == .output {
            if category == .headphone { return ["headphones"] }
            if transport == kAudioDeviceTransportTypeBuiltIn { return ["desktopcomputer"] }
            return ["hifispeaker.fill"]
        }

        // A microphone that belongs to a headset shows as the headset
        if transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
            || has("headset", "headphone", "earphone", "耳机", "耳麦") {
            return ["headphones"]
        }
        return ["mic.fill"]
    }

    private static var known: [String: Bool] = [:]

    private static func exists(_ symbol: String) -> Bool {
        if let cached = known[symbol] { return cached }
        let found = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        known[symbol] = found
        return found
    }
}
