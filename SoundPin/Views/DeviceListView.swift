import SwiftUI
import CoreAudio
import UniformTypeIdentifiers

struct DeviceListView: View {
    @EnvironmentObject var audioManager: AudioManager
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.panelReducedMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let onMove: (DeviceMove) -> Void
    let onSelect: (AudioDevice) -> Void
    var showCategoryPicker: Bool = false
    var onHide: ((AudioDevice) -> Void)?
    var isHiddenSection: Bool = false
    var category: OutputCategory? = nil

    @State private var draggingRowID: String?
    @State private var dragDevices: [AudioDevice] = []
    @State private var dragCancelled = false
    private var draggingIndex: Int? {
        guard !dragCancelled, DeviceMove.identities(in: dragDevices) == DeviceMove.identities(in: devices) else { return nil }
        return devices.firstIndex { $0.rowID == draggingRowID }
    }
    @State private var targetIndex: Int? = nil
    @State private var expandedUID: String?

    private let rowHeight: CGFloat = 32

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(devices.enumerated()), id: \.element.rowID) { index, device in
                DraggableDeviceRow(
                    device: device,
                    index: index,
                    isSelected: device.id == currentDeviceId,
                    onSelect: { onSelect(device) },
                    showCategoryPicker: showCategoryPicker,
                    onHide: onHide,
                    isHiddenSection: isHiddenSection,
                    category: category,
                    onMoveUp: index > 0 ? {
                        move(device.rowID, to: index - 1, in: devices)
                    } : nil,
                    onMoveDown: index < devices.count - 1 ? {
                        move(device.rowID, to: index + 2, in: devices)
                    } : nil,
                    onMoveToTop: index > 0 ? {
                        move(device.rowID, to: 0, in: devices)
                    } : nil,
                    isDragging: draggingIndex == index,
                    isDropTarget: isDropTarget(for: index),
                    isDropTargetBelow: isDropTargetBelow(for: index),
                    rowHeight: rowHeight,
                    deviceCount: devices.count,
                    onDragStarted: {
                        // Keep the existing fixed-height reorder calculation valid.
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            expandedUID = nil
                            draggingRowID = device.rowID
                            dragDevices = devices
                            dragCancelled = false
                            targetIndex = nil
                        }
                    },
                    onTargetChanged: { newTarget in
                        targetIndex = newTarget
                    },
                    onDragEnded: {
                        performMove(rowID: device.rowID)
                    },
                    onDragCancelled: { clearDrag(rowID: device.rowID) },
                    isListeningModeExpanded: expandedUID == device.uid,
                    onToggleListeningModes: listeningState(for: device) == nil ? nil : {
                        let expanding = expandedUID != device.uid
                        withAnimation(reduceMotion ? nil : ListeningModeMotion.animation(expanding: expanding)) {
                            expandedUID = expanding ? device.uid : nil
                        }
                    }
                )
                .zIndex(draggingIndex == index ? 100 : 0)
                if let state = listeningState(for: device) {
                    ListeningModeDisclosure(isExpanded: expandedUID == device.uid, state: state, reduceMotion: reduceMotion,
                                            requestState: audioManager.listeningModeRequests[device.uid],
                                            isUnavailable: audioManager.unavailableListeningModeUIDs.contains(device.uid),
                                            onRetry: { audioManager.retryListeningMode(for: device) },
                                            onRefresh: { audioManager.retryListeningModeRead() }) { mode in
                        audioManager.setListeningMode(mode, for: device)
                    }
                    .padding(.horizontal, -6)
                }
            }
        }
        .panelGeometryGroup()
        .onAppear { audioManager.refreshListeningModes() }
        .onChange(of: DeviceMove.identities(in: devices)) { identities in
            if draggingRowID != nil, identities != DeviceMove.identities(in: dragDevices) {
                dragCancelled = true
                targetIndex = nil
            }
        }
        .onReceive(audioManager.$listeningModes) { modes in
            if let uid = expandedUID, modes[uid] == nil { expandedUID = nil }
        }
    }

    private func listeningState(for device: AudioDevice) -> ListeningModeState? {
        guard device.isConnected, device.type == .output, !isHiddenSection else { return nil }
        return audioManager.listeningModes[device.uid]
    }

    private func isDropTarget(for index: Int) -> Bool {
        guard let target = targetIndex, let dragging = draggingIndex else { return false }
        return target == index && dragging != index && dragging != index - 1
    }

    private func isDropTargetBelow(for index: Int) -> Bool {
        guard let target = targetIndex, let dragging = draggingIndex else { return false }
        return target == devices.count && index == devices.count - 1 && dragging != devices.count - 1
    }

    private func move(_ rowID: String, to target: Int, in snapshot: [AudioDevice]) {
        if let move = DeviceMove(rowID: rowID, to: target, in: snapshot) { onMove(move) }
    }

    private func performMove(rowID: String) {
        guard draggingRowID == rowID else { return }
        if let target = targetIndex, draggingIndex != nil {
            move(rowID, to: target, in: dragDevices)
        }
        clearDrag(rowID: rowID)
    }

    private func clearDrag(rowID: String) {
        guard draggingRowID == rowID else { return }
        draggingRowID = nil
        dragDevices = []
        targetIndex = nil
    }
}

