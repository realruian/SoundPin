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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Headphones are listed only when there are some (or while editing)
                    if !audioManager.headphoneDevices.isEmpty || audioManager.isEditMode {
                        DeviceSectionView(
                            title: L10n.headphones,
                            devices: audioManager.headphoneDevices,
                            currentDeviceId: audioManager.currentOutputId,
                            onMove: audioManager.moveHeadphoneDevice,
                            onSelect: { device in
                                if !audioManager.isCustomMode {
                                    audioManager.setMode(.headphone)
                                }
                                audioManager.setOutputDevice(device)
                            },
                            onHide: { audioManager.hideDevice($0, category: .headphone) },
                            onUnhide: { audioManager.unhideDevice($0, category: .headphone) },
                            category: .headphone,
                            showCategoryPicker: true
                        )
                    }

                    DeviceSectionView(
                        title: L10n.speakers,
                        devices: audioManager.speakerDevices,
                        currentDeviceId: audioManager.currentOutputId,
                        onMove: audioManager.moveSpeakerDevice,
                        onSelect: { device in
                            if !audioManager.isCustomMode {
                                audioManager.setMode(.speaker)
                            }
                            audioManager.setOutputDevice(device)
                        },
                        onHide: { audioManager.hideDevice($0, category: .speaker) },
                        onUnhide: { audioManager.unhideDevice($0, category: .speaker) },
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
                        onUnhide: { audioManager.unhideDevice($0, category: nil) },
                        category: nil,
                        showCategoryPicker: false
                    )

                    if !audioManager.isEditMode {
                        HiddenDevicesToggleView()
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 5)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: DeviceListHeightKey.self, value: proxy.size.height)
                })
            }
            // A ScrollView has no height of its own, so size it to its content
            .frame(height: min(deviceListHeight, 460))
            .onPreferenceChange(DeviceListHeightKey.self) { deviceListHeight = $0 }

            PanelDivider()

            PanelMenuRow(title: L10n.soundSettings) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 4.5)
        }
        .frame(width: 308)
        .background(PanelPositioner())
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
}

private struct DeviceListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Moves the panel up to sit as close under the menu bar as the system's own panels do.
/// MenuBarExtra leaves 3.5 pt there; the system's Sound and Wi-Fi panels leave 0.5 pt.
private struct PanelPositioner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        PositionerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class PositionerView: NSView {
        private let gap: CGFloat = 0.5
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            let names = [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didChangeOcclusionStateNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.reposition()
                })
            }
            reposition()
        }

        private func reposition() {
            guard let window, let screen = window.screen else { return }
            let menuBarBottom = screen.visibleFrame.maxY
            // Only when there is a menu bar above and the panel hangs just below it
            guard menuBarBottom < screen.frame.maxY else { return }
            let distance = menuBarBottom - window.frame.maxY
            guard distance > gap + 0.25, distance < 12 else { return }
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: menuBarBottom - gap - window.frame.height))
        }

        private func stopObserving() {
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

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.sound)
                .font(.body.weight(.semibold))
                .foregroundColor(.panelLabel)

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
                    Toggle(L10n.openAtLogin, isOn: $launchManager.isEnabled)
                    Divider()
                    Button(L10n.editDeviceList) {
                        audioManager.toggleEditMode()
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
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .frame(height: 18)
    }
}

struct VolumeSliderView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 16))
                .foregroundColor(.panelGlyph)

            Slider(
                value: Binding(
                    get: { Double(audioManager.volume) },
                    set: { audioManager.setVolume(Float($0)) }
                ),
                in: 0...1
            )

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 16))
                .foregroundColor(.panelGlyph)
        }
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
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (AudioDevice) -> Void
    var onHide: ((AudioDevice) -> Void)?
    var onUnhide: ((AudioDevice) -> Void)?
    var category: OutputCategory?
    var showCategoryPicker: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 4.5)

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
                    onUnhide: onUnhide,
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

struct HiddenDevicesToggleView: View {
    @EnvironmentObject var audioManager: AudioManager
    @State private var isExpanded = false

    var allHiddenDevices: [AudioDevice] {
        audioManager.hiddenInputDevices +
        audioManager.hiddenSpeakerDevices +
        audioManager.hiddenHeadphoneDevices
    }

    var body: some View {
        if !allHiddenDevices.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Image(systemName: "eye.slash")
                        .font(.system(size: 11))
                    Text(L10n.ignoredCount(allHiddenDevices.count))
                        .font(.callout)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allHiddenDevices, id: \.rowID) { device in
                        HiddenDeviceRow(device: device)
                    }
                }
                .padding(12)
                .frame(minWidth: 220)
            }
        }
    }
}

struct HiddenDeviceRow: View {
    @EnvironmentObject var audioManager: AudioManager
    let device: AudioDevice
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: DeviceGlyph.symbol(for: device, category: device.type == .input ? nil : audioManager.priorityManager.getCategory(for: device)))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 18)

            Text(device.name)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if isHovering {
                Button {
                    audioManager.unhideDevice(device)
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.stopIgnoring)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

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
        if has("macbook") { return ["laptopcomputer"] }
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
