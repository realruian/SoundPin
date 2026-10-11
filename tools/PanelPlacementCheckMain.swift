import Foundation
import CoreGraphics

@main struct PanelPlacementCheckMain {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 40, width: 1440, height: 835)
        var checks = 0
        func check(_ name: String, _ panel: CGRect, screen: CGRect = screen,
                   visible: CGRect = visible, expected: CGPoint) {
            let result = PanelPlacement.origin(for: panel, screen: screen, visibleFrame: visible)
            precondition(result == expected, "\(name): \(result), expected \(expected)")
            let corrected = CGRect(origin: result, size: panel.size)
            precondition(PanelPlacement.origin(for: corrected, screen: screen, visibleFrame: visible) == result,
                         "\(name): a second correction must not move the panel again")
            checks += 1
        }
        check("Only a sliver remains at the right edge",
              CGRect(x: 1420, y: 450, width: 308, height: 400), expected: CGPoint(x: 1132, y: 450))
        check("Completely outside the right edge",
              CGRect(x: 1600, y: 450, width: 308, height: 400), expected: CGPoint(x: 1132, y: 450))
        check("Left edge", CGRect(x: -290, y: 450, width: 308, height: 400), expected: CGPoint(x: 0, y: 450))
        check("Keep the system anchor during menu resizing",
              CGRect(x: 700, y: 471.5, width: 308, height: 400), expected: CGPoint(x: 700, y: 471.5))
        check("Do not move an already valid panel",
              CGRect(x: 700, y: 450, width: 308, height: 400), expected: CGPoint(x: 700, y: 450))
        check("Above screen", CGRect(x: 700, y: 800, width: 308, height: 400), expected: CGPoint(x: 700, y: 475))
        check("Below dock", CGRect(x: 700, y: -100, width: 308, height: 400), expected: CGPoint(x: 700, y: 40))
        check("Left and vertically offset display",
              CGRect(x: -20, y: 600, width: 308, height: 400),
              screen: CGRect(x: -1920, y: 200, width: 1920, height: 1080),
              visible: CGRect(x: -1920, y: 200, width: 1920, height: 1055),
              expected: CGPoint(x: -308, y: 600))
        check("Right dock", CGRect(x: 1250, y: 450, width: 308, height: 400),
              visible: CGRect(x: 0, y: 0, width: 1370, height: 875), expected: CGPoint(x: 1062, y: 450))
        check("Hidden menu bar", CGRect(x: 1420, y: 450, width: 308, height: 400),
              visible: screen, expected: CGPoint(x: 1132, y: 450))
        check("Oversized panel keeps title reachable",
              CGRect(x: 1420, y: -100, width: 308, height: 1000), expected: CGPoint(x: 1132, y: -125))
        // Simulate the system applying the same top anchor on every expansion
        // frame. A gap correction here used to alternate the panel by 3 pt.
        let systemTop: CGFloat = visible.maxY - 3.5
        for height in stride(from: CGFloat(330), through: 550, by: 0.5) {
            let panel = CGRect(x: 700, y: systemTop - height, width: 308, height: height)
            let origin = PanelPlacement.origin(for: panel, screen: screen, visibleFrame: visible)
            precondition(origin == panel.origin, "Animated resize must preserve the system anchor")
        }
        print("Passed \(checks) panel placement cases, including stability after repeated correction.")
    }
}
