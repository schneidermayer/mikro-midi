// swiftc -parse-as-library macos/MikroLoginItem.swift scripts/check-login-item.swift -o target/swift-checks/login-item
// target/swift-checks/login-item
import AppKit
import ServiceManagement

@MainActor private final class MockLoginItemService: MikroLoginItemService {
    var currentStatus: SMAppService.Status = .notRegistered
    var statusReads = 0
    var registerCalls = 0
    var unregisterCalls = 0
    var registrationError: Error?
    var unregistrationError: Error?

    var status: SMAppService.Status {
        statusReads += 1
        return currentStatus
    }

    func register() throws {
        registerCalls += 1
        if let registrationError { throw registrationError }
        currentStatus = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregistrationError { throw unregistrationError }
        currentStatus = .notRegistered
    }
}

@main struct LoginItemChecks {
    @MainActor static func main() {
        checkRegistration()
        checkFailures()
        checkApproval()
        checkExternalChanges()
        checkPreviewIsolation()
        checkLaunchEvents()
        print("Login item checks passed: registration, failures, approval, external changes, preview isolation, launch events.")
    }

    @MainActor private static func checkRegistration() {
        let service = MockLoginItemService()
        let item = MikroLoginItem(preview: false, service: service)
        precondition(!item.launchAtLogin && !item.requiresApproval && item.errorMessage == nil)
        precondition(service.registerCalls == 0 && service.unregisterCalls == 0, "Initialization must not change login registration")

        item.setLaunchAtLogin(true)
        precondition(item.launchAtLogin && item.status == .enabled && service.registerCalls == 1)
        item.setLaunchAtLogin(true)
        precondition(service.registerCalls == 1, "Enabling an enabled item must not register again")
        item.setLaunchAtLogin(false)
        precondition(!item.launchAtLogin && item.status == .notRegistered && service.unregisterCalls == 1)
        item.setLaunchAtLogin(false)
        precondition(service.unregisterCalls == 1, "Disabling an unregistered item must not unregister again")
    }

    @MainActor private static func checkFailures() {
        let service = MockLoginItemService()
        let item = MikroLoginItem(preview: false, service: service)
        let failure = NSError(domain: "LoginItemChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated registration failure"])
        service.registrationError = failure
        item.setLaunchAtLogin(true)
        precondition(!item.launchAtLogin && item.status == .notRegistered, "Registration failure must preserve the real disabled state")
        precondition(item.errorMessage?.contains("Simulated registration failure") == true)

        service.registrationError = nil
        item.setLaunchAtLogin(true)
        precondition(item.launchAtLogin && item.errorMessage == nil, "A successful retry must clear the error")
        service.unregistrationError = failure
        item.setLaunchAtLogin(false)
        precondition(item.launchAtLogin && item.status == .enabled && item.errorMessage != nil, "Unregistration failure must preserve the real enabled state")
    }

    @MainActor private static func checkApproval() {
        let service = MockLoginItemService()
        service.currentStatus = .requiresApproval
        let item = MikroLoginItem(preview: false, service: service)
        precondition(item.launchAtLogin && item.requiresApproval)
        item.setLaunchAtLogin(true)
        precondition(service.registerCalls == 0 && item.requiresApproval, "A registered item awaiting approval must not be registered again")
        item.setLaunchAtLogin(false)
        precondition(service.unregisterCalls == 1 && !item.launchAtLogin && !item.requiresApproval, "An item awaiting approval must remain switchable off")
    }

    @MainActor private static func checkExternalChanges() {
        let service = MockLoginItemService()
        let item = MikroLoginItem(preview: false, service: service)
        for status: SMAppService.Status in [.enabled, .requiresApproval, .notRegistered, .notFound] {
            service.currentStatus = status
            item.refresh()
            precondition(item.status == status, "Refresh must reflect System Settings changes")
            precondition(item.launchAtLogin == (status == .enabled || status == .requiresApproval))
        }
        precondition(service.registerCalls == 0 && service.unregisterCalls == 0, "Refreshing status must not change registration")

        service.currentStatus = .enabled
        item.setLaunchAtLogin(false)
        precondition(service.unregisterCalls == 1 && !item.launchAtLogin, "A toggle must refresh external state before deciding what to change")
    }

    @MainActor private static func checkPreviewIsolation() {
        let service = MockLoginItemService()
        service.currentStatus = .enabled
        let item = MikroLoginItem(preview: true, service: service)
        precondition(!item.launchAtLogin, "Preview must not read the actual login state")
        item.refresh()
        item.setLaunchAtLogin(true)
        precondition(item.launchAtLogin)
        item.refresh()
        precondition(item.launchAtLogin)
        item.setLaunchAtLogin(false)
        item.openLoginItemsSettings()
        precondition(!item.launchAtLogin && service.currentStatus == .enabled)
        precondition(service.statusReads == 0 && service.registerCalls == 0 && service.unregisterCalls == 0, "Preview must not read or mutate the login service")
    }

    private static func checkLaunchEvents() {
        func event(_ eventID: AEEventID = AEEventID(kAEOpenApplication), eventClass: AEEventClass = AEEventClass(kCoreEventClass), marker: OSType? = nil) -> NSAppleEventDescriptor {
            let event = NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID, targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            if let marker {
                event.setParam(NSAppleEventDescriptor(enumCode: marker), forKeyword: AEKeyword(keyAEPropData))
            }
            return event
        }

        precondition(MikroLaunchContext.isLoginItem(event(marker: OSType(keyAELaunchedAsLogInItem))))
        precondition(!MikroLaunchContext.isLoginItem(nil))
        precondition(!MikroLaunchContext.isLoginItem(event()), "A regular launch must show the editor")
        precondition(!MikroLaunchContext.isLoginItem(event(AEEventID(kAEReopenApplication), marker: OSType(keyAELaunchedAsLogInItem))), "A reopen event is not a login launch")
        precondition(!MikroLaunchContext.isLoginItem(event(eventClass: AEEventClass(0x54455354), marker: OSType(keyAELaunchedAsLogInItem))), "The login marker must belong to the core event class")
        precondition(!MikroLaunchContext.isLoginItem(event(marker: OSType(keyAELaunchedAsServiceItem))), "A service launch is not a login-item launch")
        let wrongParameter = event()
        wrongParameter.setParam(NSAppleEventDescriptor(boolean: true), forKeyword: AEKeyword(keyAELaunchedAsLogInItem))
        precondition(!MikroLaunchContext.isLoginItem(wrongParameter), "The login marker must be the value of keyAEPropData")
    }
}
