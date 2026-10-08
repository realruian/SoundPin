import Foundation
import ServiceManagement

@MainActor
class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    /// What the system reports, not what was last asked for: a change that failed, or one
    /// made in System Settings, shows after the next refresh
    @Published private(set) var isEnabled = false

    private init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            }
        }
        refresh()
    }

    func refresh() {
        if #available(macOS 13.0, *) {
            let newStatus = SMAppService.mainApp.status == .enabled
            if newStatus != isEnabled {
                isEnabled = newStatus
            }
        }
    }
}
