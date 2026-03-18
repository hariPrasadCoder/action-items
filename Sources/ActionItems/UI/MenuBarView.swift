import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            quickActions
            Divider()
            upcomingMeetingsSection
            itemsList
            Divider()
            footer
        }
        .frame(width: 380)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(appState.isRecordingMeeting ? Color.red.opacity(0.15) : Color.blue.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: appState.isRecordingMeeting ? "waveform.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(appState.isRecordingMeeting ? .red : .blue)
                    .font(.system(size: 18))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Action Items")
                    .font(.headline)
                if appState.overdueCount > 0 {
                    Text("\(appState.overdueCount) overdue · \(appState.pendingCount) pending")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else if appState.pendingCount > 0 {
                    Text("\(appState.pendingCount) pending")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("All clear")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            if appState.overdueCount > 0 {
                Text("\(appState.overdueCount)!")
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.red)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            } else if appState.pendingCount > 0 {
                Text("\(appState.pendingCount)")
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 2) {
            // Notification banner
            if let note = appState.notification {
                HStack(spacing: 7) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }

            // Live transcript snippet
            if appState.isRecordingMeeting && !appState.liveTranscript.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text(appState.liveTranscript.suffix(120).description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }

            QuickActionButton(
                icon: appState.isRecordingMeeting ? "stop.circle.fill" : "waveform.circle",
                label: appState.isRecordingMeeting ? "Stop Recording" : "Record Meeting",
                shortcut: "⌘⇧M",
                tint: appState.isRecordingMeeting ? .red : .blue,
                loading: appState.isMeetingModelLoading
            ) {
                Task { await appState.toggleMeetingRecording() }
            }

            QuickActionButton(
                icon: "camera.viewfinder",
                label: "Capture Screen",
                shortcut: "⌘⇧A",
                tint: .indigo,
                loading: appState.isExtracting && !appState.isRecordingMeeting
            ) {
                Task { await appState.captureScreenAndExtract() }
            }

            QuickActionButton(
                icon: appState.gmail.isConnected ? "envelope.badge" : "envelope.badge.fill",
                label: appState.gmail.isConnected ? "Sync Gmail" : "Connect Gmail",
                shortcut: nil,
                tint: .orange,
                loading: false
            ) {
                if appState.gmail.isConnected {
                    Task { await appState.pollGmail() }
                } else {
                    appState.gmail.startOAuthFlow()
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    // MARK: - Upcoming Meetings

    @ViewBuilder
    private var upcomingMeetingsSection: some View {
        if appState.calendar.isAuthorized && !appState.calendar.upcomingMeetings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Meetings")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                ForEach(appState.calendar.upcomingMeetings.prefix(3), id: \.eventIdentifier) { event in
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.callout)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title ?? "Meeting")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text(event.startDate.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            Task { await appState.toggleMeetingRecording() }
                        } label: {
                            Image(systemName: appState.isRecordingMeeting ? "stop.circle.fill" : "record.circle")
                                .foregroundStyle(appState.isRecordingMeeting ? .red : .blue.opacity(0.7))
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("Record meeting")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 3)
                }
            }
            .padding(.bottom, 6)
            Divider()
        }
    }

    // MARK: - Items List

    private var itemsList: some View {
        Group {
            let pending = appState.actionItems.filter { !$0.isCompleted }
            if pending.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24, weight: .thin))
                        .foregroundStyle(.tertiary)
                    Text("No pending items")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(pending.prefix(10)) { item in
                            MiniItemRow(item: item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if pending.count > 10 {
                            Text("+ \(pending.count - 10) more — Open Dashboard")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: 240)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Dashboard") {
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.openDashboard()
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.blue)

            Spacer()

            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("·").foregroundStyle(.tertiary).font(.caption)

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Mini Item Row

struct MiniItemRow: View {
    @EnvironmentObject var appState: AppState
    let item: ActionItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { appState.toggle(item) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.isCompleted ? .green : Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.task)
                    .font(.callout)
                    .lineLimit(2)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    Image(systemName: item.source.icon)
                        .font(.caption2)
                        .foregroundStyle(item.source.color)

                    if let displayText = item.deadlineDisplayText {
                        Text(displayText)
                            .font(.caption2)
                            .foregroundStyle(item.urgency == .none ? .secondary : item.urgency.color)
                    } else if !item.sourceDetail.isEmpty {
                        Text(item.sourceDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(
            item.urgency == .overdue && !item.isCompleted
                ? Color.red.opacity(0.05)
                : Color.clear
        )
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let label: String
    let shortcut: String?
    let tint: Color
    let loading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if loading {
                        ProgressView().controlSize(.small).frame(width: 18)
                    } else {
                        Image(systemName: icon)
                            .foregroundStyle(tint)
                            .frame(width: 18)
                    }
                }
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.0001))
        }
        .buttonStyle(.plain)
        .cornerRadius(6)
        .disabled(loading)
    }
}
