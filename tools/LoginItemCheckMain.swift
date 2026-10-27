import Foundation

@MainActor private final class FakeLoginItem: LaunchAtLoginServicing {
    var state: LoginItemState = .disabled
    var registerResult: LoginItemState = .enabled
    var failure: NSError?
    var registrations = 0
    var settingsOpened = 0
    func register() throws {
        registrations += 1
        if let failure { throw failure }
        state = registerResult
    }
    func unregister() throws {
        if let failure { throw failure }
        state = .disabled
    }
    func openSettings() { settingsOpened += 1 }
}

@main struct LoginItemCheckMain {
    @MainActor static func main() {
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { fatalError(name) }
            checks += 1
            print("ok: \(name)")
        }
        let service = FakeLoginItem()
        let manager = LaunchAtLoginManager(service: service)
        manager.setEnabled(true)
        check(manager.isEnabled && manager.notice == nil, "successful registration reflects the system state")
        service.state = .approvalRequired
        manager.refresh()
        check(!manager.isEnabled && manager.state == .approvalRequired, "revoked consent is distinct from an unregistered item")
        manager.setEnabled(true)
        check(service.registrations == 1 && manager.notice == .approvalRequired, "revoked consent offers approval without repeated registration")
        check(service.settingsOpened == 0, "settings are only opened by an explicit action")
        manager.openSettings()
        check(service.settingsOpened == 1 && manager.notice == nil, "approval action opens the login settings")
        service.state = .enabled
        manager.refresh()
        check(manager.isEnabled, "approval made in System Settings is reflected on refresh")
        service.failure = NSError(domain: "LoginItemCheck", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Test registration error"])
        manager.setEnabled(false)
        check(manager.isEnabled && manager.notice == .failed("Test registration error"), "failed removal keeps actual state and exposes an error")
        service.failure = nil
        manager.setEnabled(false)
        check(!manager.isEnabled && manager.notice == nil, "a later successful attempt clears the error")
        service.registerResult = .approvalRequired
        manager.setEnabled(true)
        check(!manager.isEnabled && manager.notice == .approvalRequired, "registration needing approval never appears enabled")
        service.state = .disabled
        service.registerResult = .unavailable
        manager.setEnabled(true)
        check(manager.notice != nil && !manager.isEnabled, "an unconfirmed registration has visible feedback")
        print("\(checks) login item checks passed. No system login settings were changed.")
    }
}
