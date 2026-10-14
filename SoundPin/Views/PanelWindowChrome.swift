import AppKit
import Combine
import SwiftUI

/// The Sound panel, built the way Control Center builds its menus: a transparent window larger
/// than the panel. The glass is the system's own and draws its own shadow and edge in the room
/// around the panel; nothing here draws a shadow or border of its own. A MenuBarExtra window is
/// exactly as large as its content, which cuts that shadow off.
@MainActor
final class SoundPanelController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let window = SoundPanelWindow()
    private let hostingView: PanelHostingView
    private let content: AnyView
    private let symbol: () -> (name: String, value: Double?)
    private let accessibilityLabel: String
    private var cancellables: Set<AnyCancellable> = []
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    init(content: some View, changes: AnyPublisher<Void, Never>,
         accessibilityLabel: String, symbol: @escaping () -> (name: String, value: Double?)) {
        self.symbol = symbol
        self.accessibilityLabel = accessibilityLabel
        self.content = AnyView(content)
        hostingView = PanelHostingView(rootView: AnyView(EmptyView()))
        super.init()
        // The window keeps its size; the panel grows and shrinks inside it.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        // VoiceOver names the panel by its window title, as it reads "Control Center" for the Sound menu.
        window.title = accessibilityLabel
        window.onCancel = { [weak self] in self?.close() }

        if #available(macOS 27.0, *) {
            // The menu bar opens and closes the panel and shows the item pressed meanwhile, as for
            // its own menus; this also ends the panel when another menu bar item is opened.
            statusItem.expandedInterfaceDelegate = self
        } else if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle)
            // Opens on mouse down, like the system's menu bar items
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        statusItem.button?.setAccessibilityLabel(accessibilityLabel)
        updateButton()
        // objectWillChange fires before the change; read the new state on the next turn.
        changes.receive(on: RunLoop.main).sink { [weak self] in self?.updateButton() }.store(in: &cancellables)
    }

    convenience init(audioManager: AudioManager) {
        self.init(content: MenuBarView().environmentObject(audioManager),
                  changes: audioManager.objectWillChange.map { _ in }.eraseToAnyPublisher(),
                  accessibilityLabel: L10n.appName,
                  symbol: { audioManager.menuBarSymbol })
    }

    private var shownSymbol: (name: String, value: Double?)?

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let (name, value) = symbol()
        if let shown = shownSymbol, shown.name == name, shown.value == value { return }
        shownSymbol = (name, value)
        let image = value.map { NSImage(systemSymbolName: name, variableValue: $0, accessibilityDescription: accessibilityLabel) }
            ?? NSImage(systemSymbolName: name, accessibilityDescription: accessibilityLabel)
        image?.isTemplate = true
        button.image = image
    }

    var isOpen: Bool { window.isVisible }

    /// Before macOS 27, the item's own action opens and closes the panel.
    @objc func toggle() {
        isOpen ? close() : open()
    }

    /// The menu bar item in screen coordinates
    private var itemFrame: CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func open() {
        guard let buttonWindow = statusItem.button?.window, let item = itemFrame,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let layout = PanelPlacement.layout(itemFrame: item, itemWindowFrame: buttonWindow.frame,
                                           screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        let hostingView = hostingView
        hostingView.rootView = AnyView(SoundPanelRoot(content: content, topInset: layout.topInset) {
            hostingView.panelFrame = $0
        })
        window.setFrame(layout.windowFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        if #unavailable(macOS 27.0) {
            DispatchQueue.main.async { [weak self] in self?.statusItem.button?.highlight(true) }
        }
        startObserving()
    }

    /// Closing from the panel's side (Escape, a click outside). On macOS 27 the menu bar is told,
    /// and it ends the session, which hides the panel.
    func close() {
        if #available(macOS 27.0, *), let session = statusItem.expandedInterfaceSession {
            session.cancel()
        } else {
            hide()
        }
    }

    private func hide() {
        guard isOpen else { return }
        stopObserving()
        window.orderOut(nil)
        if #unavailable(macOS 27.0) {
            statusItem.button?.highlight(false)
        }
    }

    private func startObserving() {
        stopObserving()
        // Clicks in other apps, on the desktop or in the menu bar close the panel. On macOS 27 a
        // click on this app's own item does nothing while the panel is open, so it closes it here
        // too; before macOS 27 the item's action closes it, and closing here would reopen it.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            guard let self else { return }
            if let item = self.itemFrame, item.contains(NSEvent.mouseLocation) {
                if #available(macOS 27.0, *) { self.close() }
                return
            }
            self.close()
        }) { monitors.append(monitor) }
        // In this app: a click in the transparent room around the panel closes it, as Control Center does.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53, event.window === self.window { self.close(); return nil }
                return event
            }
            if event.window === self.window, !self.hostingView.panelContains(event.locationInWindow) {
                self.close()
                return nil
            }
            return event
        }) { monitors.append(monitor) }
        let center = NotificationCenter.default
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
    }

    private func stopObserving() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
    }
}

@available(macOS 27.0, *)
extension SoundPanelController: @preconcurrency NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        open()
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        hide()
    }
}

/// Places the panel content inside the larger transparent window.
private struct SoundPanelRoot<Content: View>: View {
    let content: Content
    let topInset: CGFloat
    let onPanelFrame: (CGRect) -> Void

    var body: some View {
        content
            .panelSurface()
            .background(GeometryReader { proxy in
                // Reported directly: a preference change was not delivered to the hosting view.
                Color.clear
                    .onAppear { onPanelFrame(proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { onPanelFrame($0) }
            })
            .padding(.top, topInset)
            .padding(.horizontal, PanelPlacement.sideInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension View {
    /// The panel's background. On macOS 26 and later it is the system glass, which also draws the
    /// panel's shadow and edge; measured against the Sound menu these match it with nothing added.
    @ViewBuilder
    func panelSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: PanelPlacement.cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            // Earlier systems have no glass. A menu material with the window shadow values AppKit
            // gives MenuBarExtra (density 0.25, radius 8, offset 4); not compared on those systems.
            background(PanelMaterial().clipShape(shape))
                .background {
                    shape.fill(Color.black)
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                        .mask(OutsideShape(cornerRadius: PanelPlacement.cornerRadius).fill(style: FillStyle(eoFill: true)))
                }
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
    }
}

/// Everything except a rounded rectangle, so a shadow can be drawn without a fill under the panel.
private struct OutsideShape: Shape {
    let cornerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -PanelPlacement.sideInset * 2, dy: -PanelPlacement.sideInset * 2))
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        return path
    }
}

private struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The room around the panel belongs to its shadow; clicks there close the panel.
final class PanelHostingView: NSHostingView<AnyView> {
    /// The panel as SwiftUI laid it out, in this view's coordinates.
    var panelFrame: CGRect = .zero

    func panelContains(_ pointInWindow: NSPoint) -> Bool {
        convert(panelFrame, to: nil).contains(pointInWindow)
    }
}

final class SoundPanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        // The glass draws the shadow inside the window; a window shadow would be a second one.
        hasShadow = false
        // Menu level, as the Sound menu (101). Setting isFloatingPanel would lower it to floating.
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