// Row wrapper that handles the drag gesture
struct DraggableDeviceRow: View {
    @EnvironmentObject var audioManager: AudioManager
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.panelReducedMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    let device: AudioDevice
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    var showCategoryPicker: Bool = false
    var onHide: ((AudioDevice) -> Void)?
    var isHiddenSection: Bool = false
    var category: OutputCategory? = nil
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onMoveToTop: (() -> Void)?
    let isDragging: Bool
    var isDropTarget: Bool = false
    var isDropTargetBelow: Bool = false
    let rowHeight: CGFloat
    let deviceCount: Int
    let onDragStarted: () -> Void
    let onTargetChanged: (Int?) -> Void
    let onDragEnded: () -> Void
    let onDragCancelled: () -> Void
    var isListeningModeExpanded = false
    var onToggleListeningModes: (() -> Void)?

    @State private var isHovering = false
    @State private var lastReportedTarget: Int? = nil
    @State private var gestureStarted = false
    @GestureState private var gestureActive = false

    var isDisconnected: Bool {
        !device.isConnected
    }

    var isIgnored: Bool {
        audioManager.isDeviceIgnored(device, inCategory: category)
    }

    var isGrayed: Bool {
        isDisconnected || isHiddenSection
    }

    var isNeverUse: Bool {
        audioManager.isNeverUse(device)
    }

    var isActive: Bool {
        isSelected && !isDisconnected
    }

    var statusIcon: String? {
        if isDisconnected {
            return "wifi.slash"
        } else if isIgnored && audioManager.isEditMode {
            return "eye.slash"
        } else if isNeverUse {
            return "nosign"
        }
        return nil
    }

    var lastSeenText: String? {
        guard isDisconnected,
              let stored = audioManager.priorityManager.getStoredDevice(for: device) else {
            return nil
        }
        return stored.lastSeenRelative
    }

    var isMuted: Bool {
        device.isConnected && audioManager.isDeviceMuted(device)
    }

    /// Device status read by VoiceOver after the name, including mute state.
    private var accessibilityStatus: String {
        var parts: [String] = []
        if isDisconnected {
            parts.append(L10n.notConnected)
            if let lastSeenText {
                parts.append(lastSeenText)
            }
        } else if isIgnored && audioManager.isEditMode {
            parts.append(L10n.ignored)
        } else if isNeverUse {
            parts.append(L10n.neverAutoSelect)
        }
        if isMuted {
            parts.append(L10n.muted)
        }
        if let battery = audioManager.battery(for: device) { parts.append(battery.details) }
        return parts.joined(separator: L10n.listSeparator)
    }

