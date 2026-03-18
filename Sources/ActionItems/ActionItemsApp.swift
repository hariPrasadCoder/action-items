import SwiftUI
import AVFoundation
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
    let appState = AppState()

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Set defaults on first launch
        // API keys are configured via Settings — do not hardcode secrets here
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "kimi_api_key") == nil {
            defaults.set("", forKey: "kimi_api_key")
        }
        defaults.set("claude-haiku-4-5-20251001", forKey: "kimi_model")

        setupMenuBar()
        setupGlobalShortcuts()
        setupNotificationObservers()
        appState.startGmailPolling()

        // Request all permissions
        ScreenCaptureEngine.requestPermission()
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        NotificationManager.shared.requestAuthorization()
        Task { await CalendarService.shared.requestAccess() }

        // Update badge count when items change
        appState.$actionItems
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarBadge() }
            .store(in: &cancellables)

        openDashboard()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "actionitems" && url.host == "gmail-callback" {
            appState.gmail.handleCallback(url: url)
        }
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .startMeetingRecording,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.appState.toggleMeetingRecording() }
        }

        NotificationCenter.default.addObserver(
            forName: .openDashboard,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openDashboard()
        }
    }

    // MARK: - Menu Bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Action Items")
            button.imagePosition = .imageLeft
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 540)
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

    func openDashboard() {
        if dashboardWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Action Items"
            window.center()
            window.contentViewController = NSHostingController(
                rootView: DashboardView()
                    .environmentObject(appState)
            )
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.minSize = NSSize(width: 700, height: 500)
            dashboardWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        dashboardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === dashboardWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Global Shortcuts

    func setupGlobalShortcuts() {
        HotkeyManager.shared.onCaptureScreen = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.appState.captureScreenAndExtract()
            }
        }

        HotkeyManager.shared.onToggleMeeting = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.appState.toggleMeetingRecording()
            }
        }
    }
}
