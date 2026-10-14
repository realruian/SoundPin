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
func rect(_ element: AXUIElement) -> CGRect? {
    guard let p = attr(element, "AXPosition"), let s = attr(element, "AXSize") else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}
func click(_ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(50_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func command(_ args: [String], wait: Bool = true) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: args[0]); process.arguments = Array(args.dropFirst())
    try! process.run()
    if wait { process.waitUntilExit() }
    return process
}
let args = CommandLine.arguments
let pid = Int32(args[1])!, output = args[2], reduced = args.contains("--reduce-motion")
let recording = args.contains("--record")
guard AXIsProcessTrusted() else { fatalError("Accessibility permission required; no settings were changed") }
try! FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let app = AXUIElementCreateApplication(pid)
var checks: [[String: Any]] = []
func check(_ ok: Bool, _ name: String) {
    print("\(ok ? "ok" : "FAIL"): \(name)"); fflush(stdout)
    checks.append(["name":name,"passed":ok])
}
func window() -> AXUIElement? {
    guard let visible = bounds()?.0 else { return nil }
    func matches(_ element: AXUIElement) -> Bool {
        rect(element).map { abs($0.width - visible.width) < 1 && $0.height > 100 } ?? false
    }
    return (attr(app, "AXWindows") as? [AXUIElement])?.first(where: matches)
        ?? find(app) { string(attr($0,"AXRole")) == "AXWindow" && matches($0) }
}
func row(_ name: String) -> AXUIElement? { window().flatMap { find($0) { string(attr($0, "AXDescription")) == name } } }
func mode(_ value: Int) -> AXUIElement? { window().flatMap { find($0) { string(attr($0, "AXIdentifier")) == "listening-mode-\(value)" } } }
func perform(_ element: AXUIElement?, _ name: String) -> Bool {
    guard let element, let action = actions(element).first(where: { $0 == name || $0.hasPrefix("Name:\(name)\n") }) else { return false }
    return AXUIElementPerformAction(element, action as CFString) == .success
}
func bounds() -> (CGRect, CGWindowID)? {
    let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]] ?? []
    for item in list where (item[kCGWindowOwnerPID as String] as? Int32) == pid {
        guard let dictionary = item[kCGWindowBounds as String] as? [String: Any],
              let r = CGRect(dictionaryRepresentation: dictionary as CFDictionary), abs(r.width - 308) < 1, r.height > 100,
              let id = item[kCGWindowNumber as String] as? UInt32 else { continue }
        return (r, id)
    }
    return nil
}
var samples: [[String: Any]] = []
func sample(_ phase: String, duration: Double) {
    let start = Date()
    while Date().timeIntervalSince(start) < duration {
        let windows = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String:Any]] ?? []).filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
        let frames = windows.compactMap { item -> CGRect? in
            guard let d=item[kCGWindowBounds as String] as? [String:Any] else{return nil};return CGRect(dictionaryRepresentation:d as CFDictionary)
        }
        if let r = frames.first(where:{abs($0.width-308)<1 && $0.height>100}) {
            let shadow = windows.compactMap { item -> CGRect? in
                guard let d=item[kCGWindowBounds as String] as? [String:Any], let frame=CGRect(dictionaryRepresentation:d as CFDictionary),abs(frame.width-372)<1 else{return nil};return frame
            }.first
            let aligned = shadow.map { abs($0.minX-(r.minX-32))<1 && abs($0.minY-(r.minY-32))<1 && abs($0.height-(r.height+64))<1 } ?? false
            samples.append(["shadowHeight":shadow?.height ?? -1,"shadowTop":shadow?.minY ?? -1,"shadowAligned":aligned,"phase":phase,"time":Date().timeIntervalSince(start),"top":Double(r.minY),"left":Double(r.minX),"height":Double(r.height)])
        }
        usleep(8_000)
    }
}
func capture(_ name: String) {
    guard let (_, id) = bounds() else { return }
    _ = command(["/usr/sbin/screencapture", "-x", "-l", String(id), output + "/" + name + ".png"])
}
// Resolve the test process's own menu item; no saved screen coordinates.
usleep(700_000)
let activated = NSRunningApplication(processIdentifier: pid)?.activate(options: []) ?? false
print("Test application activation: \(activated)"); fflush(stdout)
usleep(700_000)
var menu: AXUIElement?
for _ in 0..<50 {
    let extras = attr(app, "AXExtrasMenuBar") as! AXUIElement?
    menu = extras.flatMap { find($0) { string(attr($0,"AXRole")) == "AXMenuBarItem" } }
    if menu != nil { break }; usleep(100_000)
}
guard let menu, let menuRect = rect(menu) else { fatalError("Test menu item not found") }
func clickMenu() {
    guard let current = rect(menu) else { fatalError("Test menu item disappeared") }
    print("Click test menu at \(current)"); fflush(stdout)
    click(CGPoint(x: current.midX, y: current.midY))
}
print("Test menu: \(menuRect), title: \(string(attr(menu, "AXTitle")))"); fflush(stdout)
clickMenu()
for _ in 0..<30 { if bounds() != nil && window() != nil { break }; usleep(100_000) }
guard let (preflight, _) = bounds(), window() != nil else {
    let owned = (CGWindowListCopyWindowInfo(.optionAll, 0) as? [[String: Any]] ?? []).filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
    print("Own window diagnostics: \(owned)")
    print("AX windows: \((attr(app, "AXWindows") as? [AXUIElement] ?? []).map { String(describing: rect($0)) })"); fflush(stdout)
    exit(2)
}
check(mode(3) == nil, "collapsed listening modes are absent from accessibility tree")
// Recording is optional: screen-capture startup can steal focus from menu tracking.
let captureLeft = max(0, Int(preflight.minX - 80))
let captureWidth = Int(NSScreen.main?.frame.maxX ?? 1728) - captureLeft
let region = "\(captureLeft),\(Int(preflight.minY - 10)),\(captureWidth),\(Int(preflight.height + 210))"
var video: Process?
if recording {
    clickMenu(); usleep(200_000)
    video = command(["/usr/sbin/screencapture", "-x", "-v", "-V", "7", "-R", region, output + "/motion.mov"], wait: false)
    usleep(2_000_000)
    clickMenu()
    for _ in 0..<30 { if row("AirPods Pro") != nil { break }; usleep(100_000) }
}
guard let podsRow = row("AirPods Pro"), let (initial, _) = bounds() else {
    print("Reopen diagnostics: bounds=\(String(describing: bounds())), AX windows=\((attr(app, "AXWindows") as? [AXUIElement] ?? []).map { String(describing: rect($0)) })")
    video?.waitUntilExit(); exit(2)
}
print("AirPods actions: \(actions(podsRow))"); fflush(stdout)

