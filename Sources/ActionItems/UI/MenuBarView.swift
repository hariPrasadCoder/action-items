import SwiftUI

// MARK: - Brand colors + typography

extension Color {
    static let flaxCream   = Color(red: 0.961, green: 0.941, blue: 0.910)  // #F5F0E8
    static let flaxPurple  = Color(red: 0.353, green: 0.325, blue: 0.882)  // #5A53E1
    static let flaxInk     = Color(red: 0.102, green: 0.102, blue: 0.102)  // #1A1A1A
    static let flaxMuted   = Color(red: 0.45,  green: 0.44,  blue: 0.50)
    static let flaxSurface = Color(red: 0.98,  green: 0.97,  blue: 0.96)   // slightly warmer white
}

// MARK: - MenuBarView

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showPasteNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let note = appState.notification { notificationBanner(note) }
            quickActions
            dividerLine
            itemsSections
            dividerLine
            footer
        }
        .frame(width: 390)
        .background(Color.flaxCream)
        .sheet(isPresented: $showPasteNotes) {
            PasteNotesView().environmentObject(appState)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            // Logo mark
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.flaxPurple)
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Flaxie")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.flaxInk)

                statusLine
            }

            Spacer()

            alertBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var statusLine: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(appState.overdueCount > 0 ? Color.red : Color.green)
                .frame(width: 5, height: 5)

            if appState.overdueCount > 0 {
                Text("\(appState.overdueCount) overdue · \(appState.pendingCount) pending")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if appState.pendingCount > 0 {
                Text("\(appState.pendingCount) open")
                    .font(.caption)
                    .foregroundStyle(Color.flaxMuted)
            } else {
                Text("All clear")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var alertBadge: some View {
        if appState.overdueCount > 0 {
            Text("\(appState.overdueCount)")
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        } else if appState.pendingCount > 0 {
            Text("\(appState.pendingCount)")
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.flaxPurple.opacity(0.12))
                .foregroundStyle(Color.flaxPurple)
                .clipShape(Capsule())
        }
    }

    // MARK: Notification Banner

    private func notificationBanner(_ note: String) -> some View {
        let isError = note.lowercased().hasPrefix("error")
        return HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "sparkles")
                .font(.caption)
                .foregroundStyle(isError ? .red : Color.flaxPurple)
            Text(note)
                .font(.caption)
                .foregroundStyle(isError ? .red : Color.flaxInk)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isError ? Color.red.opacity(0.07) : Color.flaxPurple.opacity(0.07))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Quick Actions

    private var quickActions: some View {
        VStack(spacing: 2) {
            FlaxQuickAction(
                icon: "square.and.pencil",
                label: "Paste Meeting Notes",
                shortcut: "⌘⇧N",
                tint: Color.flaxPurple
            ) { showPasteNotes = true }

            FlaxQuickAction(
                icon: "camera.viewfinder",
                label: "Capture Screen",
                shortcut: "⌘⇧A",
                tint: .indigo,
                loading: appState.isExtracting
            ) { Task { await appState.captureScreenAndExtract() } }

            FlaxQuickAction(
                icon: appState.gmail.isConnected ? "envelope.badge.fill" : "envelope",
                label: appState.gmail.isConnected ? "Sync Gmail" : "Connect Gmail",
                shortcut: nil,
                tint: .orange
            ) {
                if appState.gmail.isConnected {
                    Task { await appState.syncGmailFromPopover() }
                } else {
                    (NSApp.delegate as? AppDelegate)?.popover?.performClose(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        appState.gmail.startOAuthFlow()
                    }
                }
            }

            // Integration status strip
            integrationStatusStrip
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var integrationStatusStrip: some View {
        if appState.granola.isWatching {
            HStack(spacing: 6) {
                Circle().fill(Color.flaxPurple).frame(width: 5, height: 5)
                Text("Granola connected")
                    .font(.caption2)
                    .foregroundStyle(Color.flaxMuted)
                Spacer()
                if let d = appState.granola.lastSyncDate {
                    Text(d.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(Color.flaxMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
    }

    // MARK: Items

    private var itemsSections: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                mineSection
                if !appState.delegatedItems.isEmpty { delegatedSection }
                if appState.myItems.isEmpty && appState.delegatedItems.isEmpty { emptyState }
            }
            .padding(.bottom, 8)
        }
        .frame(maxHeight: 270)
    }

    private var mineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("MINE TODAY", color: Color.flaxPurple)

            if appState.myItems.isEmpty {
                Text("Nothing on your plate")
                    .font(.caption)
                    .foregroundStyle(Color.flaxMuted)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            } else {
                ForEach(appState.myItems.prefix(8)) { item in
                    MiniItemRow(item: item).environmentObject(appState)
                }
                if appState.myItems.count > 8 {
                    Button {
                        (NSApp.delegate as? AppDelegate)?.openDashboardFromPopover()
                    } label: {
                        Text("+ \(appState.myItems.count - 8) more — Open War Room")
                            .font(.caption2)
                            .foregroundStyle(Color.flaxPurple)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private var delegatedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            dividerLine.padding(.vertical, 4)
            sectionHeader("WAITING ON", color: .orange)

            ForEach(appState.delegatedByAssignee.prefix(3), id: \.0.name) { person, items in
                DelegatedPersonRow(person: person, items: items)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 22))
                .foregroundStyle(Color.flaxPurple.opacity(0.5))
            Text("All clear — Flaxie is watching")
                .font(.caption)
                .foregroundStyle(Color.flaxMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("War Room") {
                (NSApp.delegate as? AppDelegate)?.openDashboardFromPopover()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.flaxPurple)

            Spacer()

            Button("Settings") {
                (NSApp.delegate as? AppDelegate)?.openSettingsFromPopover()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.flaxMuted)

            Text("·").foregroundStyle(Color.flaxMuted).font(.caption)

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.flaxMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Helpers

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.flaxPurple.opacity(0.09))
            .frame(height: 1)
    }

    private func sectionHeader(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(color.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 5)
    }
}

// MARK: - Mini Item Row

struct MiniItemRow: View {
    @EnvironmentObject var appState: AppState
    let item: ActionItem

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            // Status toggle
            Button { appState.toggle(item) } label: {
                Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.status == .done ? Color.flaxPurple : Color.flaxMuted.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.task)
                    .font(.callout)
                    .lineLimit(2)
                    .strikethrough(item.status == .done, color: .secondary)
                    .foregroundStyle(item.status == .done ? Color.flaxMuted : Color.flaxInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: item.source.icon)
                        .font(.caption2)
                        .foregroundStyle(item.source.color)

                    if let text = item.deadlineDisplayText {
                        Text(text)
                            .font(.caption2)
                            .foregroundStyle(item.urgency == .none ? Color.flaxMuted : item.urgency.color)
                    } else if !item.sourceDetail.isEmpty {
                        Text(item.sourceDetail)
                            .font(.caption2)
                            .foregroundStyle(Color.flaxMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
            StatusPill(status: item.status)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            item.urgency == .overdue && item.status != .done
                ? Color.red.opacity(0.04) : Color.clear
        )
    }
}

// MARK: - Delegated Person Row

struct DelegatedPersonRow: View {
    let person: Person
    let items: [ActionItem]

    var overdue: Int { items.filter { $0.urgency == .overdue }.count }

    var body: some View {
        HStack(spacing: 10) {
            PersonAvatar(name: person.name, size: 28, isAlert: overdue > 0)

            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.flaxInk)
                Text(items.first?.task ?? "")
                    .font(.caption2)
                    .foregroundStyle(Color.flaxMuted)
                    .lineLimit(1)
            }

            Spacer()

            Group {
                if overdue > 0 {
                    Text("\(overdue) overdue")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.red.opacity(0.10))
                        .clipShape(Capsule())
                } else {
                    Text("\(items.count) open")
                        .font(.caption2)
                        .foregroundStyle(Color.flaxMuted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Shared: Person Avatar

struct PersonAvatar: View {
    let name: String
    let size: CGFloat
    var isAlert: Bool = false

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(isAlert ? Color.red.opacity(0.12) : Color.flaxPurple.opacity(0.12))
                .frame(width: size, height: size)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(isAlert ? .red : Color.flaxPurple)
        }
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let status: ItemStatus

    var body: some View {
        if status != .todo {
            Text(status.displayName)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.3)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(status.color.opacity(0.14))
                .foregroundStyle(status.color)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Quick Action Button

struct FlaxQuickAction: View {
    let icon: String
    let label: String
    let shortcut: String?
    let tint: Color
    var loading: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if loading {
                        ProgressView().controlSize(.small).frame(width: 16)
                    } else {
                        Image(systemName: icon)
                            .foregroundStyle(tint)
                            .frame(width: 16)
                    }
                }
                .font(.system(size: 13))

                Text(label)
                    .font(.callout)
                    .foregroundStyle(Color.flaxInk)

                Spacer()

                if let shortcut {
                    Text(shortcut)
                        .font(.caption2)
                        .foregroundStyle(Color.flaxMuted)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovered ? tint.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
