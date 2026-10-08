import SwiftUI
import CoreAudio
import UniformTypeIdentifiers

struct DeviceListView: View {
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (AudioDevice) -> Void
    var showCategoryPicker: Bool = false
    var onHide: ((AudioDevice) -> Void)?
    var isHiddenSection: Bool = false
    var category: OutputCategory? = nil

    // Only track which item is being dragged and the target - not the offset
    @State private var draggingIndex: Int? = nil
    @State private var targetIndex: Int? = nil

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
                        onMove(IndexSet(integer: index), index - 1)
                    } : nil,
                    onMoveDown: index < devices.count - 1 ? {
                        onMove(IndexSet(integer: index), index + 2)
                    } : nil,
                    onMoveToTop: index > 0 ? {
                        onMove(IndexSet(integer: index), 0)
                    } : nil,
                    isDragging: draggingIndex == index,
                    isDropTarget: isDropTarget(for: index),
                    isDropTargetBelow: isDropTargetBelow(for: index),
                    rowHeight: rowHeight,
                    deviceCount: devices.count,
                    onDragStarted: {
                        draggingIndex = index
                    },
                    onTargetChanged: { newTarget in
                        targetIndex = newTarget
                    },
                    onDragEnded: {
                        performMove(fromIndex: index)
                    }
                )
                .zIndex(draggingIndex == index ? 100 : 0)
            }
        }
    }

    private func isDropTarget(for index: Int) -> Bool {
        guard let target = targetIndex, let dragging = draggingIndex else { return false }
        return target == index && dragging != index && dragging != index - 1
    }

    private func isDropTargetBelow(for index: Int) -> Bool {
        guard let target = targetIndex, let dragging = draggingIndex else { return false }
        return target == devices.count && index == devices.count - 1 && dragging != devices.count - 1
    }

    private func performMove(fromIndex: Int) {
        if let target = targetIndex, target != fromIndex {
            onMove(IndexSet(integer: fromIndex), target)
        }
        draggingIndex = nil
        targetIndex = nil
    }
}

// Row wrapper that handles the drag gesture
struct DraggableDeviceRow: View {
    @EnvironmentObject var audioManager: AudioManager
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

    @State private var isHovering = false
    @State private var lastReportedTarget: Int? = nil

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
              let stored = audioManager.priorityManager.getStoredDevice(uid: device.uid) else {
            return nil
        }
        return stored.lastSeenRelative
    }

    var isMuted: Bool {
        device.isConnected && audioManager.isDeviceMuted(device)
    }

    /// What VoiceOver reads after the name: the marks the row shows as small icons
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
        return parts.joined(separator: L10n.listSeparator)
    }

    /// The ⋯ menu, one array per group between dividers. VoiceOver gets the same list as actions.
    private var menuActionGroups: [[RowAction]] {
        var groups: [[RowAction]] = []

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
                    audioManager.priorityManager.forgetDevice(device)
                    audioManager.refreshDevices()
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
        // With automatic switching on, the top of the list is what gets used,
        // so a pick only sticks if it moves there
        if !audioManager.isCustomMode {
            onMoveToTop?()
        }
    }

    private func calculateTarget(offset: CGFloat) -> Int? {
        let rowsOffset = Int(round(offset / rowHeight))
        var newTarget = index + rowsOffset
        newTarget = max(0, min(deviceCount, newTarget))

        if newTarget == index || newTarget == index + 1 {
            return nil
        }
        return newTarget
    }

    var body: some View {
        HStack(spacing: 8) {
            // Round device icon, filled with the accent color for the device in use
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : Color.primary.opacity(0.1))
                Image(systemName: DeviceGlyph.symbol(for: device, category: category))
                    .font(.system(size: 12, weight: .medium))
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

            if isMuted {
                Image(systemName: device.type == .input ? "mic.slash.fill" : "speaker.slash.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .help(L10n.muted)
            }

            Spacer(minLength: 4)

            // Actions menu - always reserve space to prevent layout shifts
            ZStack {
                // Invisible placeholder to reserve space
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .opacity(0)

                // Actual menu (shown on hover)
                if isHovering && !isDragging {
                    Group {
                    Menu {
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(width: 28)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
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
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
        .animation(.easeInOut(duration: 0.1), value: isDropTarget)
        .animation(.easeInOut(duration: 0.1), value: isDropTargetBelow)
        .contentShape(Rectangle())
        .onTapGesture {
            select()
        }
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if !isDragging {
                        onDragStarted()
                    }
                    let newTarget = calculateTarget(offset: value.translation.height)
                    if newTarget != lastReportedTarget {
                        lastReportedTarget = newTarget
                        onTargetChanged(newTarget)
                    }
                }
                .onEnded { _ in
                    lastReportedTarget = nil
                    onDragEnded()
                }
        )
        .modifier(RowKeyboardSupport(activate: select))
        // VoiceOver reads the row as one button. The ⋯ menu shows on hover only and a drag
        // needs a pointer, so both are offered as actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.name)
        .accessibilityValue(accessibilityStatus)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
        .accessibilityActions {
            if let onMoveToTop {
                Button(L10n.moveToTop, action: onMoveToTop)
            }
            if let onMoveUp {
                Button(L10n.moveUp, action: onMoveUp)
            }
            if let onMoveDown {
                Button(L10n.moveDown, action: onMoveDown)
            }
            ForEach(menuActionGroups.flatMap { $0 }) { action in
                Button(action.title, action: action.perform)
            }
        }
    }
}

/// One entry of a row's ⋯ menu
private struct RowAction: Identifiable {
    let title: String
    let systemImage: String
    var isDestructive = false
    let perform: () -> Void

    var id: String { title }
}

/// Lets a row take keyboard focus the way a button does (with Keyboard Navigation on in
/// System Settings) and be picked with Space or Return. The key handling needs macOS 14.
private struct RowKeyboardSupport: ViewModifier {
    let activate: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .contentShape(.focusEffect, RoundedRectangle(cornerRadius: 8))
                .focusable(true, interactions: .activate)
                .onKeyPress(keys: [.space, .return]) { _ in
                    activate()
                    return .handled
                }
        } else {
            content
        }
    }
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
