import Foundation
import CoreAudio

@main struct ListeningModeCheckMain {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { print("FAIL: \(name)"); exit(1) }
            count += 1
            print("ok: \(name)")
        }
        let all = ListeningModeState(currentRawValue: 2, supportedMask: 7)
        check(all.supported == [.transparency, .adaptive, .noiseCancellation], "system menu order")
        check(all.current == .noiseCancellation, "current noise cancellation")
        check(ListeningModeState(currentRawValue: 4, supportedMask: 3).supported == [.transparency, .noiseCancellation], "no adaptive row without support")
        check(ListeningModeState(currentRawValue: 4, supportedMask: 3).current == nil, "unsupported current value is not shown as selected")
        check(ListeningModeState(currentRawValue: 1, supportedMask: 7).current == nil, "off does not masquerade as a tested mode")
        check(ListeningModeState(currentRawValue: 99, supportedMask: 7).current == nil, "future current value stays unknown")
        check(ListeningModeState(currentRawValue: 2, supportedMask: 0).supported.isEmpty, "empty support mask")
        check(ListeningModeState(currentRawValue: 3, supportedMask: 0x80000002).supported == [.transparency], "unknown support bits ignored")
        let service = ListeningModeService()
        let offline = AudioDevice.disconnected(uid: "check", name: "AirPods Pro 3", type: .output)
        check(service.state(for: offline) == nil && !service.request(.transparency, for: offline), "disconnected device rejected before write")
        let input = AudioDevice(id: 0, uid: "check", name: "AirPods Pro 3", type: .input)
        check(service.state(for: input) == nil && !service.request(.transparency, for: input), "microphone endpoint rejected before write")
        let other = AudioDevice(id: 0, uid: "check", name: "Speakers", type: .output)
        check(service.state(for: other) == nil && !service.request(.transparency, for: other), "non-AirPods device rejected before write")
        service.observe([offline, input, other])
        service.observe([])
        print("\(count) checks passed. No real device writes.")
    }
}