check(perform(row("AirPods Pro"), "Show Listening Modes"), "VoiceOver expand action dispatches")
sample("expand", duration: 0.8)
check(mode(3) != nil && mode(4) != nil && mode(2) != nil, "expanded production panel exposes all supported modes")
check(mode(3).map { actions($0).contains("AXPress") } ?? false, "mode button exposes its default VoiceOver action")

guard let expandedHeight = bounds()?.0.height else {
    print("Menu closed during expansion diagnostics"); video?.waitUntilExit(); exit(2)
}
check(perform(row("AirPods Pro"), "Hide Listening Modes"), "VoiceOver collapse action dispatches")
sample("reverse-collapse", duration: 0.10)
check(perform(row("AirPods Pro"), "Show Listening Modes"), "rapid reverse expand action dispatches")
sample("reverse-expand", duration: 0.8)
check(bounds().map { abs($0.0.height - expandedHeight) < 1 } ?? false, "rapid reversal settles at expanded height")
check(perform(row("AirPods Pro"), "Hide Listening Modes"), "collapse dispatches after reversal")
sample("collapse", duration: 0.8)
check((bounds().map { abs($0.0.height - initial.height) < 1 } ?? false) && mode(3) == nil, "collapse restores window and removes mode controls")
let stable = samples.allSatisfy { abs(($0["top"] as! Double) - initial.minY) <= 1 && abs(($0["left"] as! Double) - initial.minX) <= 1 }
check(stable, "actual MenuBarExtra keeps its top and left anchors")
let mids = samples.filter { $0["phase"] as? String == "expand" && ($0["height"] as! Double) > initial.height + 1 && ($0["height"] as! Double) < expandedHeight - 1 }
check(reduced ? mids.isEmpty : mids.count >= 3, reduced ? "reduced motion skips intermediate window heights" : "expansion contains intermediate window frames")
video?.waitUntilExit()
if let video { check(video.terminationStatus == 0 && FileManager.default.fileExists(atPath: output + "/motion.mov"), "test panel recording saved") }
// Focused window-chrome regression: real MenuBarExtra plus its noninteractive shadow.
if args.contains("--chrome-only") {
    check(samples.allSatisfy{$0["shadowAligned"] as? Bool == true}, "shadow follows actual window throughout expansion and reversal")
    func shadowCount()->Int {
 (CGWindowListCopyWindowInfo(.optionOnScreenOnly,0) as? [[String:Any]] ?? []).filter { item in
  guard item[kCGWindowOwnerPID as String] as? Int32 == pid, let d=item[kCGWindowBounds as String] as? [String:Any],let r=CGRect(dictionaryRepresentation:d as CFDictionary) else{return false};return abs(r.width-372)<1
 }.count
}
    for cycle in 1...3 {
 CGEvent(keyboardEventSource:nil,virtualKey:53,keyDown:true)?.post(tap:.cghidEventTap)
 CGEvent(keyboardEventSource:nil,virtualKey:53,keyDown:false)?.post(tap:.cghidEventTap)
 usleep(350_000)
 check(bounds()==nil && shadowCount()==0, "Escape dismisses menu and shadow, cycle \(cycle)")
 clickMenu();usleep(500_000)
 check(bounds() != nil && shadowCount()==1,"reopen creates exactly one shadow, cycle \(cycle)")
}
    let payload: [String: Any] = ["checks":checks,"samples":samples,"reduced":reduced,"initialHeight":initial.height,"expandedHeight":expandedHeight]
    try! JSONSerialization.data(withJSONObject:payload,options:.prettyPrinted).write(to:URL(fileURLWithPath:output+"/results.json"))
    clickMenu()
    exit(checks.allSatisfy{$0["passed"] as? Bool == true} ? 0:1)
}
// Reopen after recording before checking production row actions.
_ = AXUIElementSetAttributeValue(app, "AXFrontmost" as CFString, kCFBooleanTrue)
usleep(500_000)
if bounds() == nil { clickMenu(); usleep(600_000) }
check(window() != nil, "test menu is visible before row action checks")
check(perform(row("Studio Display Speakers"), "Move Up"), "VoiceOver reorder action dispatches")
usleep(200_000)
check(row("Studio Display Speakers").map { !actions($0).contains { $0.hasPrefix("Name:Move Up\n") } } ?? false,
      "VoiceOver reorder moves the device to the top")
