import SwiftUI
import Combine

@main
struct ActionItemsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var dashboardWindow: NSWindow?
    var onboardingWindow: NSWindow?
    let appState = AppState()

    private var cancellables = Set<AnyCancellable>()

    @AppStorage("onboarding_complete") var onboardingComplete = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Set first-launch defaults
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "kimi_api_key") == nil {
            defaults.set("", forKey: "kimi_api_key")
        }
        defaults.set("claude-haiku-4-5-20251001", forKey: "kimi_model")

        setupMenuBar()
        setupGlobalShortcuts()
        setupNotificationObservers()
        appState.startGmailPolling()

        // Request permissions
        ScreenCaptureEngine.requestPermission()
        NotificationManager.shared.requestAuthorization()
        Task { await CalendarService.shared.requestAccess() }

        // Wake notification for Supabase reconnect
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Update badge count when items change
        appState.$actionItems
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarBadge() }
            .store(in: &cancellables)

        // Show onboarding or go straight to War Room
        if onboardingComplete {
            openDashboard()
        } else {
            openOnboarding()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "actionitems" {
            switch url.host {
            case "gmail-connected":
                appState.gmail.handleConnectedCallback()
            case "slack-connected":
                Task {
                    guard let token = try? await FlaxieAPIClient.shared.fetchSlackToken() else { return }
                    try? await appState.slack.connect(token: token)
                }
            default:
                break
            }
        }
    }

    @objc private func handleWake() {
        appState.supabase.reconnect()
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .openDashboard,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openDashboard()
        }

        NotificationCenter.default.addObserver(
            forName: .nudgeResponseDone,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let itemId = notification.userInfo?["itemId"] as? Int64 {
                self?.appState.updateStatus(itemId: itemId, status: .done)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .nudgeResponseSend,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let itemId = notification.userInfo?["itemId"] as? Int64 {
                self?.appState.nudgeEngine.sendSlackNudge(for: itemId)
            }
        }
    }

    // MARK: - Menu Bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Flaxie")
            button.imagePosition = .imageLeft
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 560)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(appState)
        )
        self.popover = popover
    }

    private func updateMenuBarBadge() {
        let pending = appState.pendingCount
        let overdue = appState.overdueCount
        if let button = statusItem?.button {
            if overdue > 0 {
                button.title = " \(overdue)!"
            } else if pending > 0 {
                button.title = " \(pending)"
            } else {
                button.title = ""
            }
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover?.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - War Room

    func openDashboard() {
        if dashboardWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "War Room · Flaxie"
            window.center()
            window.contentViewController = NSHostingController(
                rootView: DashboardView()
                    .environmentObject(appState)
            )
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.minSize = NSSize(width: 800, height: 550)
            dashboardWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        dashboardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openDashboardFromPopover() {
        popover?.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.openDashboard()
        }
    }

    func openSettingsFromPopover() {
        popover?.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Onboarding

    func openOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Flaxie"
        window.center()
        window.contentViewController = NSHostingController(
            rootView: OnboardingView()
                .environmentObject(appState)
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        onboardingWindow = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === dashboardWindow {
            NSApp.setActivationPolicy(.accessory)
        }
        if (notification.object as? NSWindow) === onboardingWindow {
            // If onboarding closed without completing, open War Room anyway
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.openDashboard()
            }
        }
    }

    // MARK: - Global Shortcuts

    func setupGlobalShortcuts() {
        HotkeyManager.shared.onCaptureScreen = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.appState.captureScreenAndExtract()
            }
        }

        HotkeyManager.shared.onPasteNotes = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.popover?.performClose(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.openDashboard()
                }
            }
        }
    }
}
