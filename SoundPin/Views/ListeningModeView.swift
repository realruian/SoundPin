import SwiftUI

enum ListeningModeMotion {
    // Use a retargetable system spring. The replica's extra bounce visibly
    // overshoots on this Mac; a smooth spring better matches the Sound menu.
    // Duration is perceptual, not settling time. These are not Apple's private parameters.
    static func animation(expanding: Bool) -> Animation {
        if #available(macOS 14.0, *) {
            return .smooth(duration: 0.5)
        }
        return .spring(response: 0.5, dampingFraction: 1)
    }
}

extension View {
    @ViewBuilder
    func panelGeometryGroup() -> some View {
        if #available(macOS 14.0, *) {
            geometryGroup()
        } else {
            self
        }
    }

    @ViewBuilder
    func panelWindowAnchor() -> some View {
        if #available(macOS 27.0, *) {
            backgroundStyle(.regularMaterial)
                .windowResizeAnchor(.topLeading)
        } else if #available(macOS 26.0, *) {
            backgroundStyle(.ultraThinMaterial)
                .windowResizeAnchor(.topLeading)
        } else {
            self
        }
    }
}

/// Keep the subtree mounted for interruption and accessibility state. SwiftUI
/// animates its geometry as a group; no per-frame height is written into state.
struct ListeningModeDisclosure: View {
    let isExpanded: Bool
    let state: ListeningModeState
    let reduceMotion: Bool
    let onSelect: (ListeningMode) -> Void
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ListeningModeView(state: state, onSelect: onSelect)
            .padding(.top, 5)
            .padding(.bottom, 4)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ListeningModeHeightKey.self, value: proxy.size.height)
            })
            .onPreferenceChange(ListeningModeHeightKey.self) { contentHeight = $0 }
            // Both endpoints must be concrete sizes: nil -> zero jumps the
            // interior layout while the window is still animating its height.
            .frame(height: isExpanded ? contentHeight : 0, alignment: .top)
            .clipped()
            .panelGeometryGroup()
            .opacity(isExpanded ? 1 : 0)
            .animation(reduceMotion ? nil : ListeningModeMotion.animation(expanding: isExpanded), value: isExpanded)
            .allowsHitTesting(isExpanded)
            .disabled(!isExpanded)
            .accessibilityHidden(!isExpanded)
    }
}

private struct ListeningModeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Matches the Sound menu: gray heading, monochrome glyphs, checkmark at the left.
struct ListeningModeView: View {
    let state: ListeningModeState
    let onSelect: (ListeningMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Text(L10n.listeningMode)
                .font(.callout.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 13.5)
                .padding(.bottom, 3.5)
                .accessibilityAddTraits(.isHeader)
            ForEach(state.supported) { mode in
                ListeningModeRow(mode: mode, selected: state.current == mode) { onSelect(mode) }
            }
            .padding(.horizontal, 6)
            Divider().padding(.horizontal, 5).padding(.top, 5.5)
        }
        .background(Color.listeningModeBackground)
    }
}

private struct ListeningModeRow: View {
    let mode: ListeningMode
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(selected ? 1 : 0)
                    .frame(width: 26)
                ListeningModeGlyph(mode: mode)
                    .foregroundColor(.listeningModeIcon)
                    .frame(width: 18, height: 18)
                    // The asymmetric sparkles extend beyond the centered head.
                    // Align the person's head with the other two mode symbols.
                    .offset(x: mode == .adaptive ? 1 : 0)
                Text(mode.title).font(.body)
                Spacer(minLength: 0)
            }
            .foregroundColor(.listeningModeLabel)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.primary.opacity(0.07) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The Sound menu uses symbols from the OS's private symbol catalog. Load them
/// through AppKit's bundle-image API, with a local vector fallback on OS versions
/// where the catalog or symbol is absent. No OS assets are copied into the app.
struct ListeningModeGlyph: View {
    let mode: ListeningMode

