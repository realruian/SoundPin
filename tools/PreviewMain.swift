import SwiftUI
import AppKit
import CoreAudio

// Renders the panel to a PNG for a visual check, since the real menu bar panel
// cannot be captured from outside. Run it through tools/render-preview.sh, which
// gives this process its own copy of the settings with automatic switching off,
// so creating AudioManager here applies nothing to the audio devices.
//
//   soundpinpreview <output.png> [--manual-look] [--edit-look] [--demo] [--lang en|zh-Hans]
//
// --demo swaps this Mac's devices for a sample set and frames the panel, for a
// screenshot that can be published.
@main struct PreviewMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let out = CommandLine.arguments[1]
        let manager = AudioManager()
        // Shown as automatic unless asked otherwise. Only the published flag is flipped;
        // the copied priorities match the real app's, so a device event during the
        // render would pick the same devices the real app picks.
        if !CommandLine.arguments.contains("--manual-look") { manager.isCustomMode = false }
        if CommandLine.arguments.contains("--edit-look") { manager.toggleEditMode() }
        if let flag = CommandLine.arguments.firstIndex(of: "--lang"), flag + 1 < CommandLine.arguments.count {
            manager.language = AppLanguage(rawValue: CommandLine.arguments[flag + 1]) ?? .system
        }

        let demo = CommandLine.arguments.contains("--demo")
        if demo {
            func device(_ id: AudioObjectID, _ name: String, _ type: AudioDeviceType) -> AudioDevice {
                AudioDevice(id: id, uid: "demo-\(id)", name: name, type: type)
            }
            manager.headphoneDevices = [device(9001, "AirPods Pro", .output)]
            manager.speakerDevices = [
                device(9002, "MacBook Pro Speakers", .output),
                device(9003, "Studio Display Speakers", .output),
            ]
            manager.inputDevices = [
                device(9004, "Shure MV7+", .input),
                device(9005, "AirPods Pro", .input),
                device(9006, "MacBook Pro Microphone", .input),
            ]
            manager.hiddenInputDevices = []
            manager.hiddenSpeakerDevices = []
            manager.hiddenHeadphoneDevices = []
            manager.currentMode = .headphone
            manager.currentOutputId = 9001
            manager.currentInputId = 9004
            manager.mutedRowIDs = []
            manager.volume = 0.6
        }

        let panel = MenuBarView()
            .environmentObject(manager)
            .background(Color(nsColor: .windowBackgroundColor))
        let root: AnyView = demo
            ? AnyView(panel
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.black.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .padding(28))
            : AnyView(panel)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 308, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host

        // The device list reports its height after the first layout pass
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("could not create a bitmap")
            exit(1)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        print("rendered \(Int(size.width))x\(Int(size.height))")
    }
}
