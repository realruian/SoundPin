import ApplicationServices
import Foundation

// Prints what VoiceOver finds in another process's window, read through the same
// accessibility API, then runs one action on a row and checks the result.
// The terminal running it needs Accessibility permission (System Settings > Privacy & Security).
//
//   voiceoverdump <pid> [<row label> <action> <action that must be gone afterwards>]
func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func text(_ value: AnyObject?) -> String {
    if let string = value as? String { return string }
    if let attributed = value as? NSAttributedString { return attributed.string }
    if let number = value as? NSNumber { return number.stringValue }
    return ""
}

func rawActions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success, let list = names as? [String] else { return [] }
    return list
}

// A custom action's name arrives as "Name:Move Up\nTarget:0x0\nSelector:(null)"
func readable(_ action: String) -> String {
    action.hasPrefix("Name:")
        ? String(action.dropFirst(5).prefix { $0 != "\n" })
        : action.replacingOccurrences(of: "AX", with: "")
}

func actions(_ element: AXUIElement) -> [String] {
    rawActions(element).map(readable).filter { !["ShowMenu", "ScrollToVisible"].contains($0) }
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (attribute(element, "AXChildren") as? [AXUIElement]) ?? []
}

func printTree(_ element: AXUIElement, depth: Int) {
    let role = text(attribute(element, "AXRole")).replacingOccurrences(of: "AX", with: "")
    let label = text(attribute(element, "AXDescription"))
    let title = text(attribute(element, "AXTitle"))
    let value = text(attribute(element, "AXValueDescription")).isEmpty
        ? text(attribute(element, "AXValue"))
        : text(attribute(element, "AXValueDescription"))
    let help = text(attribute(element, "AXHelp"))
    let shown = role != "Window" && (!label.isEmpty || !title.isEmpty || ["Button", "Slider", "MenuButton", "Heading"].contains(role))
    if shown {
        let pad = String(repeating: "  ", count: min(depth, 4))
        var line = pad + role
        if !label.isEmpty { line += " \"\(label)\"" }
        if !title.isEmpty && title != label { line += " \"\(title)\"" }
        if !value.isEmpty { line += ", \(value)" }
        if text(attribute(element, "AXSelected")) == "1" { line += ", selected" }
        if text(attribute(element, "AXEnabled")) == "0" { line += ", dimmed" }
        if !help.isEmpty { line += "  (help: \(help))" }
        print(line)
        let offered = actions(element)
        if !offered.isEmpty { print(pad + "    actions: " + offered.joined(separator: " | ")) }
    }
    for child in children(element) {
        printTree(child, depth: depth + (shown ? 1 : 0))
    }
}

func find(_ element: AXUIElement, label: String) -> AXUIElement? {
    if text(attribute(element, "AXDescription")) == label && text(attribute(element, "AXRole")) != "AXWindow" { return element }
    for child in children(element) {
        if let found = find(child, label: label) { return found }
    }
    return nil
}

let arguments = CommandLine.arguments
guard arguments.count >= 2, let pid = Int32(arguments[1]) else {
    print("usage: voiceoverdump <pid> [<row label> <action> <action that must be gone afterwards>]")
    exit(2)
}
guard AXIsProcessTrusted() else {
    print("This terminal has no Accessibility permission, so the panel cannot be read.")
    print("Allow it under System Settings > Privacy & Security > Accessibility and run again.")
    exit(1)
}

let app = AXUIElementCreateApplication(pid)
var windows = (attribute(app, "AXWindows") as? [AXUIElement]) ?? []
if windows.isEmpty {
    windows = children(app).filter { text(attribute($0, "AXRole")) == "AXWindow" }
}
guard let window = windows.first else {
    print("The panel's window was not found.")
    exit(1)
}
printTree(window, depth: 0)

var failures = 0
func check(_ what: String, _ ok: Bool) {
    print((ok ? "ok   " : "FAIL ") + what)
    if !ok { failures += 1 }
}

print("")
check("device rows are buttons", find(window, label: "AirPods Pro").map { text(attribute($0, "AXRole")) == "AXButton" } ?? false)
check("the device in use reads as selected", find(window, label: "AirPods Pro").map { text(attribute($0, "AXSelected")) == "1" } ?? false)
check("a row's state is read after its name", find(window, label: "MacBook Pro Speakers").map { !text(attribute($0, "AXValue")).isEmpty } ?? false)
func slider(_ element: AXUIElement) -> AXUIElement? {
    if text(attribute(element, "AXRole")) == "AXSlider" { return element }
    for child in children(element) {
        if let found = slider(child) { return found }
    }
    return nil
}
check("the slider has a name and reads a percentage", slider(window).map {
    !text(attribute($0, "AXDescription")).isEmpty && text(attribute($0, "AXValueDescription")).hasSuffix("%")
} ?? false)

if arguments.count >= 5 {
    let (label, action, goneAfterwards) = (arguments[2], arguments[3], arguments[4])
    if let row = find(window, label: label), let raw = rawActions(row).first(where: { readable($0) == action }) {
        let result = AXUIElementPerformAction(row, raw as CFString)
        usleep(500_000)
        check("\"\(action)\" on \"\(label)\" runs", result == .success)
        let after = find(window, label: label).map(actions) ?? []
        check("afterwards \"\(goneAfterwards)\" is no longer offered for it", !after.contains(goneAfterwards))
    } else {
        check("\"\(action)\" is offered on \"\(label)\"", false)
    }
}

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
