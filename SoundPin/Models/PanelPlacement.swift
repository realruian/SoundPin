import Foundation
import CoreGraphics

/// Screen coordinates can be negative or offset vertically on another display.
/// Keep the system's horizontal anchor unless it would leave the usable screen.
enum PanelPlacement {
    static func origin(for panel: CGRect, screen: CGRect, visibleFrame: CGRect) -> CGPoint {
        let gap: CGFloat = 0.5
        var y = panel.minY
        let distance = visibleFrame.maxY - panel.maxY
        if visibleFrame.maxY < screen.maxY, distance > gap + 0.25, distance < 12 {
            y = visibleFrame.maxY - gap - panel.height
        }

        let x = min(max(panel.minX, visibleFrame.minX),
                    max(visibleFrame.minX, visibleFrame.maxX - panel.width))
        // If a panel is taller than the usable screen, keep its top accessible.
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - panel.height)
        return CGPoint(x: x, y: y)
    }
}
