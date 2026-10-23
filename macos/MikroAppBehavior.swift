import AppKit
import Observation

@Observable @MainActor final class MikroAppBehavior {
    var runInBackground: Bool {
        didSet {
            save(runInBackground, forKey: "runInBackground")
            if !runInBackground, isPrepared, mainWindow?.isVisible != true { showWindow() }
        }
    }
    var showInMenuBar: Bool {
        didSet {
            // Keep an entry point available when the editor is closed.
            if !showInMenuBar && !showInDock { showInDock = true }
            save(showInMenuBar, forKey: "showInMenuBar")
        }
    }
    var showInDock: Bool {
        didSet {
            if !showInDock && !showInMenuBar { showInMenuBar = true }
            save(showInDock, forKey: "showInDock")
            if isPrepared { applyActivationPolicy() }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let preview: Bool
    @ObservationIgnored private var isPrepared = false
    @ObservationIgnored private weak var mainWindow: NSWindow?
    @ObservationIgnored var openEditor: (() -> Void)?

    init(preview: Bool, defaults: UserDefaults = .standard) {
        self.preview = preview
        self.defaults = defaults
        runInBackground = preview ? true : defaults.object(forKey: "runInBackground") as? Bool ?? true
        let savedMenuBar = preview ? true : defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        showInMenuBar = savedMenuBar
        let savedDock = preview ? true : defaults.object(forKey: "showInDock") as? Bool ?? true
        showInDock = savedDock || !savedMenuBar
    }

    func attach(window: NSWindow) {
        mainWindow = window
        prepareForLaunch()
    }

    func prepareForLaunch() {
        guard !isPrepared else { return }
        isPrepared = true
        applyActivationPolicy()
    }

    func showWindow() {
        openEditor?()
        // Finish the menu action before bringing the editor forward.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.mainWindow?.isMiniaturized == true { self.mainWindow?.deminiaturize(nil) }
            NSApplication.shared.activate(ignoringOtherApps: true)
            self.mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    func hideWindow() {
        runInBackground = true
        mainWindow?.performClose(nil)
    }

    private func save(_ value: Bool, forKey key: String) {
        if !preview { defaults.set(value, forKey: key) }
    }

    private func applyActivationPolicy() {
        let wasKey = mainWindow?.isKeyWindow == true
        NSApplication.shared.setActivationPolicy(showInDock ? .regular : .accessory)
        if wasKey {
            DispatchQueue.main.async { [weak self] in
                NSApplication.shared.activate(ignoringOtherApps: true)
                self?.mainWindow?.makeKeyAndOrderFront(nil)
            }
        }
    }
}

