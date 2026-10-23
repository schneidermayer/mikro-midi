// swiftc -parse-as-library macos/MikroAppBehavior.swift scripts/check-app-behavior.swift -o /tmp/check-mikro-behavior
// /tmp/check-mikro-behavior
import Foundation

@main struct AppBehaviorChecks {
    @MainActor static func main() {
        let suite = "MikroMIDI.BehaviorChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let behavior = MikroAppBehavior(preview: false, defaults: defaults)
        precondition(behavior.runInBackground && behavior.showInMenuBar && behavior.showInDock)

        behavior.showInDock = false
        precondition(!behavior.showInDock && behavior.showInMenuBar)
        behavior.showInMenuBar = false
        precondition(behavior.showInDock && !behavior.showInMenuBar)
        precondition(defaults.bool(forKey: "showInDock") && !defaults.bool(forKey: "showInMenuBar"))
        behavior.showInDock = false
        precondition(!behavior.showInDock && behavior.showInMenuBar)
        precondition(!defaults.bool(forKey: "showInDock") && defaults.bool(forKey: "showInMenuBar"))

        behavior.runInBackground = false
        let restored = MikroAppBehavior(preview: false, defaults: defaults)
        precondition(!restored.runInBackground && !restored.showInDock && restored.showInMenuBar)

        defaults.set(false, forKey: "showInMenuBar")
        let recovered = MikroAppBehavior(preview: false, defaults: defaults)
        precondition(recovered.showInDock || recovered.showInMenuBar)

        let beforePreview = defaults.persistentDomain(forName: suite)! as NSDictionary
        let preview = MikroAppBehavior(preview: true, defaults: defaults)
        precondition(preview.runInBackground && preview.showInMenuBar && preview.showInDock)
        preview.runInBackground = false
        preview.showInDock = false
        preview.showInMenuBar = false
        precondition(beforePreview.isEqual(to: defaults.persistentDomain(forName: suite)!))
        print("App behavior checks passed: defaults, persistence, reachable entry points, preview isolation.")
    }
}
