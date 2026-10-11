import Foundation
import CoreGraphics

/// Screen coordinates can be negative or offset vertically on another display.
/// Keep the system's horizontal anchor unless it would leave the usable screen.
enum PanelPlacement {
    static func origin(for panel: CGRect, screen: CGRect, visibleFrame: CGRect) -> CGPoint {
        // MenuBarExtra owns the top anchor, including its menu-bar gap. Moving an
        // otherwise valid panel closer after each animated resize fights that
        // anchor and produces a visible 3 pt oscillation. Only correct overflow.
        var y = panel.minY

        let x = min(max(panel.minX, visibleFrame.minX),
                    max(visibleFrame.minX, visibleFrame.maxX - panel.width))
        // If a panel is taller than the usable screen, keep its top accessible.
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - panel.height)
        return CGPoint(x: x, y: y)
    }
}
