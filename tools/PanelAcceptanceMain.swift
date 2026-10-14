import SwiftUI
import AppKit

/// The production panel in a real MenuBarExtra, backed only by in-memory services.
@main struct PanelAcceptanceMain: App {
    @StateObject private var manager = PreviewSupport.manager(listeningModes: true, delayedModes: true, battery: true)
    init() {
        L10n.persistsSetting = false
        L10n.setting = .english
        if CommandLine.arguments.contains("--dark") { NSApplication.shared.appearance = NSAppearance(named: .darkAqua) }
    }
    var body: some Scene {
        MenuBarExtra("SoundPin Acceptance Check", systemImage: "checkmark.rectangle") {
            MenuBarView().environmentObject(manager)
                .environment(\.panelReducedMotion, CommandLine.arguments.contains("--reduce-motion"))
        }
        .menuBarExtraStyle(.window)
    }
}
