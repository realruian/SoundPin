import Foundation
import ServiceManagement

enum LoginItemState: Equatable {
    case disabled, enabled, approvalRequired, unavailable
}

@MainActor protocol LaunchAtLoginServicing {
    var state: LoginItemState { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

@MainActor private struct SystemLoginItemService: LaunchAtLoginServicing {
    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .approvalRequired
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    enum Notice: Equatable {
        case approvalRequired
        case failed(String)
    }

    private let service: LaunchAtLoginServicing
    @Published private(set) var state: LoginItemState = .disabled
    @Published var notice: Notice?
    var isEnabled: Bool { state == .enabled }

    init(service: LaunchAtLoginServicing? = nil) {
        self.service = service ?? SystemLoginItemService()
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        notice = nil
        refresh()
        if enabled && state == .approvalRequired {
            // Registering again cannot replace consent withdrawn in System Settings.
            notice = .approvalRequired
            return
        }
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
            refresh()
            if enabled && state == .approvalRequired { notice = .approvalRequired }
            else if isEnabled != enabled { notice = .failed(L10n.loginChangeUnconfirmed) }
        } catch {
            refresh()
            notice = .failed(error.localizedDescription)
        }
    }

    func openSettings() {
        notice = nil
        service.openSettings()
    }

    func refresh() {
        let current = service.state
        if current != state { state = current }
    }
}
