import AppKit
import Observation
import ServiceManagement

@MainActor protocol MikroLoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor private struct SystemLoginItemService: MikroLoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@Observable @MainActor final class MikroLoginItem {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var errorMessage: String?
    @ObservationIgnored private let preview: Bool
    @ObservationIgnored private let service: any MikroLoginItemService

    init(preview: Bool, service: (any MikroLoginItemService)? = nil) {
        self.preview = preview
        self.service = service ?? SystemLoginItemService()
        refresh()
    }

    // A registered item awaiting approval stays switchable off; the UI explains
    // that macOS has not yet allowed it to launch.
    var launchAtLogin: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        if !preview { status = service.status }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        errorMessage = nil
        if preview {
            status = enabled ? .enabled : .notRegistered
            return
        }
        refresh()
        do {
            if enabled && !launchAtLogin {
                try service.register()
            } else if !enabled && launchAtLogin {
                try service.unregister()
            }
        } catch {
            errorMessage = "Could not change Launch at login. \(error.localizedDescription)"
        }
        // The OS is the source of truth, including failures and external changes.
        refresh()
    }

    func openLoginItemsSettings() {
        if !preview { SMAppService.openSystemSettingsLoginItems() }
    }
}

enum MikroLaunchContext {
    static func isLoginItem(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventID == AEEventID(kAEOpenApplication),
              event.eventClass == AEEventClass(kCoreEventClass) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }
}
