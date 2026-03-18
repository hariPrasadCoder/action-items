import SwiftUI
import EventKit

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSource: ActionItemSource? = nil
    @State private var showCompleted = false
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            mainContent
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $showCompleted) {
                    Label(showCompleted ? "Hide Done" : "Show Done",
                          systemImage: showCompleted ? "eye.slash" : "eye")
                }
                .toggleStyle(.button)
                .help("Toggle completed items")

                Divider()

                Button {
                    Task { await appState.captureScreenAndExtract() }
                } label: {
                    Label("Capture Screen", systemImage: "camera.viewfinder")
                }
                .disabled(appState.isExtracting)
                .help("Capture screen (⌘⇧A)")

                Button {
                    Task { await appState.toggleMeetingRecording() }
                } label: {
                    if appState.isMeetingModelLoading {
                        Label("Loading...", systemImage: "waveform.circle")
                    } else {
                        Label(
                            appState.isRecordingMeeting ? "Stop Recording" : "Record Meeting",
                            systemImage: appState.isRecordingMeeting ? "stop.circle.fill" : "waveform.circle"
                        )
                    }
                }
                .tint(appState.isRecordingMeeting ? .red : .accentColor)
                .help("Toggle meeting recording (⌘⇧M)")
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            // Stats
            if appState.overdueCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text("\(appState.overdueCount) overdue")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.red.opacity(0.1))
                .cornerRadius(6)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 8))
            }

            Section("Sources") {
                SidebarRow(icon: "tray.full", label: "All",
                           count: filteredItems(nil).count, source: nil, selected: $selectedSource)

                ForEach(ActionItemSource.allCases, id: \.self) { source in
                    SidebarRow(
                        icon: source.icon,
                        label: source.displayName,
                        count: filteredItems(source).count,
                        source: source,
                        selected: $selectedSource,
                        color: source.color
                    )
                }
            }

            // Upcoming meetings from calendar
            if appState.calendar.isAuthorized && !appState.calendar.upcomingMeetings.isEmpty {
                Section("Today's Meetings") {
                    ForEach(appState.calendar.upcomingMeetings.prefix(5), id: \.eventIdentifier) { event in
                        UpcomingMeetingRow(event: event, appState: appState)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("Search action items...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Recording status bar
            if appState.isRecordingMeeting {
                MeetingStatusBar()
                    .environmentObject(appState)
            }

            // Notification banner
            if let note = appState.notification {
                HStack(spacing: 8) {
                    Image(systemName: note.lowercased().hasPrefix("error") ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(note.lowercased().hasPrefix("error") ? .red : .blue)
                    Text(note)
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(note.lowercased().hasPrefix("error") ? .red.opacity(0.08) : .blue.opacity(0.08))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Items list
            let items = displayedItems
            if items.isEmpty {
                emptyState
            } else {
                List {
                    // Overdue section at top if there are overdue items
                    let overdueItems = items.filter { $0.urgency == .overdue }
                    if !overdueItems.isEmpty && searchText.isEmpty {
                        Section {
                            ForEach(overdueItems) { item in
                                ActionItemRow(item: item)
                                    .environmentObject(appState)
                            }
                        } header: {
                            Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                    }

                    // Remaining items grouped by date
                    let remaining = overdueItems.isEmpty || !searchText.isEmpty
                        ? items
                        : items.filter { $0.urgency != .overdue }

                    ForEach(groupedItems(remaining), id: \.0) { date, dayItems in
                        Section {
                            ForEach(dayItems) { item in
                                ActionItemRow(item: item)
                                    .environmentObject(appState)
                            }
                        } header: {
                            Text(date)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
                .animation(.default, value: items.count)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedSource?.icon ?? "checkmark.circle")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text(emptyStateTitle)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(emptyStateSubtitle)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            if !searchText.isEmpty {
                Button("Clear Search") { searchText = "" }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var emptyStateTitle: String {
        if !searchText.isEmpty { return "No results for \"\(searchText)\"" }
        if showCompleted { return "No items" }
        return "All clear!"
    }

    private var emptyStateSubtitle: String {
        if !searchText.isEmpty { return "Try a different search term" }
        if showCompleted { return "No action items yet" }
        return "Press ⌘⇧A to capture from screen\nor ⌘⇧M to record a meeting"
    }

    // MARK: - Filtering

    private func filteredItems(_ source: ActionItemSource?) -> [ActionItem] {
        var items = appState.actionItems
        if let source { items = items.filter { $0.source == source } }
        if !showCompleted { items = items.filter { !$0.isCompleted } }
        return items
    }

    private var displayedItems: [ActionItem] {
        var items = filteredItems(selectedSource)
        if !searchText.isEmpty {
            items = items.filter {
                $0.task.localizedCaseInsensitiveContains(searchText)
                || $0.sourceDetail.localizedCaseInsensitiveContains(searchText)
            }
        }
        return items
    }

    private func groupedItems(_ items: [ActionItem]) -> [(String, [ActionItem])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let grouped = Dictionary(grouping: items) { item in
            formatter.string(from: item.createdAt)
        }

        return grouped.sorted { a, b in
            let dateA = a.value.first?.createdAt ?? Date.distantPast
            let dateB = b.value.first?.createdAt ?? Date.distantPast
            return dateA > dateB
        }
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let icon: String
    let label: String
    let count: Int
    let source: ActionItemSource?
    @Binding var selected: ActionItemSource?
    var color: Color = .secondary

    var isSelected: Bool { selected == source }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(isSelected ? color : .secondary)
                .frame(width: 18)
            Text(label)
                .font(.callout)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.15))
                    .foregroundStyle(isSelected ? color : .secondary)
                    .clipShape(Capsule())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selected = source }
        .listRowBackground(
            isSelected
                ? color.opacity(0.1).cornerRadius(6)
                : Color.clear.cornerRadius(6)
        )
    }
}

// MARK: - Upcoming Meeting Row

struct UpcomingMeetingRow: View {
    let event: EKEvent
    let appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
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
                    .foregroundStyle(appState.isRecordingMeeting ? .red : .blue)
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .help(appState.isRecordingMeeting ? "Stop recording" : "Record this meeting")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Action Item Row

struct ActionItemRow: View {
    @EnvironmentObject var appState: AppState
    let item: ActionItem
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Source color accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(item.source.color)
                .frame(width: 3)
                .padding(.vertical, 6)

            HStack(alignment: .top, spacing: 10) {
                // Checkbox
                Button { appState.toggle(item) } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(item.isCompleted ? .green : Color.secondary.opacity(0.7))
                        .animation(.easeInOut(duration: 0.15), value: item.isCompleted)
                }
                .buttonStyle(.plain)

                // Content
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.task)
                        .font(.body)
                        .strikethrough(item.isCompleted, color: .secondary)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Badges row
                    HStack(spacing: 6) {
                        // Source badge
                        Label(item.source.displayName, systemImage: item.source.icon)
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(item.source.color.opacity(0.12))
                            .foregroundStyle(item.source.color)
                            .clipShape(Capsule())

                        // Source detail
                        if !item.sourceDetail.isEmpty {
                            Text(item.sourceDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    // Deadline + timestamp row
                    HStack(spacing: 6) {
                        if let displayText = item.deadlineDisplayText {
                            DeadlineBadge(text: displayText, urgency: item.urgency)
                        }

                        Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                }

                Spacer()

                // Delete button (shows on hover)
                Button { appState.delete(item) } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 0.7 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(item.urgency == .overdue && !item.isCompleted
                      ? Color.red.opacity(0.04)
                      : Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    item.urgency == .overdue && !item.isCompleted
                        ? Color.red.opacity(0.2)
                        : Color.primary.opacity(0.05),
                    lineWidth: 1
                )
        )
        .onHover { isHovered = $0 }
        .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

// MARK: - Deadline Badge

struct DeadlineBadge: View {
    let text: String
    let urgency: DeadlineUrgency

    var body: some View {
        if urgency == .none {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 3) {
                if !urgency.icon.isEmpty {
                    Image(systemName: urgency.icon)
                        .font(.caption2)
                }
                Text(text)
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(urgency == .overdue ? urgency.color : urgency.color.opacity(0.12))
            .foregroundStyle(urgency == .overdue ? .white : urgency.color)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Meeting Status Bar

struct MeetingStatusBar: View {
    @EnvironmentObject var appState: AppState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
                    .onAppear { pulse = true }

                Text("Recording")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if !appState.liveTranscript.isEmpty {
                Text(appState.liveTranscript.suffix(120).description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 500, alignment: .leading)
            }

            Spacer()

            Button("Stop Recording") {
                Task { await appState.toggleMeetingRecording() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.red.opacity(0.07))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
