import SwiftUI
import AppKit

@MainActor final class MotionDriver: ObservableObject {
    @Published var expanded = false
    @Published var reduced = false
    var height: CGFloat = 0
    weak var window: NSWindow?
    var started = false
    var timer: Timer?
}
private struct WindowProbe: NSViewRepresentable {
    let driver: MotionDriver
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.driver = driver
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ view: Probe, context: Context) {}
    final class Probe: NSView {
        weak var driver: MotionDriver?
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            driver?.window = window
            if let window { onWindow?(window) }
        }
    }
}
private struct ProbeHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct ContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct MotionProbe: View {
    @ObservedObject var driver: MotionDriver
    @State private var listHeight: CGFloat = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AirPods Pro 3")
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(driver.expanded ? 90 : 0))
                    .animation(driver.reduced ? nil : ListeningModeMotion.animation(expanding: driver.expanded), value: driver.expanded)
            }.padding(.horizontal, 14).frame(height: 32)
            // Geometry supplies the target size; SwiftUI animates the window.
            // Use the same ScrollView sizing and geometry group as MenuBarView.
            ScrollView {
                VStack(spacing: 0) {
                ListeningModeDisclosure(isExpanded: driver.expanded,
                                        state: ListeningModeState(currentRawValue: 2, supportedMask: 7), reduceMotion: driver.reduced) { _ in
                    fatalError("Motion check must never select a listening mode")
                }
                Text("Other devices").frame(height: 32)
                }
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeight.self, value: proxy.size.height)
                })
            }
            .frame(height: min(listHeight, 460))
            .panelGeometryGroup()
            .onPreferenceChange(ContentHeight.self) { height in
                guard abs(listHeight - height) > 0.1 else { return }
                let animation = listHeight == 0 || driver.reduced ? nil
                    : ListeningModeMotion.animation(expanding: height > listHeight)
                withAnimation(animation) { listHeight = height }
            }
            Text("Sound Settings…").frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).frame(height: 26)
        }
        .frame(width: 308)
        .panelGeometryGroup()
        .fixedSize(horizontal: false, vertical: true)
        .panelWindowAnchor()
        .background(Color(nsColor: .windowBackgroundColor))
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ProbeHeight.self, value: proxy.size.height)
        })
        .onPreferenceChange(ProbeHeight.self) { driver.height = $0 }
    }
}

// Window animation requires the SwiftUI app lifecycle. An NSHostingView in a
// manually resized NSWindow only exposes target geometry, not this animation.
@main struct MotionCheckMain: App {
    @StateObject private var driver = MotionDriver()
    var body: some Scene {
        MenuBarExtra("SoundPin Motion Check", systemImage: "rectangle.expand.vertical") {
            MotionProbe(driver: driver)
                .background(WindowProbe(driver: driver, onWindow: runCheck))
        }
        .menuBarExtraStyle(.window)
    }

    @MainActor private func runCheck(_ window: NSWindow) {
        guard !driver.started else { return }
        driver.started = true
        FileHandle.standardError.write(Data("Motion probe attached\n".utf8))
        var initial: CGFloat?
        var top: CGFloat = 0
        var left: CGFloat = 0
        var start: Date?
        var events = [(0.15, true, false), (1.1, false, false), (1.2, true, false),
                      (2.1, false, false), (3.0, true, true), (3.4, false, true)]
        var rows: [[String: Double]] = []
        var reported = false
        // Menu tracking uses a nested run loop. A common-mode timer keeps the
        // probe running while this menu is open without blocking the UI thread.
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { timer in
            MainActor.assumeIsolated {
                if !reported {
                    reported = true
                    FileHandle.standardError.write(Data("Timer active; windows: \(NSApplication.shared.windows.map { ($0.frame, $0.isVisible) })\n".utf8))
                }
                // MenuBarExtra first hosts content in a hidden measurement
                // window. Sample the displayed panel, not that initial host.
                guard let window = NSApplication.shared.windows.first(where: {
                    $0.isVisible && abs($0.frame.width - 308) < 1 && $0.frame.height > 50
                }) else { return }
                guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]])?.first,
                      let bounds = info[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return }
                guard let began = start else {
                    initial = rect.height
                    top = rect.minY
                    left = rect.minX
                    start = Date().addingTimeInterval(0.3)
                    return
                }
                let elapsed = Date().timeIntervalSince(began)
                guard elapsed >= 0 else { return }
                if let event = events.first, elapsed >= event.0 {
                    driver.reduced = event.2
                    withAnimation(event.2 ? nil : ListeningModeMotion.animation(expanding: event.1)) {
                        driver.expanded = event.1
                    }
                    events.removeFirst()
                }
                rows.append(["time": elapsed, "height": rect.height,
                             "top": rect.minY, "left": rect.minX,
                             "target": driver.height, "expanded": driver.expanded ? 1 : 0,
                             "reduced": driver.reduced ? 1 : 0])
                if elapsed >= 3.8 {
                    timer.invalidate()
                    finish(rows: rows, window: window, initial: initial!, top: top, left: left)
                }
            }
        }
        driver.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @MainActor private func finish(rows: [[String: Double]], window: NSWindow,
                                   initial: CGFloat, top: CGFloat, left: CGFloat) {
        let data = try! JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted)
        try! data.write(to: URL(fileURLWithPath: ".build/listening-mode-motion-check/motion-frames.json"))
        let settled = rows.first { $0["time"]! > 1.0 }!["height"]!
        let mids = rows.filter { (0.15...0.65).contains($0["time"]!) && $0["height"]! > initial + 1 && $0["height"]! < settled - 1 }
        let reverse = rows.filter { (1.12...1.5).contains($0["time"]!) && $0["height"]! > initial + 1 && $0["height"]! < settled - 1 }
        let reduced = rows.filter { (3.08...3.3).contains($0["time"]!) }
        let stable = rows.allSatisfy { abs($0["top"]! - top) <= 1 && abs($0["left"]! - left) <= 1 }
        print("collapsed=\(initial) expanded=\(settled) final=\(window.frame.height)")
        print("intermediate window frames=\(mids.count), reversal frames=\(reverse.count), anchor stable=\(stable)")
        print("reduced-motion window heights=\(Set(reduced.map { $0["height"]! }).sorted())")
        guard settled > initial + 80, mids.count >= 3, !reverse.isEmpty,
              abs(window.frame.height - initial) < 1, stable,
              reduced.allSatisfy({ abs($0["height"]! - settled) <= 1 }) else {
            print("FAIL: actual window animation requires inspection")
            exit(1)
        }
        print("PASS: real MenuBarExtra expansion, reversal, collapse, fixed anchor and reduced motion. No audio service created.")
        exit(0)
    }
}
