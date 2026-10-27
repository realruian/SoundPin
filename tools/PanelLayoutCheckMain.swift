import AppKit
import SwiftUI
import CoreAudio

/// Exercises the production root without showing a window or linking real audio services.
@main struct PanelLayoutCheckMain {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        L10n.persistsSetting = false
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            checks += 1
        }
        for height: CGFloat in [360, 500, 900] {
            for language in [AppLanguage.english, .chinese] {
                let manager = PreviewSupport.manager()
                manager.setCustomMode(true)
                manager.language = language
                manager.speakerDevices = (0..<30).map {
                    AudioDevice(id: UInt32(1000 + $0), uid: "layout-\($0)", name: "Speaker \($0)", type: .output)
                }
                var panelFrame = CGRect.zero
                let maximum = height - PanelPlacement.topInset - PanelPlacement.sideInset
                let host = NSHostingView(rootView: SoundPanelRoot(
                    content: MenuBarView().environmentObject(manager), topInset: PanelPlacement.topInset,
                    maximumPanelHeight: maximum, onPanelFrame: { panelFrame = $0 }))
                host.sizingOptions = []
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 372, height: height),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                for _ in 0..<12 {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.025))
                    host.layoutSubtreeIfNeeded()
                }
                check(!window.isVisible, "layout checks never display a window")
                check(abs(panelFrame.minY - PanelPlacement.topInset) < 1, "panel keeps its top anchor at \(height) pt")
                check(panelFrame.maxY <= height - PanelPlacement.sideInset + 1, "content and shadow fit a \(height) pt window")
                if height == 900 { check(abs(panelFrame.height - 559) < 1, "normal-screen geometry remains unchanged") }
                print("Layout \(language.rawValue), window \(height): \(panelFrame)")
            }
        }

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let otherWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let monitor = DeviceRowKeyMonitorView()
        window.contentView = monitor
        var activations = 0
        monitor.action = { activations += 1 }
        func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false, other: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: other ? otherWindow.windowNumber : window.windowNumber,
                context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: repeatKey, keyCode: code)!
        }
        check(monitor.handle(key(49)) != nil && activations == 0, "unfocused rows cannot activate")
        monitor.isRowFocused = true
        for code: UInt16 in [49, 36, 76] {
            check(monitor.handle(key(code)) == nil, "Space, Return and keypad Enter activate on macOS 13")
        }
        check(activations == 3, "one activation per key down")
        check(monitor.handle(key(49, other: true)) != nil, "other windows retain their input")
        check(monitor.handle(key(49, flags: .command)) != nil, "system shortcuts pass through")
        check(monitor.handle(key(49, repeatKey: true)) != nil, "held keys do not repeatedly select a device")
        check(monitor.handle(key(48)) != nil, "Tab remains available for focus navigation")
        check(activations == 3, "unrelated input does not select a device")
        monitor.isRowFocused = false

        check(DeviceRowDragTarget.insertionIndex(index: 0, offset: 32, rowHeight: 32, count: 3) == 2,
              "down one row means move down once")
        check(DeviceRowDragTarget.insertionIndex(index: 1, offset: -32, rowHeight: 32, count: 3) == 0,
              "up one row means move up once")
        for offset: CGFloat in [-15, 0, 15] {
            check(DeviceRowDragTarget.insertionIndex(index: 1, offset: offset, rowHeight: 32, count: 3) == nil,
                  "small movements in either direction preserve the row")
        }
        check(DeviceRowDragTarget.insertionIndex(index: 0, offset: 1000, rowHeight: 32, count: 3) == 3,
              "downward dragging clamps to the list end")
        check(DeviceRowDragTarget.insertionIndex(index: 2, offset: -1000, rowHeight: 32, count: 3) == 0,
              "upward dragging clamps to the list start")
        print("Passed \(checks) hidden panel, keyboard adapter and drag checks.")
    }
}
