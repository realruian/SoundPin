import AppKit
import ApplicationServices

func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func string(_ value: AnyObject?) -> String { (value as? String) ?? "" }
func children(_ element: AXUIElement) -> [AXUIElement] { attr(element, "AXChildren") as? [AXUIElement] ?? [] }
func find(_ element: AXUIElement, _ predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    if predicate(element) { return element }
    for child in children(element) { if let match = find(child, predicate) { return match } }
    return nil
}
func actions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyActionNames(element, &names)
    return names as? [String] ?? []
}

let pid = Int32(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
var failed = 0
func check(_ condition: Bool, _ name: String) {
    print("\(condition ? "ok" : "FAIL"): \(name)")
    if !condition { failed += 1 }
}
func mode() -> AXUIElement? { find(app) { string(attr($0, "AXIdentifier")) == "listening-mode-3" } }
func press(_ element: AXUIElement?) -> Bool {
    guard let element else { return false }
    return AXUIElementPerformAction(element, "AXPress" as CFString) == .success
}
check(mode().map { actions($0).contains("AXPress") } ?? false, "mode has a default accessibility action")
check(press(mode()), "VoiceOver can activate a simulated mode request")
usleep(100_000)
check(mode().map { (attr($0, "AXEnabled") as? NSNumber)?.boolValue == false } ?? false, "pending mode is disabled")
check(mode().map { string(attr($0, "AXValue")) == "Switching…" } ?? false, "pending mode exposes progress")
usleep(3_700_000)
check(mode().map { (attr($0, "AXEnabled") as? NSNumber)?.boolValue == true } ?? false, "timeout enables mode controls")
let retry = find(app) { string(attr($0, "AXTitle")) == "Retry" || string(attr($0, "AXDescription")) == "Retry" }
check(retry != nil, "timeout exposes Retry")
check(press(retry), "VoiceOver can retry")
usleep(100_000)
check(mode().map { string(attr($0, "AXValue")) == "Switching…" } ?? false, "retry starts a new request")
exit(failed == 0 ? 0 : 1)
