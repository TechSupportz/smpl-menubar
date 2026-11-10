import AppKit
import ServiceManagement

/// Launch at Login, including the state where macOS is waiting for approval in System Settings.
@MainActor
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = on ? "Couldn’t turn on Launch at Login" : "Couldn’t turn off Launch at Login"
            alert.runModal()
        }
        if on, needsApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
