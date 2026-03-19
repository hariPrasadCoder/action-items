import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("onboarding_complete") var onboardingComplete = false

    @State private var step = 0
    @State private var name = ""
    @State private var email = ""
    @State private var selectedSource: OnboardingSource = .granola
    @State private var teamAction: TeamAction = .create
    @State private var teamName = ""
    @State private var joinCode = ""
    @State private var isLoading = false
    @State private var errorMessage = ""

    enum OnboardingSource: String, CaseIterable, Identifiable {
        case granola   = "Granola"
        case fireflies = "Fireflies"
        case otter     = "Otter.ai"
        case manual    = "Paste manually"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .granola:   return "note.text"
            case .fireflies: return "waveform.circle.fill"
            case .otter:     return "waveform"
            case .manual:    return "square.and.pencil"
            }
        }
        var detail: String {
            switch self {
            case .granola:   return "Auto-detected from your Mac — no setup needed"
            case .fireflies: return "Add your API key in Settings after setup"
            case .otter:     return "Watches Downloads for .txt exports"
            case .manual:    return "Paste notes anytime with ⌘⇧N"
            }
        }
        var color: Color {
            switch self {
            case .granola:   return .teal
            case .fireflies: return .indigo
            case .otter:     return .blue
            case .manual:    return Color.flaxPurple
            }
        }
    }

    enum TeamAction { case create, join, skip }

    var body: some View {
        ZStack {
            Color.flaxCream.ignoresSafeArea()

            VStack(spacing: 0) {
                onboardingHeader
                progressDots
                    .padding(.bottom, 28)

                Group {
                    switch step {
                    case 0:  profileStep
                    case 1:  sourceStep
                    case 2:  slackStep
                    case 3:  teamStep
                    default: profileStep
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 44)
                .animation(.easeInOut(duration: 0.25), value: step)

                Spacer()

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 44)
                }

                navButtons
            }
        }
        .frame(width: 500, height: 580)
    }

    // MARK: - Header

    private var onboardingHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.flaxPurple)
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.flaxPurple.opacity(0.35), radius: 10, y: 4)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 36)

            Text("Welcome to Flaxie")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Color.flaxInk)

            Text(stepSubtitle)
                .font(.callout)
                .foregroundStyle(Color.flaxMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
                .padding(.bottom, 8)
        }
    }

    private var stepSubtitle: String {
        switch step {
        case 0:  return "Let's get to know you"
        case 1:  return "Where do your meeting notes come from?"
        case 2:  return "Connect Slack to nudge teammates automatically"
        case 3:  return "Collaborate with your team"
        default: return ""
        }
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Color.flaxPurple : Color.flaxPurple.opacity(0.18))
                    .frame(width: i == step ? 18 : 7, height: 7)
                    .animation(.spring(response: 0.3), value: step)
            }
        }
    }

    // MARK: - Step 0: Profile

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepLabel("1 of 4 · Your profile")

            VStack(spacing: 14) {
                FlaxField(label: "Your name", placeholder: "e.g. Hari Prasad", text: $name)
                FlaxField(label: "Work email (optional)", placeholder: "you@company.com", text: $email)
            }

            Text("Flaxie uses your name to figure out which tasks are yours vs. delegated to teammates.")
                .font(.caption)
                .foregroundStyle(Color.flaxMuted)
        }
    }

    // MARK: - Step 1: Source

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepLabel("2 of 4 · Meeting notes source")

            VStack(spacing: 8) {
                ForEach(OnboardingSource.allCases) { source in
                    SourceCard(
                        source: source,
                        isSelected: selectedSource == source
                    ) { selectedSource = source }
                }
            }
        }
    }

    // MARK: - Step 2: Slack

    private var slackStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepLabel("3 of 4 · Slack (optional)")

            VStack(spacing: 14) {
                // Connect via OAuth
                Button {
                    FlaxieAPIClient.shared.connectSlack()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.white)
                        Text("Connect Slack")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color(red: 0.27, green: 0.20, blue: 0.40))  // Slack purple
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Rectangle().fill(Color.flaxPurple.opacity(0.15)).frame(height: 1)
                    Text("or").font(.caption2).foregroundStyle(Color.flaxMuted)
                    Rectangle().fill(Color.flaxPurple.opacity(0.15)).frame(height: 1)
                }

                Text("Skip for now — you can connect Slack anytime in Settings.")
                    .font(.caption)
                    .foregroundStyle(Color.flaxMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            FeatureRow(icon: "bubble.left.and.bubble.right.fill", color: .indigo,
                       text: "Flaxie sends nudges via DM so you never have to chase anyone")
            FeatureRow(icon: "person.crop.circle.badge.checkmark", color: .green,
                       text: "Team members are matched by email — no extra setup needed")
        }
    }

    // MARK: - Step 3: Team

    private var teamStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepLabel("4 of 4 · Your team")

            // Toggle
            HStack(spacing: 0) {
                teamToggleButton("Create team", selected: teamAction == .create) { teamAction = .create }
                teamToggleButton("Join team", selected: teamAction == .join) { teamAction = .join }
                teamToggleButton("Solo", selected: teamAction == .skip) { teamAction = .skip }
            }
            .background(Color.flaxPurple.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 9))

            switch teamAction {
            case .create:
                FlaxField(label: "Team name", placeholder: "e.g. Product Squad", text: $teamName)
            case .join:
                FlaxField(label: "Join code", placeholder: "ABC123", text: $joinCode)
                    .onChange(of: joinCode) { _, v in joinCode = v.uppercased() }
            case .skip:
                VStack(spacing: 8) {
                    FeatureRow(icon: "checkmark.circle.fill", color: .green, text: "You're all set! Add teammates later in Settings.")
                    FeatureRow(icon: "info.circle", color: Color.flaxPurple, text: "Team features unlock real-time sync and Slack nudges.")
                }
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
    }

    // MARK: - Nav Buttons

    private var navButtons: some View {
        HStack {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Color.flaxMuted)
            }
            Spacer()

            if step < 3 {
                Button("Continue") { withAnimation { advance() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.flaxPurple)
                    .disabled(!canAdvance)
            } else {
                Button("Get started →") { finish() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.flaxPurple)
                    .disabled(isLoading)
            }
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 24)
    }

    private var canAdvance: Bool {
        step == 0 ? !name.trimmingCharacters(in: .whitespaces).isEmpty : true
    }

    // MARK: - Logic

    private func advance() {
        if step == 0 {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            appState.currentUser = Person(
                name: trimmed,
                email: email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email.trimmingCharacters(in: .whitespaces),
                isCurrentUser: true
            )
            appState.saveCurrentUser()

            // Register early so userId is available before the Slack connect step
            Task {
                let deviceId = getOrCreateDeviceId()
                _ = try? await FlaxieAPIClient.shared.register(
                    deviceId: deviceId,
                    name: trimmed,
                    email: appState.currentUser.email
                )
            }
        }
        errorMessage = ""
        step += 1
    }

    private func finish() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = ""

        Task {
            // Register device with backend
            let deviceId = getOrCreateDeviceId()
            do {
                _ = try await FlaxieAPIClient.shared.register(
                    deviceId: deviceId,
                    name: appState.currentUser.name,
                    email: appState.currentUser.email
                )

                // Handle team creation / joining
                if teamAction == .create && !teamName.isEmpty {
                    _ = try? await FlaxieAPIClient.shared.createTeam(name: teamName)
                } else if teamAction == .join && !joinCode.isEmpty {
                    _ = try? await FlaxieAPIClient.shared.joinTeam(joinCode: joinCode)
                }

                await MainActor.run {
                    isLoading = false
                    onboardingComplete = true
                    (NSApp.delegate as? AppDelegate)?.onboardingWindow?.close()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func getOrCreateDeviceId() -> String {
        let key = "flaxie_device_id"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    // MARK: - Helpers

    private func stepLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Color.flaxPurple.opacity(0.6))
    }

    private func teamToggleButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.flaxPurple : Color.flaxMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? Color.flaxPurple.opacity(0.13) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Source Card

struct SourceCard: View {
    let source: OnboardingView.OnboardingSource
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(source.color.opacity(isSelected ? 0.15 : 0.07))
                        .frame(width: 36, height: 36)
                    Image(systemName: source.icon)
                        .foregroundStyle(source.color)
                        .font(.system(size: 14))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.rawValue)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.flaxInk)
                    Text(source.detail)
                        .font(.caption)
                        .foregroundStyle(Color.flaxMuted)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.flaxPurple)
                        .font(.system(size: 16))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? Color.flaxPurple.opacity(0.06)
                          : isHovered ? Color.secondary.opacity(0.05) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.flaxPurple.opacity(0.35) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 13))
                .frame(width: 18)
                .padding(.top, 1)
            Text(text)
                .font(.callout)
                .foregroundStyle(Color.flaxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Flax Field

struct FlaxField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.flaxMuted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.flaxPurple.opacity(0.18), lineWidth: 1)
                )
        }
    }
}
