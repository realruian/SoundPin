import SwiftUI
import AppKit
import Combine

/// The production panel and menu bar item, backed only by in-memory services.
@main struct PanelAcceptanceMain: App {
    @NSApplicationDelegateAdaptor(AcceptanceDelegate.self) private var delegate
    init() {
        L10n.persistsSetting = false
        L10n.setting = .english
        if CommandLine.arguments.contains("--dark") { NSApplication.shared.appearance = NSAppearance(named: .darkAqua) }
    }
    var body: some Scene {
        MenuBarExtra("SoundPin Acceptance Check", systemImage: "checkmark.rectangle", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}

@MainActor
final class AcceptanceDelegate: NSObject, NSApplicationDelegate {
    private var panel: SoundPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = PreviewSupport.manager(listeningModes: true, delayedModes: true, battery: true)
        panel = SoundPanelController(
            content: MenuBarView().environmentObject(manager)
                .environment(\.panelReducedMotion, CommandLine.arguments.contains("--reduce-motion")),
            changes: manager.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            accessibilityLabel: "SoundPin Acceptance Check",
            symbol: { manager.menuBarSymbol })
    }
}
