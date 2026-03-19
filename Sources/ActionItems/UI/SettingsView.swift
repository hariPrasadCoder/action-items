import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("gmail_client_id")     var gmailClientID = ""
    @AppStorage("gmail_client_secret") var gmailClientSecret = ""
    @AppStorage("gmail_poll_minutes")  var gmailPollMinutes = 5
    @AppStorage("fireflies_api_key")   var firefliesAPIKey = ""

    @State private var selectedTab: SettingsTab = .general
    @State private var launchAtLoginError: String?

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general       = "General"
        case profile       = "Profile"
        case integrations  = "Integrations"
        case notifications = "Notifications"
        case shortcuts     = "Shortcuts"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general:       return "gear"
            case .profile:       return "person.circle"
            case .integrations:  return "puzzlepiece.fill"
            case .notifications: return "bell.fill"
            case .shortcuts:     return "keyboard"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider().overlay(Color.flaxPurple.opacity(0.1))
            settingsContent
        }
        .frame(width: 620, height: 480)
        .background(Color.flaxCream)
    }

    // MARK: - Sidebar

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(Color.flaxInk)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)

            ForEach(SettingsTab.allCases) { tab in
                SettingsSidebarRow(
                    icon: tab.icon,
                    label: tab.rawValue,
                    isSelected: selectedTab == tab
                ) { selectedTab = tab }
            }

            Spacer()

            // Version footer
            Text("Flaxie 3.0.0")
                .font(.caption2)
                .foregroundStyle(Color.flaxMuted.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: 170)
        .background(Color.flaxCream.opacity(0.6))
    }

    // MARK: - Content

    @ViewBuilder
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Tab title
                Text(selectedTab.rawValue)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.flaxInk)
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 18)

                Divider().overlay(Color.flaxPurple.opacity(0.08))
                    .padding(.bottom, 16)

                Group {
                    switch selectedTab {
                    case .general:       generalContent
                    case .profile:       profileContent
                    case .integrations:  integrationsContent
                    case .notifications: notificationsContent
                    case .shortcuts:     shortcutsContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - General

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Startup") {
                Toggle(isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { enable in
                        do {
                            if enable { try SMAppService.mainApp.register() }
                            else       { try SMAppService.mainApp.unregister() }
                            launchAtLoginError = nil
                        } catch { launchAtLoginError = error.localizedDescription }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                        Text("Flaxie starts automatically and lives in the menu bar")
                            .font(.caption).foregroundStyle(Color.flaxMuted)
                    }
                }

                if let err = launchAtLoginError {
                    Text("Error: \(err)").font(.caption).foregroundStyle(.red)
                }

                if SMAppService.mainApp.status == .requiresApproval {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Go to System Settings → General → Login Items to approve")
                            .font(.caption).foregroundStyle(Color.flaxMuted)
                        Spacer()
                        Button("Open") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }

            SettingsSection("About") {
                InfoRow(label: "Version", value: "3.0.0")
                InfoRow(label: "Bundle ID", value: "com.hari.actionitems")
                InfoRow(label: "Backend", value: FlaxieAPIClient.shared.isAuthenticated ? "Connected ✓" : "Not connected")
            }
        }
    }

    // MARK: - Profile

    private var profileContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Your identity") {
                VStack(spacing: 12) {
                    FlaxField(label: "Name", placeholder: "Your name", text: Binding(
                        get: { appState.currentUser.name },
                        set: { appState.currentUser.name = $0 }
                    ))
                    FlaxField(label: "Email", placeholder: "you@company.com", text: Binding(
                        get: { appState.currentUser.email ?? "" },
                        set: { appState.currentUser.email = $0.isEmpty ? nil : $0 }
                    ))
                }

                Text("Flaxie uses your name to identify which tasks are yours in meeting notes.")
                    .font(.caption)
                    .foregroundStyle(Color.flaxMuted)

                Button("Save Profile") { appState.saveCurrentUser() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.flaxPurple)
            }
        }
    }

    // MARK: - Integrations

    private var integrationsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Granola
            SettingsSection("Granola") {
                IntegrationRow(
                    icon: "note.text",
                    name: "Granola",
                    statusText: appState.granola.isWatching ? "Watching for notes" : "Not detected",
                    isConnected: appState.granola.isWatching,
                    detail: appState.granola.watchedDirectory?.path ?? "Install Granola to auto-connect"
                ) {
                    if !appState.granola.isWatching {
                        Button("Connect") { appState.granola.startWatching() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }

            // Fireflies
            SettingsSection("Fireflies.ai") {
                FlaxField(label: "API Key", placeholder: "Your Fireflies API key", text: $firefliesAPIKey)
                    .onChange(of: firefliesAPIKey) { _, v in FirefliesService.apiKey = v }

                IntegrationRow(
                    icon: "waveform.circle.fill",
                    name: "Fireflies",
                    statusText: appState.fireflies.isConnected ? "Connected · polls every 30 min" : "Not connected",
                    isConnected: appState.fireflies.isConnected,
                    detail: "app.fireflies.ai → Settings → API"
                ) {
                    if !firefliesAPIKey.isEmpty && !appState.fireflies.isConnected {
                        Button("Test") { Task { try? await appState.fireflies.testConnection() } }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }

            // Otter
            SettingsSection("Otter.ai") {
                IntegrationRow(
                    icon: "waveform",
                    name: "Otter.ai",
                    statusText: appState.otter.isWatching ? "Watching Downloads folder" : "Not active",
                    isConnected: appState.otter.isWatching,
                    detail: "Export transcripts as .txt from Otter — auto-detected"
                ) { EmptyView() }
            }

            // Slack
            SettingsSection("Slack") {
                if appState.slack.isConnected {
                    IntegrationRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        name: "Slack",
                        statusText: "Connected to \(appState.slack.workspaceName ?? "workspace")",
                        isConnected: true,
                        detail: "\(appState.slack.workspaceMembers.count) members loaded"
                    ) {
                        Button("Disconnect") { appState.slack.disconnect() }
                            .buttonStyle(.bordered).tint(.red).controlSize(.small)
                    }
                } else {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 0.27, green: 0.20, blue: 0.40).opacity(0.10))
                                .frame(width: 36, height: 36)
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(Color(red: 0.27, green: 0.20, blue: 0.40))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect Slack workspace")
                                .font(.callout.weight(.medium))
                            Text("Opens browser to authorize — no token needed")
                                .font(.caption).foregroundStyle(Color.flaxMuted)
                        }
                        Spacer()
                        Button("Connect") { FlaxieAPIClient.shared.connectSlack() }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.27, green: 0.20, blue: 0.40))
                            .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            // Gmail
            SettingsSection("Gmail") {
                VStack(spacing: 10) {
                    FlaxField(label: "Client ID", placeholder: "OAuth Client ID", text: $gmailClientID)
                    FlaxField(label: "Client Secret", placeholder: "OAuth Client Secret", text: $gmailClientSecret)
                }
                Text("console.cloud.google.com → Gmail API → OAuth Desktop App → Redirect: actionitems://gmail-callback")
                    .font(.caption).foregroundStyle(Color.flaxMuted)

                if appState.gmail.isConnected {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Gmail connected")
                        Spacer()
                        Button("Sync Now") { Task { await appState.pollGmail() } }
                            .buttonStyle(.bordered).controlSize(.small)
                        Button("Disconnect") { appState.gmail.disconnect() }
                            .buttonStyle(.bordered).tint(.red).controlSize(.small)
                    }
                } else {
                    Button("Connect Gmail") { appState.gmail.startOAuthFlow() }
                        .buttonStyle(.borderedProminent).tint(.orange)
                        .disabled(gmailClientID.isEmpty)
                }

                Stepper("Check every \(gmailPollMinutes) minute\(gmailPollMinutes == 1 ? "" : "s")",
                        value: $gmailPollMinutes, in: 1...60)
            }
        }
    }

    // MARK: - Notifications

    private var notificationsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Smart nudges") {
                FeatureRow(icon: "bell.badge.fill", color: Color.flaxPurple,
                           text: "Flaxie nudges you and teammates at the right time")
                FeatureRow(icon: "moon.fill", color: .indigo,
                           text: "Quiet hours: never before 9am or after 7pm")
                FeatureRow(icon: "clock.badge.fill", color: .orange,
                           text: "30-minute deadline reminders for your own tasks")

                Button("Notification Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }

            SettingsSection("Calendar") {
                HStack(spacing: 10) {
                    Image(systemName: appState.calendar.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appState.calendar.isAuthorized ? .green : Color.flaxMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.calendar.isAuthorized ? "Calendar access granted" : "Calendar access not granted")
                        Text("Detects upcoming meetings to capture action items")
                            .font(.caption).foregroundStyle(Color.flaxMuted)
                    }
                    Spacer()
                    if !appState.calendar.isAuthorized {
                        Button("Grant Access") { Task { await appState.calendar.requestAccess() } }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Shortcuts

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Global shortcuts") {
                VStack(spacing: 10) {
                    ShortcutRow(label: "Capture screen & extract", shortcut: "⌘⇧A")
                    ShortcutRow(label: "Paste meeting notes", shortcut: "⌘⇧N")
                }
                Text("These shortcuts work system-wide, even when Flaxie is not focused.")
                    .font(.caption).foregroundStyle(Color.flaxMuted)
            }
        }
    }
}

