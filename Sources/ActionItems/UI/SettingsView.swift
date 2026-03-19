import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("kimi_api_key") var kimiAPIKey = ""
    @AppStorage("kimi_model") var kimiModel = "claude-haiku-4-5-20251001"
    @AppStorage("whisper_model") var whisperModel = "base"
    @AppStorage("gmail_client_id") var gmailClientID = ""
    @AppStorage("gmail_client_secret") var gmailClientSecret = ""
    @AppStorage("gmail_poll_minutes") var gmailPollMinutes = 5
    @State private var kimiTestResult = ""
    @State private var isTesting = false
    @State private var launchAtLoginError: String?

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            apiTab.tabItem { Label("API", systemImage: "key") }
            meetingTab.tabItem { Label("Meeting", systemImage: "waveform") }
            gmailTab.tabItem { Label("Gmail", systemImage: "envelope") }
            notificationsTab.tabItem { Label("Notifications", systemImage: "bell") }
            shortcutsTab.tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Startup") {
                Toggle(isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { enable in
                        do {
                            if enable {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = error.localizedDescription
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                        Text("ActionItems starts automatically when you log in and runs in the menu bar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let err = launchAtLoginError {
                    Text("Error: \(err)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if SMAppService.mainApp.status == .requiresApproval {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Requires approval in System Settings → General → Login Items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Section("About") {
                LabeledContent("Version") { Text("2.0.0") }
                LabeledContent("Bundle ID") { Text("com.hari.actionitems").foregroundStyle(.secondary) }
                HStack {
                    Link("GitHub", destination: URL(string: "https://github.com/hariPrasadCoder/action-items")!)
                    Spacer()
                }
            }
        }
    }

    // MARK: - API Tab

    private var apiTab: some View {
        Form {
            Section("Claude API (Anthropic)") {
                HStack {
                    Text("API Key")
                    SecureField("sk-ant-...", text: $kimiAPIKey)
                }

                Picker("Model", selection: $kimiModel) {
                    Text("Haiku 4.5 (fast, economical)").tag("claude-haiku-4-5-20251001")
                    Text("Sonnet 4.6 (recommended)").tag("claude-sonnet-4-6")
                    Text("Opus 4.6 (most capable)").tag("claude-opus-4-6")
                }

                HStack {
                    Button("Test Connection") {
                        isTesting = true
                        Task {
                            await testKimiConnection()
                            isTesting = false
                        }
                    }
                    .disabled(isTesting)

                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else if !kimiTestResult.isEmpty {
                        Text(kimiTestResult)
                            .font(.caption)
                            .foregroundStyle(kimiTestResult.hasPrefix("Error") ? .red : .green)
                    }
                }
            }
        }
    }

    private func testKimiConnection() async {
        do {
            let result = try await KimiService.extractActionItems(from: "Test: Send the report to John by Friday.")
            kimiTestResult = result.isEmpty
                ? "Connected — no items in test"
                : "Connected — found \(result.count) item(s)"
        } catch {
            kimiTestResult = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Meeting Tab

    private var meetingTab: some View {
        Form {
            Section("Whisper Transcription Model") {
                Picker("Model Size", selection: $whisperModel) {
                    Text("Tiny (~75 MB, fastest)").tag("tiny")
                    Text("Base (~145 MB, recommended)").tag("base")
                    Text("Small (~466 MB, more accurate)").tag("small")
                    Text("Medium (~1.5 GB, most accurate)").tag("medium")
                }

                Text("Model loads into RAM only while recording, then releases immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                PermissionRow(icon: "mic", label: "Microphone",
                              detail: "Required to record your voice",
                              settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                PermissionRow(icon: "desktopcomputer", label: "Screen Recording",
                              detail: "Required for system audio & screen capture",
                              settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            }
        }
    }

    // MARK: - Gmail Tab

    private var gmailTab: some View {
        Form {
            Section("Google OAuth Credentials") {
                TextField("Client ID", text: $gmailClientID)
                SecureField("Client Secret", text: $gmailClientSecret)

                Text("1. Go to console.cloud.google.com\n2. Create a project → Enable Gmail API\n3. Create OAuth credentials (Desktop App)\n4. Add redirect URI: actionitems://gmail-callback")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                if appState.gmail.isConnected {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Connected to Gmail")
                        Spacer()
                        Button("Disconnect") { appState.gmail.disconnect() }.tint(.red)
                    }
                    if let date = appState.gmail.lastSyncDate {
                        Text("Last synced: \(date.formatted())").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Sync Now") { Task { await appState.pollGmail() } }
                } else {
                    Button("Connect Gmail") { appState.gmail.startOAuthFlow() }
                        .buttonStyle(.borderedProminent)
                        .disabled(gmailClientID.isEmpty)
                }
            }

            Section("Polling") {
                Stepper("Check every \(gmailPollMinutes) minute\(gmailPollMinutes == 1 ? "" : "s")",
                        value: $gmailPollMinutes, in: 1...60)
            }
        }
    }

    // MARK: - Notifications Tab

    private var notificationsTab: some View {
        Form {
            Section("Calendar & Meeting Detection") {
                HStack {
                    Image(systemName: appState.calendar.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appState.calendar.isAuthorized ? .green : .red)
                    VStack(alignment: .leading) {
                        Text(appState.calendar.isAuthorized ? "Calendar access granted" : "Calendar access not granted")
                            .font(.callout)
                        Text("Detects upcoming meetings and prompts to record")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !appState.calendar.isAuthorized {
                        Button("Grant Access") {
                            Task { await appState.calendar.requestAccess() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Open Calendar Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if appState.calendar.isAuthorized {
                    let meetings = appState.calendar.upcomingMeetings
                    if meetings.isEmpty {
                        Text("No meetings in the next 8 hours")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(meetings.count) upcoming meeting\(meetings.count == 1 ? "" : "s") detected")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Section("Deadline Reminders") {
                HStack {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text("30-minute deadline alerts")
                            .font(.callout)
                        Text("Notified 30 minutes before each action item deadline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Notification Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        Form {
            Section("Global Keyboard Shortcuts") {
                LabeledContent("Capture Screen & Extract") {
                    ShortcutBadge("⌘⇧A")
                }
                LabeledContent("Toggle Meeting Recording") {
                    ShortcutBadge("⌘⇧M")
                }
                Text("Shortcuts work system-wide, even when the app is not in focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ShortcutBadge: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.15))
            .cornerRadius(5)
    }
}

struct PermissionRow: View {
    let icon: String
    let label: String
    let detail: String
    let settingsURL: String

    var body: some View {
        HStack {
            Image(systemName: icon).frame(width: 24)
            VStack(alignment: .leading) {
                Text(label).font(.callout)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: settingsURL)!)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
