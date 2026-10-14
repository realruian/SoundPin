import Foundation
import CoreGraphics

/// Where the panel and its window go. Screen coordinates can be negative or offset
/// vertically on another display. Values marked "measured" come from the Sound menu
/// on this Mac (macOS 27), not from Apple documentation.
enum PanelPlacement {
    static let width: CGFloat = 308
    static let cornerRadius: CGFloat = 16
    /// Room beside the panel for the glass's own shadow. Control Center leaves 32 pt beside its
    /// module panel (measured); below, the window runs down to the usable bottom of the screen.
    static let sideInset: CGFloat = 32
    static let topInset: CGFloat = 1

    struct Layout: Equatable {
        var windowFrame: CGRect
        /// Space between the window's top (the menu bar's bottom) and the panel: 1 pt (measured on 2x displays).
        var topInset: CGFloat
    }

    /// Like the Sound menu (measured): the panel's left edge meets the left edge of the item's
    /// pressed highlight; where that would run past the screen, its right edge meets the item's right edge.
    /// - Parameters:
    ///   - itemFrame: the menu bar item in screen coordinates
    ///   - itemWindowFrame: the window holding the item, which can reach below the menu bar
    static func layout(itemFrame: CGRect, itemWindowFrame: CGRect, screenFrame: CGRect, visibleFrame: CGRect) -> Layout {
        var left = itemFrame.minX
        if left + width > visibleFrame.maxX { left = itemFrame.maxX - width }
        left = min(max(left, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - width)).rounded()
        // A shown menu bar is left out of the visible frame; an automatically hidden one is not.
        let menuBarBottom = visibleFrame.maxY < screenFrame.maxY ? visibleFrame.maxY : itemWindowFrame.minY
        let bottom = min(visibleFrame.minY, menuBarBottom)
        let frame = CGRect(x: left - sideInset, y: bottom,
                           width: width + sideInset * 2, height: menuBarBottom - bottom)
        return Layout(windowFrame: frame, topInset: topInset)
    }
}