check(perform(row("Studio Display Speakers"), "Move Down"), "VoiceOver reverse reorder dispatches")
usleep(200_000)
check(row("Studio Display Speakers").map { actions($0).contains { $0.hasPrefix("Name:Move Up\n") } } ?? false,
      "VoiceOver reverse reorder restores its order")
// A simulated write waits and times out. No real service is linked in the app.
_ = perform(row("AirPods Pro"), "Show Listening Modes"); usleep(600_000)
check(perform(mode(3), "AXPress"), "mode button dispatches a simulated request")
usleep(250_000)
check(mode(3).map { (attr($0,"AXEnabled") as? NSNumber)?.boolValue == false } ?? false,"pending mode buttons are disabled")
check(mode(3).map { string(attr($0,"AXValue")) == "Switching…" } ?? false,"pending mode exposes progress to VoiceOver")

usleep(3_700_000)
check(row("Retry") != nil || window().flatMap { find($0) { string(attr($0,"AXTitle")) == "Retry" } } != nil,"timeout exposes a retry control")
capture("timeout")
let payload: [String: Any] = ["checks":checks,"samples":samples,"reduced":reduced,"initialHeight":initial.height,"expandedHeight":expandedHeight,"captureLeft":captureLeft,"captureTop":Int(preflight.minY - 10)]
try! JSONSerialization.data(withJSONObject: payload, options:.prettyPrinted).write(to:URL(fileURLWithPath:output + "/results.json"))
clickMenu()
exit(checks.allSatisfy { $0["passed"] as? Bool == true } ? 0 : 1)
