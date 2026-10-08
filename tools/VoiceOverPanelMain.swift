import SwiftUI
import AppKit
import CoreAudio

// Shows the panel with a sample set of devices in a fully transparent window and waits,
// so that tools/VoiceOverDump.swift can read it from outside the way VoiceOver does.
// Run it through tools/check-voiceover.sh, which gives this process its own settings
// with automatic switching off, so nothing here reaches the real audio devices.
//
//   soundpinvoiceover <seconds to stay open> [--lang en|zh-Hans]
@main struct VoiceOverPanelMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // The accessibility API gets no answer from an app that has not finished launching
        app.finishLaunching()

        let manager = AudioManager()
        manager.language = .english
        if let flag = CommandLine.arguments.firstIndex(of: "--lang"), flag + 1 < CommandLine.arguments.count {
            manager.language = AppLanguage(rawValue: CommandLine.arguments[flag + 1]) ?? .english
        }
        func device(_ id: AudioObjectID, _ name: String, _ type: AudioDeviceType) -> AudioDevice {
            AudioDevice(id: id, uid: "demo-\(id)", name: name, type: type)
        }
        manager.headphoneDevices = [device(9001, "AirPods Pro", .output)]
        manager.speakerDevices = [
            device(9002, "MacBook Pro Speakers", .output),
            device(9003, "Studio Display Speakers", .output),
            .disconnected(uid: "demo-gone", name: "Old Speaker", type: .output),
        ]
        manager.inputDevices = [
            device(9004, "Shure MV7+", .input),
            device(9006, "MacBook Pro Microphone", .input),
        ]
        manager.hiddenInputDevices = []
        manager.hiddenSpeakerDevices = []
        manager.hiddenHeadphoneDevices = []
        // Headphones are the list in use, so reordering the speakers applies nothing
        manager.currentMode = .headphone
        manager.currentOutputId = 9001
        manager.currentInputId = 9004
        manager.mutedRowIDs = ["output:demo-9002"]
        manager.volume = 0.6
        manager.hasVolumeControl = true

        let host = NSHostingView(rootView: MenuBarView().environmentObject(manager))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 308, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "SoundPin VoiceOver check"
        window.contentView = host
        // On screen but invisible: SwiftUI builds no accessibility elements for a window that is not shown
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()

        let seconds = CommandLine.arguments.dropFirst().compactMap(Double.init).first ?? 8
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        exit(0)
    }
}