    /// The row context menu, one array per group between dividers. VoiceOver gets the same list as actions.
    private var menuActionGroups: [[RowAction]] {
        var groups: [[RowAction]] = []
        var order: [RowAction] = []
        if let onMoveToTop { order.append(RowAction(title: L10n.moveToTop, systemImage: "arrow.up.to.line", perform: onMoveToTop)) }
        if let onMoveUp { order.append(RowAction(title: L10n.moveUp, systemImage: "arrow.up", perform: onMoveUp)) }
        if let onMoveDown { order.append(RowAction(title: L10n.moveDown, systemImage: "arrow.down", perform: onMoveDown)) }
        if !order.isEmpty { groups.append(order) }

        if showCategoryPicker {
            groups.append([
                RowAction(title: L10n.moveToSpeakers, systemImage: "speaker.wave.2.fill") {
                    audioManager.setCategory(.speaker, for: device)
                },
                RowAction(title: L10n.moveToHeadphones, systemImage: "headphones") {
                    audioManager.setCategory(.headphone, for: device)
                },
            ])
        }

        if isHiddenSection || isIgnored {
            groups.append([
                RowAction(title: L10n.stopIgnoring, systemImage: "eye") {
                    audioManager.unhideDevice(device)
                },
            ])
        } else if let onHide {
            var group = [
                RowAction(title: L10n.ignore(in: device.type, category: category), systemImage: "eye.slash") {
                    onHide(device)
                },
            ]
            if device.type == .output {
                group.append(RowAction(title: L10n.ignoreEntirely, systemImage: "eye.slash.fill") {
                    audioManager.hideDeviceEntirely(device)
                })
            }
            groups.append(group)
        }

        if isDisconnected {
            groups.append([
                RowAction(title: L10n.forgetDevice, systemImage: "trash", isDestructive: true) {
                    audioManager.forgetDevice(device)
                },
            ])
        } else {
            let neverUse = audioManager.isNeverUse(device)
            groups.append([
                RowAction(
                    title: neverUse ? L10n.allowAutoSelect : L10n.neverAutoSelect,
                    systemImage: neverUse ? "checkmark.circle" : "nosign"
                ) {
                    audioManager.setNeverUse(device, neverUse: !neverUse)
                },
            ])
        }

        return groups
    }

    private func select() {
        guard !isDisconnected else { return }
        onSelect()

    }

    private func calculateTarget(offset: CGFloat) -> Int? {
        DeviceRowDragTarget.insertionIndex(index: index, offset: offset, rowHeight: rowHeight, count: deviceCount)
    }

    var body: some View {
        HStack(spacing: 8) {
            // The Sound menu uses system blue, independently of the user accent color.
            ZStack {
                Circle()
                    .fill(isActive ? Color(nsColor: .systemBlue) : Color.primary.opacity(0.1))
                Image(systemName: DeviceGlyph.symbol(for: device, category: category))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isActive ? .white : .panelIcon)
            }
            .frame(width: 26, height: 26)

            Text(device.name)
                .font(.body)
                .strikethrough(isNeverUse, color: .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isGrayed || isNeverUse ? .secondary : .panelLabel)

            if let icon = statusIcon {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            if let lastSeen = lastSeenText {
                Text(lastSeen)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer(minLength: 4)

            if let battery = audioManager.battery(for: device) {
                HStack(spacing: 3) {
                    Text(battery.compactText)
                        .font(.system(size: 12))
                    Image(systemName: battery.symbol)
                        .font(.system(size: 15))
                }
                .foregroundColor(.panelBattery)
                .fixedSize()
                .padding(.trailing, onToggleListeningModes == nil ? 0 : 4)
                .help(battery.details + "\n" + L10n.batteryReportHelp)
                .accessibilityHidden(true) // Included in the row's spoken value.
            }

            if let onToggleListeningModes {
                Button(action: onToggleListeningModes) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isListeningModeExpanded ? 90 : 0))
                        .animation(reduceMotion ? nil : ListeningModeMotion.animation(expanding: isListeningModeExpanded),
                                   value: isListeningModeExpanded)
                        .frame(width: 20, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isListeningModeExpanded ? L10n.hideListeningModes : L10n.showListeningModes)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: rowHeight)
        .opacity(isDragging ? 0.5 : (isGrayed ? 0.6 : 1.0))
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.primary.opacity(0.07) : Color.clear)
        )
        // Drop indicator above this row
        .overlay(alignment: .top) {
            if isDropTarget {
                DropIndicatorLine()
                    .offset(y: -1)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        // Drop indicator below this row (for last position)
        .overlay(alignment: .bottom) {
            if isDropTargetBelow {
                DropIndicatorLine()
                    .offset(y: 1)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        // Highlight the dragged row with a border instead of moving it
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDragging ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isDragging && !reduceMotion ? 1.02 : 1.0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isHovering)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isSelected)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: isDropTarget)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: isDropTargetBelow)
        .contentShape(Rectangle())
        .onTapGesture {
            select()
        }
        .modifier(DeviceRowKeyboardActivation(enabled: !isDisconnected, action: select))
        .gesture(
            DragGesture(minimumDistance: 5)
                .updating($gestureActive) { _, active, _ in active = true }
                .onChanged { value in
                    if !gestureStarted {
                        gestureStarted = true
                        onDragStarted()
                    }
                    let newTarget = calculateTarget(offset: value.translation.height)
                    if newTarget != lastReportedTarget {
                        lastReportedTarget = newTarget
                        onTargetChanged(newTarget)
                    }
                }
                .onEnded { _ in
                    gestureStarted = false
                    lastReportedTarget = nil
                    onDragEnded()
                }
        )
        .onChange(of: gestureActive) { active in
            // GestureState resets on cancellation too, when onEnded is not delivered.
            if !active {
                gestureStarted = false
                lastReportedTarget = nil
                onDragCancelled()
            }
        }
        .contextMenu {
            ForEach(Array(menuActionGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Divider()
                }
                ForEach(group) { action in
                    Button(role: action.isDestructive ? .destructive : nil, action: action.perform) {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            }
        }
        .help(device.name + (audioManager.battery(for: device).map { "\n" + $0.details + "\n" + L10n.batteryReportHelp } ?? ""))
        // VoiceOver reads the row as one button and exposes the context-menu
        // commands and pointer-only reordering as named actions.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("device-" + device.rowID)
        .accessibilityLabel(device.name)
        .accessibilityValue(accessibilityStatus)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
        .accessibilityActions {
            if let onToggleListeningModes {
                Button(isListeningModeExpanded ? L10n.hideListeningModes : L10n.showListeningModes,
                       action: onToggleListeningModes)
            }
            ForEach(menuActionGroups.flatMap { $0 }) { action in
                Button(action.title, action: action.perform)
            }
        }

    }
}