    private static let systemSymbols: [ListeningMode: NSImage] = {
        let catalog = Bundle(path: "/System/Library/PrivateFrameworks/SFSymbols.framework/Resources/CoreGlyphsPrivate.bundle")
        let names: [(ListeningMode, String)] = [
            (.transparency, "person.open.fill"),
            (.adaptive, "person.and.sparkles.fill"),
            (.noiseCancellation, "person.closed.fill"),
        ]
        return Dictionary(uniqueKeysWithValues: names.compactMap { mode, name in
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
                    ?? catalog?.image(forResource: name) else { return nil }
            return (mode, image.withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? image)
        })
    }()

    var body: some View {
        Group {
            if let image = Self.systemSymbols[mode] {
                Image(nsImage: image)
                    .renderingMode(.template)
            } else {
                ListeningModeFallbackGlyph(mode: mode)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Remains available if a later macOS release moves or removes the private catalog.
private struct ListeningModeFallbackGlyph: View {
    let mode: ListeningMode

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 18
            context.scaleBy(x: scale, y: scale)
            let ink = GraphicsContext.Shading.foreground
            let head = CGPoint(x: 8.5, y: 6.8)
            // Draw the halo first: the shoulders naturally cover its lower edge.
            switch mode {
            case .transparency:
                for i in 0..<12 {
                    let angle = Double(i) * .pi / 6 - .pi / 2
                    let x = head.x + cos(angle) * 4.8, y = head.y + sin(angle) * 4.8
                    context.fill(Path(ellipseIn: CGRect(x: x - 0.55, y: y - 0.55, width: 1.1, height: 1.1)), with: ink)
                }
            case .noiseCancellation:
                context.stroke(Path(ellipseIn: CGRect(x: 3.9, y: 2.2, width: 9.2, height: 9.2)), with: ink, lineWidth: 1)
            case .adaptive:
                func sparkle(x: CGFloat, y: CGFloat, radius: CGFloat) -> Path {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y - radius))
                    p.addQuadCurve(to: CGPoint(x: x + radius * 0.8, y: y), control: CGPoint(x: x + radius * 0.2, y: y - radius * 0.2))
                    p.addQuadCurve(to: CGPoint(x: x, y: y + radius), control: CGPoint(x: x + radius * 0.2, y: y + radius * 0.2))
                    p.addQuadCurve(to: CGPoint(x: x - radius * 0.8, y: y), control: CGPoint(x: x - radius * 0.2, y: y + radius * 0.2))
                    p.addQuadCurve(to: CGPoint(x: x, y: y - radius), control: CGPoint(x: x - radius * 0.2, y: y - radius * 0.2))
                    return p
                }
                context.fill(sparkle(x: 14.5, y: 4.4, radius: 3.3), with: ink)
                context.fill(sparkle(x: 11.4, y: 1.6, radius: 1.35), with: ink)
            }
            context.fill(Path(ellipseIn: CGRect(x: head.x - 2.7, y: head.y - 2.7, width: 5.4, height: 5.4)), with: ink)
            var shoulders = Path()
            shoulders.move(to: CGPoint(x: 3.5, y: 16.5))
            shoulders.addQuadCurve(to: CGPoint(x: 2.7, y: 15.7), control: CGPoint(x: 2.7, y: 16.5))
            shoulders.addCurve(to: CGPoint(x: 8.5, y: 11.3), control1: CGPoint(x: 2.7, y: 13.2), control2: CGPoint(x: 5.2, y: 11.3))
            shoulders.addCurve(to: CGPoint(x: 14.3, y: 15.7), control1: CGPoint(x: 11.8, y: 11.3), control2: CGPoint(x: 14.3, y: 13.2))
            shoulders.addQuadCurve(to: CGPoint(x: 13.5, y: 16.5), control: CGPoint(x: 14.3, y: 16.5))
            shoulders.closeSubpath()
            context.fill(shoulders, with: ink)
        }
        .accessibilityHidden(true)
    }
}
