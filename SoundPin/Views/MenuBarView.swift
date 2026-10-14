import SwiftUI
import CoreAudio
import AppKit

// Laid out after the macOS Sound menu: title, volume slider, device rows with round icons.
// Text uses the system's built-in styles, matching the system menus: the title is Body
// emphasized (13 pt semibold), group names are Callout emphasized (12 pt semibold), and
// device names are Body (13 pt regular).
struct MenuBarView: View {
    @EnvironmentObject var audioManager: AudioManager
    @State private var deviceListHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.panelReducedMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeaderView()
                .padding(.horizontal, 14)
                .padding(.top, 12)

            VolumeSliderView()
                .padding(.horizontal, 14)
                .padding(.top, 6.5)
                .padding(.bottom, 9.5)

            PanelDivider()

            if audioManager.isDeviceReadUnavailable {
                HStack {
                    Text(L10n.deviceReadUnavailable).font(.caption)
                    Spacer()
                    Button(L10n.retry) { audioManager.retryDeviceRead() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Headphones are listed only when there are some (or while editing)
                    if !audioManager.headphoneDevices.isEmpty || audioManager.isEditMode {
                        DeviceSectionView(
                            title: L10n.headphones,
                            devices: audioManager.headphoneDevices,
                            currentDeviceId: audioManager.currentOutputId,
                            onMove: audioManager.moveHeadphoneDevice,
                            onSelect: { audioManager.selectOutputDevice($0, in: .headphone) },
                            onHide: { audioManager.hideDevice($0, category: .headphone) },
                            category: .headphone,
                            showCategoryPicker: true
                        )
                    }

                    DeviceSectionView(
                        title: L10n.speakers,
                        devices: audioManager.speakerDevices,
                        currentDeviceId: audioManager.currentOutputId,
                        onMove: audioManager.moveSpeakerDevice,
                        onSelect: { audioManager.selectOutputDevice($0, in: .speaker) },
                        onHide: { audioManager.hideDevice($0, category: .speaker) },
                        category: .speaker,
                        showCategoryPicker: true
                    )

                    PanelDivider()
                        .padding(.top, 5)
                        .padding(.bottom, 4)

                    DeviceSectionView(
                        title: L10n.microphones,
                        devices: audioManager.inputDevices,
                        currentDeviceId: audioManager.currentInputId,
                        onMove: audioManager.moveInputDevice,
                        onSelect: audioManager.setInputDevice,
                        onHide: { audioManager.hideDevice($0, category: nil) },
                        category: nil,
                        showCategoryPicker: false
                    )
                }
                .padding(.top, 4)
                .padding(.bottom, 5)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: DeviceListHeightKey.self, value: proxy.size.height)
                })
            }
            // A ScrollView has no height of its own, so size it to its content
            .frame(height: min(deviceListHeight, 460))
            .panelGeometryGroup()
            .onPreferenceChange(DeviceListHeightKey.self) { height in
                // Geometry reports the target layout. Animate that change once,
                // allowing the window and its content to share the system spring.
                guard abs(deviceListHeight - height) > 0.1 else { return }
                let animation = deviceListHeight == 0 || reduceMotion ? nil
                    : ListeningModeMotion.animation(expanding: height > deviceListHeight)
                withAnimation(animation) { deviceListHeight = height }
            }

            PanelDivider()

            PanelMenuRow(title: L10n.soundSettings) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 4.5)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await audioManager.refreshBatteryLevels() }
        }
        .task {
            while !Task.isCancelled {
                if NSApplication.shared.keyWindow?.isVisible == true {
                    await audioManager.refreshBatteryLevels()
                }
                do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                catch { return }
            }
        }
        .frame(width: 308)
        .panelGeometryGroup()
        .panelWindowAnchor()
        .background(PanelPositioner())
        .background(PanelWindowChrome())
        .alert(L10n.deviceSwitchFailed, isPresented: Binding(
            get: { audioManager.routingFailure != nil },
            set: { if !$0 { audioManager.routingFailure = nil } }
        ), presenting: audioManager.routingFailure) { failure in
            Button(L10n.retry) { audioManager.retryRoutingFailure(failure) }
            Button(L10n.done, role: .cancel) { audioManager.routingFailure = nil }
        } message: { failure in
            Text(L10n.deviceSwitchFailure(failure.device.name))
        }
    }
}

