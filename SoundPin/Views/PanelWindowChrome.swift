import AppKit
import SwiftUI

/// A non-interactive companion draws only outside the real MenuBarExtra window.
/// AppKit continues to own the menu's focus, dismissal, placement and animations.
struct PanelWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> Attachment { Attachment() }
    func updateNSView(_ view: Attachment, context: Context) {}
    static func dismantleNSView(_ view: Attachment, coordinator: ()) { view.detach() }

    final class Attachment: NSView {
        private weak var owner: NSWindow?
        private var originalShadow = true
        private var shadowWindow: NSPanel?
        private var borderView: BorderView?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window !== owner else { return }
            detach()
            guard let window, window.styleMask.contains(.nonactivatingPanel) else { return }
            owner = window
            originalShadow = window.hasShadow
            let shadow = ShadowPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            shadow.title = "SoundPin panel shadow"
            shadow.isReleasedWhenClosed = false
            shadow.backgroundColor = .clear
            shadow.isOpaque = false
            shadow.hasShadow = false
            shadow.ignoresMouseEvents = true
            shadow.hidesOnDeactivate = false
            shadow.animationBehavior = .none
            shadow.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
            shadow.contentView = ShadowView()
            shadow.setAccessibilityElement(false)
            shadowWindow = shadow
            let border = BorderView()
            if let frameView = window.contentView?.superview {
                border.frame = frameView.bounds
                border.autoresizingMask = [.width, .height]
                frameView.addSubview(border, positioned: .above, relativeTo: nil)
            }
            borderView = border
            window.hasShadow = false
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification,
                         NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification,
                         NSWindow.didChangeScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.synchronize()
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.detach() })
            synchronize()
        }

        private func synchronize() {
            guard let owner, let shadowWindow else { return }
            let frame = owner.frame.insetBy(dx: -ShadowView.margin, dy: -ShadowView.margin)
            if shadowWindow.frame != frame { shadowWindow.setFrame(frame, display: true) }
            shadowWindow.appearance = owner.effectiveAppearance
            borderView?.appearance = owner.effectiveAppearance
            if owner.isVisible {
                if shadowWindow.parent !== owner { owner.addChildWindow(shadowWindow, ordered: .below) }
            } else {
                if shadowWindow.parent === owner { owner.removeChildWindow(shadowWindow) }
                shadowWindow.orderOut(nil)
            }
        }

        func detach() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            borderView?.removeFromSuperview()
            borderView = nil
            if let shadowWindow {
                shadowWindow.parent?.removeChildWindow(shadowWindow)
                shadowWindow.orderOut(nil)
                shadowWindow.close()
            }
            shadowWindow = nil
            owner?.hasShadow = originalShadow
            owner = nil
        }
        deinit { detach() }
    }

    final class ShadowPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    final class BorderView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
        override func draw(_ dirtyRect: NSRect) {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            (dark ? NSColor.white.withAlphaComponent(contrast ? 0.5 : 0.18) : NSColor.black.withAlphaComponent(contrast ? 0.4 : 0.16)).setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: 16, yRadius: 16)
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    final class ShadowView: NSView {
        static let margin: CGFloat = 32
        override func isAccessibilityElement() -> Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let body = NSBezierPath(roundedRect: bounds.insetBy(dx: Self.margin, dy: Self.margin), xRadius: 16, yRadius: 16)
            // Keep the material's backdrop untouched: no pixels under the menu body.
            let outside = NSBezierPath(rect: bounds)
            outside.append(body)
            outside.windingRule = .evenOdd
            outside.addClip()
            let shadow = NSShadow()
            // Tuned against captured Sound-menu edges; these are our drawing values,
            // not undocumented Apple window-server parameters.
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
            shadow.shadowBlurRadius = 24
            shadow.shadowOffset = NSSize(width: 0, height: -4)
            shadow.set()
            NSColor.black.setFill()
            body.fill()
        }
    }
}
