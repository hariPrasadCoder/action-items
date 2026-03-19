import SwiftUI
import EventKit

// MARK: - War Room

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedView: WarRoomView = .people
    @State private var selectedPerson: Person?
    @State private var selectedMeeting: String?
    @State private var showCompleted = false
    @State private var searchText = ""
    @State private var showPasteNotes = false

    enum WarRoomView { case people, mine, all }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Color.flaxPurple.opacity(0.07))
            mainContent
        }
        .background(Color.flaxCream)
        .frame(minWidth: 900, minHeight: 580)
        .sheet(isPresented: $showPasteNotes) {
            PasteNotesView().environmentObject(appState)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    if appState.overdueCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(.red)
                            Text("\(appState.overdueCount) overdue")
                                .font(.caption2.bold()).foregroundStyle(.red)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }

                    sidebarSectionLabel("VIEWS")

                    SidebarRow(icon: "person.fill", label: "My Tasks",
                               count: appState.myItems.filter { showCompleted || $0.status != .done }.count,
                               isSelected: selectedView == .mine && selectedPerson == nil && selectedMeeting == nil) {
                        selectedView = .mine; selectedPerson = nil; selectedMeeting = nil
                    }
                    SidebarRow(icon: "person.2.fill", label: "Team",
                               count: appState.delegatedItems.count,
                               isSelected: selectedView == .people && selectedPerson == nil && selectedMeeting == nil) {
                        selectedView = .people; selectedPerson = nil; selectedMeeting = nil
                    }
                    SidebarRow(icon: "tray.full.fill", label: "All Items",
                               count: appState.actionItems.filter { showCompleted || $0.status != .done }.count,
                               isSelected: selectedView == .all && selectedPerson == nil && selectedMeeting == nil) {
                        selectedView = .all; selectedPerson = nil; selectedMeeting = nil
                    }

                    if !appState.delegatedByAssignee.isEmpty {
                        sidebarSectionLabel("PEOPLE")
                        ForEach(appState.delegatedByAssignee, id: \.0.name) { person, items in
                            SidebarPersonRow(
                                person: person,
                                overdueCount: items.filter { $0.urgency == .overdue }.count,
                                taskCount: items.count,
                                isSelected: selectedPerson?.name == person.name
                            ) {
                                selectedPerson = person
                                selectedView = .people
                                selectedMeeting = nil
                            }
                        }
                    }

                    let meetings = Set(appState.actionItems.compactMap { $0.meetingTitle }).sorted()
                    if !meetings.isEmpty {
                        sidebarSectionLabel("MEETINGS")
                        ForEach(meetings, id: \.self) { title in
                            let count = appState.actionItems.filter { $0.meetingTitle == title && $0.status != .done }.count
                            SidebarRow(icon: "calendar.badge.clock", label: title, count: count,
                                       isSelected: selectedMeeting == title, color: .teal) {
                                selectedMeeting = title; selectedPerson = nil
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }

            Divider().overlay(Color.flaxPurple.opacity(0.07))
            sidebarFooter
        }
        .frame(width: 210)
        .background(Color.flaxCream)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.flaxPurple)
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Flaxie")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.flaxInk)
                Text("War Room")
                    .font(.caption2)
                    .foregroundStyle(Color.flaxMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func sidebarSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Color.flaxMuted.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if appState.granola.isWatching {
                integrationDot(label: "Granola", color: .teal)
            }
            if appState.fireflies.isConnected {
                integrationDot(label: "Fireflies", color: .indigo)
            }
            if appState.slack.isConnected {
                integrationDot(label: "Slack", color: Color(red: 0.27, green: 0.20, blue: 0.40))
            }
            if appState.gmail.isConnected {
                integrationDot(label: "Gmail", color: .orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func integrationDot(label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.caption2).foregroundStyle(Color.flaxMuted)
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            contentHeader

            if let note = appState.notification {
                notificationBar(note).transition(.move(edge: .top).combined(with: .opacity))
            }

            searchBar

            Divider().overlay(Color.flaxPurple.opacity(0.07))

            let items = displayedItems
            if items.isEmpty {
                emptyState
            } else if selectedView == .people && selectedPerson == nil && selectedMeeting == nil {
                peopleGrid(items: items)
            } else {
                itemList(items: items)
            }
        }
        .background(Color.flaxCream)
    }

    private var contentHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contentTitle)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.flaxInk)
                if let sub = contentSubtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(Color.flaxMuted)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 6) {
                Button {
                    withAnimation { showCompleted.toggle() }
                } label: {
                    Label(showCompleted ? "Hide Done" : "Show Done",
                          systemImage: showCompleted ? "eye.slash" : "eye")
                        .font(.caption)
                        .foregroundStyle(Color.flaxMuted)
                }
                .buttonStyle(.plain)
                .help(showCompleted ? "Hide completed" : "Show completed")

                headerButton(icon: "square.and.pencil", label: "Paste Notes") {
                    showPasteNotes = true
                }

                headerButton(
                    icon: appState.isExtracting ? "progress.indicator" : "camera.viewfinder",
                    label: "Capture"
                ) {
                    Task { await appState.captureScreenAndExtract() }
                }
                .disabled(appState.isExtracting)

                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(Color.flaxMuted)
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.flaxCream)
    }

    private func headerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.caption)
            }
            .foregroundStyle(Color.flaxMuted)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.flaxPurple.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func notificationBar(_ note: String) -> some View {
        let isError = note.lowercased().hasPrefix("error") || note.lowercased().hasPrefix("enable")
        return HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "sparkles")
                .foregroundStyle(isError ? .red : Color.flaxPurple)
                .font(.callout)
            Text(note).font(.callout).foregroundStyle(isError ? .red : Color.flaxInk)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isError ? Color.red.opacity(0.06) : Color.flaxPurple.opacity(0.06))
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.flaxMuted)
                .font(.callout)
            TextField("Search tasks, people, meetings…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(Color.flaxInk)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.flaxMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.flaxPurple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - People grid

    private func peopleGrid(items: [ActionItem]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(appState.delegatedByAssignee, id: \.0.name) { person, personItems in
                    let filtered = filterItems(personItems)
                    if !filtered.isEmpty {
                        PersonSection(person: person, items: filtered).environmentObject(appState)
                    }
                }
                let myFiltered = filterItems(appState.myItems)
                if !myFiltered.isEmpty {
                    myTasksSection(myFiltered)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func myTasksSection(_ items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PersonAvatar(name: appState.currentUser.name, size: 26)
                Text("My Tasks")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.flaxInk)
                Spacer()
                Text("\(items.count) task\(items.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(Color.flaxMuted)
            }
            .padding(.horizontal, 14)

            ForEach(items) { item in
                ActionItemRow(item: item).environmentObject(appState)
            }
        }
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.flaxPurple.opacity(0.07), lineWidth: 1))
    }

    // MARK: - List view

    private func itemList(items: [ActionItem]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let overdue = searchText.isEmpty ? items.filter { $0.urgency == .overdue } : []
                if !overdue.isEmpty {
                    listSectionHeader("Overdue", icon: "exclamationmark.triangle.fill", color: .red)
                    ForEach(overdue) { item in
                        ActionItemRow(item: item).environmentObject(appState)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 3)
                    }
                }

                let rest = overdue.isEmpty ? items : items.filter { $0.urgency != .overdue }
                ForEach(groupedItems(rest), id: \.0) { dateLabel, dayItems in
                    listSectionHeader(dateLabel, icon: nil, color: Color.flaxMuted)
                    ForEach(dayItems) { item in
                        ActionItemRow(item: item).environmentObject(appState)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 3)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func listSectionHeader(_ title: String, icon: String?, color: Color) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.caption2.bold()).foregroundStyle(color)
            }
            Text(title).font(.caption.bold()).foregroundStyle(color)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.flaxPurple.opacity(0.07))
                    .frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.flaxPurple.opacity(0.5))
            }
            VStack(spacing: 6) {
                Text(searchText.isEmpty ? "All clear" : "No results for \"\(searchText)\"")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.flaxInk)
                Text(searchText.isEmpty
                     ? "Paste meeting notes or capture your screen to get started"
                     : "Try a different search term")
                    .font(.callout)
                    .foregroundStyle(Color.flaxMuted)
                    .multilineTextAlignment(.center)
            }
            if searchText.isEmpty {
                HStack(spacing: 8) {
                    Button("Paste Notes") { showPasteNotes = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.flaxPurple)
                    Button("Capture Screen") {
                        Task { await appState.captureScreenAndExtract() }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.flaxPurple)
                }
            } else {
                Button("Clear Search") { searchText = "" }
                    .buttonStyle(.bordered).tint(Color.flaxPurple)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
    }

    // MARK: - Computed

    private var contentTitle: String {
        if let p = selectedPerson { return p.name }
        if let m = selectedMeeting { return m }
        switch selectedView {
        case .mine:   return "My Tasks"
        case .people: return "Team"
        case .all:    return "All Items"
        }
    }

    private var contentSubtitle: String? {
        if selectedMeeting != nil { return "Meeting" }
        if selectedView == .people && selectedPerson == nil {
            let n = appState.delegatedItems.count
            return n > 0 ? "\(n) delegated task\(n == 1 ? "" : "s")" : nil
        }
        return nil
    }

    private var displayedItems: [ActionItem] {
        var items: [ActionItem]
        if let p = selectedPerson {
            items = appState.actionItems.filter { $0.assignedTo?.name == p.name }
        } else if let m = selectedMeeting {
            items = appState.actionItems.filter { $0.meetingTitle == m }
        } else {
            switch selectedView {
            case .mine:   items = appState.myItems
            case .people: items = appState.actionItems.filter { $0.assignedTo != nil }
            case .all:    items = appState.actionItems
            }
        }
        if !showCompleted { items = items.filter { $0.status != .done } }
        if !searchText.isEmpty {
            items = items.filter {
                $0.task.localizedCaseInsensitiveContains(searchText)
                || $0.sourceDetail.localizedCaseInsensitiveContains(searchText)
                || ($0.assignedTo?.name.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return items
    }

    private func filterItems(_ items: [ActionItem]) -> [ActionItem] {
        var result = showCompleted ? items : items.filter { $0.status != .done }
        if !searchText.isEmpty {
            result = result.filter { $0.task.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    private func groupedItems(_ items: [ActionItem]) -> [(String, [ActionItem])] {
        let fmt = DateFormatter(); fmt.dateStyle = .medium
        let grouped = Dictionary(grouping: items) { fmt.string(from: $0.createdAt) }
        return grouped.sorted {
            ($0.value.first?.createdAt ?? .distantPast) > ($1.value.first?.createdAt ?? .distantPast)
        }
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let icon: String
    let label: String
    let count: Int
    let isSelected: Bool
    var color: Color = Color.flaxPurple
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? color : Color.flaxMuted)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.flaxInk : Color.flaxMuted)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(isSelected ? color.opacity(0.15) : Color.secondary.opacity(0.09))
                        .foregroundStyle(isSelected ? color : Color.flaxMuted)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? color.opacity(0.09) : isHovered ? Color.flaxPurple.opacity(0.04) : Color.clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Sidebar Person Row

struct SidebarPersonRow: View {
    let person: Person
    let overdueCount: Int
    let taskCount: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                PersonAvatar(name: person.name, size: 20, isAlert: overdueCount > 0)
                Text(person.name)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.flaxInk : Color.flaxMuted)
                    .lineLimit(1)
                Spacer()
                if overdueCount > 0 {
                    Text("\(overdueCount)!")
                        .font(.caption2.bold()).foregroundStyle(.red)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.red.opacity(0.12)).clipShape(Capsule())
                } else if taskCount > 0 {
                    Text("\(taskCount)")
                        .font(.caption2).foregroundStyle(Color.flaxMuted)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.09)).clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.flaxPurple.opacity(0.09) : isHovered ? Color.flaxPurple.opacity(0.04) : Color.clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Person Section (team view)

struct PersonSection: View {
    @EnvironmentObject var appState: AppState
    let person: Person
    let items: [ActionItem]

    var overdueCount: Int { items.filter { $0.urgency == .overdue }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PersonAvatar(name: person.name, size: 30, isAlert: overdueCount > 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.flaxInk)
                    if let email = person.email {
                        Text(email).font(.caption2).foregroundStyle(Color.flaxMuted)
                    }
                }
                Spacer()
                if overdueCount > 0 {
                    Label("\(overdueCount) overdue", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.bold()).foregroundStyle(.red)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red.opacity(0.09)).clipShape(Capsule())
                } else {
                    Text("\(items.count) task\(items.count == 1 ? "" : "s")")
                        .font(.caption2).foregroundStyle(Color.flaxMuted)
                }
            }
            .padding(.horizontal, 14)

            VStack(spacing: 6) {
                ForEach(items) { item in
                    ActionItemRow(item: item).environmentObject(appState)
                }
            }
        }
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.flaxPurple.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - Action Item Row

struct ActionItemRow: View {
    @EnvironmentObject var appState: AppState
    let item: ActionItem
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editTask = ""
    @State private var editDeadline = ""
    @State private var showDraft = false

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isEditing ? Color.flaxPurple : item.source.color)
                .frame(width: 3)
                .padding(.vertical, 8)

            HStack(alignment: .top, spacing: 11) {
                Menu {
                    ForEach(ItemStatus.allCases, id: \.self) { s in
                        Button { appState.updateStatus(item, status: s) } label: {
                            Label(s.displayName, systemImage: s.icon)
                        }
                    }
                } label: {
                    Image(systemName: item.status.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(item.status.color)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
                .padding(.top, 1)

                if isEditing { editingView } else { displayView }

                Spacer(minLength: 0)

                if isHovered && !isEditing { hoverActions }
            }
            .padding(.leading, 11)
            .padding(.trailing, 13)
            .padding(.vertical, 9)
        }
        .background(rowBackground)
        .overlay(rowBorder)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .sheet(isPresented: $showDraft) {
            if let draft = item.aiDraft {
                AIDraftView(draft: draft, item: item).environmentObject(appState)
            }
        }
    }

    private var displayView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let to = item.assignedTo {
                AssigneeChip(name: to.name, isCurrentUser: to.isCurrentUser)
            }
            Text(item.task)
                .font(.body)
                .strikethrough(item.status == .done, color: .secondary)
                .foregroundStyle(item.status == .done ? Color.flaxMuted.opacity(0.7) : Color.flaxInk)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Label(item.source.displayName, systemImage: item.source.icon)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(item.source.color.opacity(0.09))
                    .foregroundStyle(item.source.color)
                    .clipShape(Capsule())

                if let title = item.meetingTitle {
                    Text(title).font(.caption2).foregroundStyle(Color.flaxMuted).lineLimit(1)
                } else if !item.sourceDetail.isEmpty {
                    Text(item.sourceDetail).font(.caption2).foregroundStyle(Color.flaxMuted).lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                if let text = item.deadlineDisplayText {
                    DeadlineBadge(text: text, urgency: item.urgency)
                }
                StatusBadge(status: item.status)
                Spacer()
                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(Color.flaxMuted)
            }

            if item.aiDraft != nil {
                Button { showDraft = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.caption2)
                        Text("View Flaxie Draft").font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(Color.flaxPurple)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var editingView: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField("Task", text: $editTask, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(Color.flaxInk)
                .lineLimit(1...4)
                .onSubmit { saveEdit() }

            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.caption).foregroundStyle(Color.flaxMuted)
                TextField("Deadline (e.g. tomorrow, Friday 3pm)", text: $editDeadline)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.flaxMuted)
                    .onSubmit { saveEdit() }
            }

            HStack(spacing: 8) {
                Button("Save") { saveEdit() }
                    .buttonStyle(.borderedProminent).controlSize(.mini).tint(Color.flaxPurple)
                Button("Cancel") { isEditing = false }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 5) {
            if item.aiDraft == nil {
                IconButton(icon: "sparkles", tint: Color.flaxPurple) {
                    Task { await appState.draftWithFlaxie(item: item, type: .email) }
                }
                .help("Draft with Flaxie")
            }
            IconButton(icon: "pencil", tint: Color.flaxMuted) {
                editTask = item.task; editDeadline = item.deadline ?? ""; isEditing = true
            }
            .help("Edit")
            IconButton(icon: "trash", tint: Color.flaxMuted) { appState.delete(item) }
                .help("Delete")
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(isEditing
                  ? Color.flaxPurple.opacity(0.04)
                  : item.urgency == .overdue && item.status != .done
                    ? Color.red.opacity(0.03)
                    : Color.white.opacity(isHovered ? 0.85 : 0.55))
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 9)
            .stroke(
                isEditing ? Color.flaxPurple.opacity(0.3)
                : item.urgency == .overdue && item.status != .done ? Color.red.opacity(0.15)
                : Color.flaxPurple.opacity(isHovered ? 0.12 : 0.06),
                lineWidth: 1
            )
    }

    private func saveEdit() {
        let t = editTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { isEditing = false; return }
        let d = editDeadline.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.updateItem(item, newTask: t, newDeadline: d.isEmpty ? nil : d)
        isEditing = false
    }
}

