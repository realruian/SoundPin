import SwiftUI
import AppKit
import CoreAudio

// Renders sample devices only, using in-memory audio and preferences.
// --demo adds a frame; --manual-look and --edit-look select sample states.
@main struct PreviewMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--dark") {
            app.appearance = NSAppearance(named: CommandLine.arguments.contains("--high-contrast")
                                          ? .accessibilityHighContrastDarkAqua : .darkAqua)
        } else if CommandLine.arguments.contains("--high-contrast") {
            app.appearance = NSAppearance(named: .accessibilityHighContrastAqua)
        }
        let out = CommandLine.arguments[1]
        let showsBattery = CommandLine.arguments.contains("--battery")
        let manager = PreviewSupport.manager(listeningModes: showsBattery, battery: showsBattery)
        if showsBattery { Task { await manager.refreshBatteryLevels() } }
        manager.setCustomMode(CommandLine.arguments.contains("--manual-look"))
        if CommandLine.arguments.contains("--edit-look") { manager.toggleEditMode() }
        if let flag = CommandLine.arguments.firstIndex(of: "--lang"), flag + 1 < CommandLine.arguments.count {
            manager.language = AppLanguage(rawValue: CommandLine.arguments[flag + 1]) ?? .system
        }

        let demo = CommandLine.arguments.contains("--demo")
        let panel: AnyView
        if let flag = CommandLine.arguments.firstIndex(of: "--listening-state"), flag + 1 < CommandLine.arguments.count {
            let sample = CommandLine.arguments[flag + 1]
            guard ["ready", "pending", "failed", "unavailable"].contains(sample) else { exit(2) }
            let state = ListeningModeState(currentRawValue: sample == "unavailable" ? 0 : 2, supportedMask: 7)
            let request: ListeningModeRequestState? = sample == "pending" ? .pending(.transparency)
                : sample == "failed" ? .failed(.transparency, .timedOut) : nil
            panel = AnyView(ListeningModeView(state: state, requestState: request,
                                              isUnavailable: sample == "unavailable", onRetry: {}, onRefresh: {}) { _ in }
                .frame(width: 308).padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor)))
        } else {
            panel = AnyView(MenuBarView()
                .environmentObject(manager)
                .background(Color(nsColor: .windowBackgroundColor)))
        }
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
        do {
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
            try png.write(to: URL(fileURLWithPath: out))
        } catch {
            print("could not write preview: \(error)")
            exit(1)
        }
        print("rendered \(Int(size.width))x\(Int(size.height))")
    }
}