extension Color {
    /// Black in light mode and white in dark mode, at a fixed opacity. In the menu bar
    /// panel SwiftUI's default text style draws pure black and NSColor.labelColor draws
    /// too light, so the panel's tones are measured off the system menus and set outright.
    private static func tone(_ opacity: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: dark ? 1 : 0, alpha: opacity)
        })
    }

    /// Titles, device names and the settings row
    static let panelLabel = tone(0.855)
    /// The speaker glyphs at the ends of the volume slider
    static let panelGlyph = tone(0.515)
    /// The device glyph inside a circle that is not selected
    static let panelIcon = tone(0.44)
    /// Battery text and glyph use the lighter tone of the native accessory row.
    static let panelBattery = tone(0.42)
    /// Listening-mode symbols are lighter than the volume glyphs in the Sound menu.
    /// Keep a separate role so tuning them does not change device/volume icons.
    static let listeningModeIcon = tone(0.42)
    /// Keep the same visible label tone on the darker listening-mode surface.
    static let listeningModeLabel = tone(0.85)
    static let listeningModeBackground = tone(0.04)
}

private struct DeviceListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Corrects screen overflow while leaving MenuBarExtra in charge of valid anchors.
private struct PanelPositioner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        PositionerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class PositionerView: NSView {
        private var observers: [NSObjectProtocol] = []
        private var pendingReposition: DispatchWorkItem?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            let names = [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.didChangeScreenNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didChangeOcclusionStateNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.scheduleReposition()
                })
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.scheduleReposition()
            })
            scheduleReposition()
        }

        private func scheduleReposition() {
            // MenuBarExtra can still be placing/resizing its window in the notification.
            // Wait until that layout finishes instead of moving it reentrantly.
            guard pendingReposition == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingReposition = nil
                self.reposition()
            }
            pendingReposition = work
            DispatchQueue.main.async(execute: work)
        }

        private func reposition() {
            guard let window, window.isVisible else { return }
            // A removed display can leave the window without an associated screen.
            let screen = window.screen ?? NSScreen.screens.min { first, second in
                func distance(to screen: NSScreen) -> CGFloat {
                    let bounds = screen.visibleFrame
                    let dx = max(bounds.minX - window.frame.midX, 0, window.frame.midX - bounds.maxX)
                    let dy = max(bounds.minY - window.frame.midY, 0, window.frame.midY - bounds.maxY)
                    return dx * dx + dy * dy
                }
                return distance(to: first) < distance(to: second)
            }
            guard let screen else { return }
            let origin = PanelPlacement.origin(for: window.frame, screen: screen.frame,
                                               visibleFrame: screen.visibleFrame)
            guard origin != window.frame.origin else { return }
            window.setFrameOrigin(origin)
        }

        private func stopObserving() {
            pendingReposition?.cancel()
            pendingReposition = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        deinit {
            stopObserving()
        }
    }
}

struct PanelDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 14)
    }
}

// Title row. Everything the system menu has no place for lives in the menu on the right.
struct PanelHeaderView: View {
    @EnvironmentObject var audioManager: AudioManager
    @StateObject private var launchManager = LaunchAtLoginManager.shared

    private var ignoredDevices: [AudioDevice] {
        audioManager.hiddenHeadphoneDevices +
        audioManager.hiddenSpeakerDevices +
        audioManager.hiddenInputDevices
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.sound)
                .font(.body.weight(.semibold))
                .foregroundColor(.panelLabel)
                .accessibilityAddTraits(.isHeader)