// MARK: - Assignee Chip

struct AssigneeChip: View {
    let name: String
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 4) {
            PersonAvatar(name: name, size: 14)
            Text(isCurrentUser ? "You" : name)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background((isCurrentUser ? Color.flaxPurple : Color.secondary).opacity(0.09))
        .foregroundStyle(isCurrentUser ? Color.flaxPurple : Color.flaxMuted)
        .clipShape(Capsule())
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(isHovered ? tint : tint.opacity(0.45))
                .frame(width: 24, height: 24)
                .background(isHovered ? tint.opacity(0.09) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: ItemStatus
    var body: some View {
        if status != .todo {
            HStack(spacing: 3) {
                Image(systemName: status.icon).font(.caption2)
                Text(status.displayName).font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(status.color.opacity(0.11))
            .foregroundStyle(status.color)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Deadline Badge

struct DeadlineBadge: View {
    let text: String
    let urgency: DeadlineUrgency

    var body: some View {
        if urgency == .none {
            Text(text).font(.caption2).foregroundStyle(Color.flaxMuted)
        } else {
            HStack(spacing: 3) {
                if !urgency.icon.isEmpty {
                    Image(systemName: urgency.icon).font(.caption2)
                }
                Text(text).font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(urgency == .overdue ? urgency.color : urgency.color.opacity(0.11))
            .foregroundStyle(urgency == .overdue ? .white : urgency.color)
            .clipShape(Capsule())
        }
    }
}

// MARK: - AI Draft View

struct AIDraftView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let draft: String
    let item: ActionItem
    @State private var editedDraft: String

    init(draft: String, item: ActionItem) {
        self.draft = draft
        self.item = item
        _editedDraft = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.flaxPurple)
                        .frame(width: 32, height: 32)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Flaxie Draft").font(.headline).foregroundStyle(Color.flaxInk)
                    Text(item.task).font(.caption).foregroundStyle(Color.flaxMuted).lineLimit(1)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent).tint(Color.flaxPurple)
            }
            .padding(18)

            Divider().overlay(Color.flaxPurple.opacity(0.09))

            TextEditor(text: $editedDraft)
                .font(.body)
                .foregroundStyle(Color.flaxInk)
                .scrollContentBackground(.hidden)
                .background(Color.flaxCream)
                .padding(14)
                .frame(minHeight: 200)

            Divider().overlay(Color.flaxPurple.opacity(0.09))

            HStack(spacing: 10) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(editedDraft, forType: .string)
                } label: {
                    Label("Copy to clipboard", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered).tint(Color.flaxPurple)
                Spacer()
            }
            .padding(14)
        }
        .frame(width: 520)
        .background(Color.flaxCream)
    }
}
