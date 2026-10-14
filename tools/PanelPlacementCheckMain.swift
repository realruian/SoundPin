import Foundation
import CoreGraphics

@main struct PanelPlacementCheckMain {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let visible = CGRect(x: 0, y: 103, width: 1728, height: 981)
        let itemWindowBottom: CGFloat = 1086.5
        var checks = 0
        func check(_ name: String, item: CGRect, screen: CGRect = screen, visible: CGRect = visible,
                   itemWindowBottom: CGFloat = itemWindowBottom, panelLeft: CGFloat, top: CGFloat) {
            let itemWindow = CGRect(x: item.minX, y: itemWindowBottom, width: item.width, height: screen.maxY - itemWindowBottom)
            let layout = PanelPlacement.layout(itemFrame: item, itemWindowFrame: itemWindow,
                                               screenFrame: screen, visibleFrame: visible)
            let frame = layout.windowFrame
            precondition(frame.minX + PanelPlacement.sideInset == panelLeft, "\(name): panel left \(frame.minX + PanelPlacement.sideInset), expected \(panelLeft)")
            precondition(frame.maxY == top, "\(name): window top \(frame.maxY), expected \(top)")
            precondition(frame.width == PanelPlacement.width + PanelPlacement.sideInset * 2, "\(name): window width")
            precondition(frame.minY == min(visible.minY, top), "\(name): window reaches the usable bottom")
            checks += 1
        }
        // Measured on the Sound menu: left edges meet; near the right edge, right edges meet.
        check("Left edge meets the item", item: CGRect(x: 1286, y: 1086.5, width: 38, height: 28), panelLeft: 1286, top: 1084)
        check("Right edges meet near the screen edge", item: CGRect(x: 1431, y: 1086.5, width: 31.5, height: 28),
              panelLeft: 1155, top: 1084)
        check("Item at the very left", item: CGRect(x: -10, y: 1086.5, width: 30, height: 28), panelLeft: 0, top: 1084)
        // A display above the main one with a 30 pt menu bar; the item's window reaches below it.
        check("Display above, shorter menu bar",
              item: CGRect(x: 1381, y: 2167.5, width: 38, height: 28),
              screen: CGRect(x: -97, y: 1117, width: 1920, height: 1080),
              visible: CGRect(x: -97, y: 1117, width: 1920, height: 1050),
              itemWindowBottom: 2165, panelLeft: 1381, top: 2167)
        // Automatically hidden menu bar: the visible frame includes it; use the item's window.
        check("Hidden menu bar", item: CGRect(x: 700, y: 1089, width: 38, height: 28),
              visible: CGRect(x: 0, y: 0, width: 1728, height: 1117), itemWindowBottom: 1089, panelLeft: 700, top: 1089)
        print("Passed \(checks) panel placement cases.")
    }
}