            if audioManager.isCustomMode {
                Button {
                    audioManager.setCustomMode(false)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 9))
                        Text(L10n.autoSwitchPaused)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange))
                }
                .buttonStyle(.plain)
                .help(L10n.resumeAutoSwitchHelp)
                .accessibilityLabel(L10n.autoSwitchPaused)
            }

            Spacer()

            if audioManager.isEditMode {
                Button {
                    audioManager.toggleEditMode()
                } label: {
                    Text(L10n.done)
                        .font(.body.weight(.medium))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    Toggle(L10n.autoSwitch, isOn: Binding(
                        get: { !audioManager.isCustomMode },
                        set: { audioManager.setCustomMode(!$0) }
                    ))
                    Toggle(L10n.openAtLogin, isOn: Binding(
                        get: { launchManager.isEnabled },
                        set: { launchManager.setEnabled($0) }
                    ))
                    Divider()
                    Button(L10n.editDeviceList) {
                        audioManager.toggleEditMode()
                    }
                    // Ignored devices stay out of the panel; this is where they are brought back
                    if !ignoredDevices.isEmpty {
                        Menu(L10n.ignoredDevices) {
                            Section(L10n.stopIgnoring) {
                                ForEach(ignoredDevices, id: \.rowID) { device in
                                    Button {
                                        audioManager.unhideDevice(device)
                                    } label: {
                                        Label(device.name, systemImage: DeviceGlyph.symbol(for: device, category: device.type == .input ? nil : audioManager.priorityManager.getCategory(for: device)))
                                    }
                                }
                            }
                        }
                    }
                    Picker(L10n.language, selection: $audioManager.language) {
                        Text(L10n.systemDefault).tag(AppLanguage.system)
                        // Each language is listed under its own name
                        Text("English").tag(AppLanguage.english)
                        Text("简体中文").tag(AppLanguage.chinese)
                    }
                    Divider()
                    Button(L10n.quit) {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    // Named here: the symbol's own name, "More", is what VoiceOver would read otherwise
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .accessibilityLabel(L10n.options)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel(L10n.options)
                .fixedSize()
            }
        }
        .frame(height: 18)
        // The login item can be turned off in System Settings; read it again each time the panel opens
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            launchManager.refresh()
        }
    }
}

struct VolumeSliderView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 16))
                .foregroundColor(.panelGlyph)
                .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { Double(audioManager.volume) },
                    set: { audioManager.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .accessibilityLabel(L10n.volume)
            .accessibilityValue("\(Int((audioManager.volume * 100).rounded()))%")

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 16))
                .foregroundColor(.panelGlyph)
                .accessibilityHidden(true)
        }
        // An output with no volume the Mac can set, such as a screen: dimmed, as in the system menu
        .disabled(!audioManager.hasVolumeControl)
        .opacity(audioManager.hasVolumeControl ? 1 : 0.45)
        .help(audioManager.hasVolumeControl ? "" : L10n.noVolumeControl)
        .onScrollWheel { delta in
            let newVolume = audioManager.volume + Float(delta * 0.02)
            audioManager.setVolume(max(0, min(1, newVolume)))
        }
    }
}

// Scroll wheel modifier
struct ScrollWheelModifier: ViewModifier {
    let onScroll: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelReceiver(onScroll: onScroll)
        )
    }
}

struct ScrollWheelReceiver: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.deltaY)
    }
}

extension View {
    func onScrollWheel(_ action: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelModifier(onScroll: action))
    }
}

struct DeviceSectionView: View {
    let title: String
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let onMove: (DeviceMove) -> Void
    let onSelect: (AudioDevice) -> Void
    var onHide: ((AudioDevice) -> Void)?
    var category: OutputCategory?
    var showCategoryPicker: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 4.5)
                .accessibilityAddTraits(.isHeader)

            if devices.isEmpty {
                Text(L10n.noDevices)
                    .font(.body)
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            } else {
                DeviceListView(
                    devices: devices,
                    currentDeviceId: currentDeviceId,
                    onMove: onMove,
                    onSelect: onSelect,
                    showCategoryPicker: showCategoryPicker,
                    onHide: onHide,
                    category: category
                )
                .padding(.horizontal, 6)
            }
        }
    }
}

// A plain text row that highlights on hover, like "Sound Settings…" in the system menu
struct PanelMenuRow: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundColor(.panelLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.primary.opacity(0.07) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }
}