/// Convert the intended final row into the insertion index expected by DeviceMove.
/// Downward moves must skip the source row; otherwise they require an extra row of travel.
enum DeviceRowDragTarget {
    static func insertionIndex(index: Int, offset: CGFloat, rowHeight: CGFloat, count: Int) -> Int? {
        guard count > 0, (0..<count).contains(index), offset.isFinite, rowHeight > 0 else { return nil }
        let rows = (offset / rowHeight).rounded()
        let finalIndex = Int(max(0, min(CGFloat(count - 1), CGFloat(index) + rows)))
        guard finalIndex != index else { return nil }
        return finalIndex > index ? finalIndex + 1 : finalIndex
    }
}

/// Keep the row's pointer/drag behavior while making it an ordinary keyboard focus target.
private struct DeviceRowKeyboardActivation: ViewModifier {
    let enabled: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .focusable(enabled, interactions: .activate)
                .focused($isFocused)
                .onKeyPress(keys: [.space, .return], phases: .down) { press in
                    guard enabled, isFocused, press.modifiers.intersection([.command, .control, .option]).isEmpty else {
                        return .ignored
                    }
                    action()
                    return .handled
                }
        } else {
            content
                .focusable(enabled)
                .focused($isFocused)
                .background(DeviceRowKeyMonitor(isFocused: enabled && isFocused, action: action))
        }
    }
}

/// macOS 13 has FocusState but no onKeyPress. Monitor only the focused row's own window,
/// and pass every other event through unchanged. This never installs a global event tap.
struct DeviceRowKeyMonitor: NSViewRepresentable {
    let isFocused: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> DeviceRowKeyMonitorView { DeviceRowKeyMonitorView() }
    func updateNSView(_ view: DeviceRowKeyMonitorView, context: Context) {
        view.action = action
        view.isRowFocused = isFocused
    }
    static func dismantleNSView(_ view: DeviceRowKeyMonitorView, coordinator: ()) { view.stopMonitoring() }
}

final class DeviceRowKeyMonitorView: NSView {
    var action: (() -> Void)?
    var isRowFocused = false { didSet { updateMonitoring() } }
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateMonitoring() }

    private func updateMonitoring() {
        guard isRowFocused, window != nil else { stopMonitoring(); return }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard isRowFocused, let window, event.window === window, event.type == .keyDown,
              !event.isARepeat, [UInt16(36), 49, 76].contains(event.keyCode),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
        action?()
        return nil
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

/// One entry of a row's context menu
private struct RowAction: Identifiable {
    let title: String
    let systemImage: String
    var isDestructive = false
    let perform: () -> Void

    var id: String { title }
}

// Drop indicator line
struct DropIndicatorLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .padding(.horizontal, 2)
    }
}