// MARK: - Sidebar Row

struct SettingsSidebarRow: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? Color.flaxPurple : Color.flaxMuted)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.flaxInk : Color.flaxMuted)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected
                          ? Color.flaxPurple.opacity(0.10)
                          : isHovered ? Color.flaxPurple.opacity(0.04) : Color.clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.flaxPurple.opacity(0.6))

            content()
        }
    }
}

// MARK: - Integration Row

struct IntegrationRow<Action: View>: View {
    let icon: String
    let name: String
    let statusText: String
    let isConnected: Bool
    let detail: String
    @ViewBuilder let actionButton: () -> Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(isConnected ? .green : Color.flaxMuted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(Color.flaxInk)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.flaxMuted)
                    .lineLimit(1)
            }
            Spacer()
            actionButton()
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Color.flaxMuted)
            Spacer()
            Text(value).foregroundStyle(Color.flaxInk).font(.callout)
        }
        .font(.callout)
    }
}

// MARK: - Shortcut Row

struct ShortcutRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(Color.flaxInk)
            Spacer()
            Text(shortcut)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Color.flaxInk)
        }
    }
}

struct ShortcutBadge: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct PermissionRow: View {
    let icon: String
    let label: String
    let detail: String
    let settingsURL: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 22)
                .foregroundStyle(Color.flaxPurple)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.callout)
                Text(detail).font(.caption).foregroundStyle(Color.flaxMuted)
            }
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: settingsURL)!)
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }
}
