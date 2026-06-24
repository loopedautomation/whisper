import Foundation
import ServiceManagement

/// Wraps `SMAppService` for "launch at login". Works for LSUIElement agent apps.
/// Always read `isEnabled` from live status rather than caching a bool.
@MainActor
final class LoginItemManager: ObservableObject {
    @Published var isEnabled = false
    @Published var requiresApproval = false

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    /// Enables or disables launch-at-login in response to an explicit user toggle.
    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LoginItem: \(error.localizedDescription)")
        }
        refresh()
    }
}
