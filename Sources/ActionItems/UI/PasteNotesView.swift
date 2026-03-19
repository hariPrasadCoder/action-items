import SwiftUI

struct PasteNotesView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var notesText = ""
    @State private var meetingTitle = ""
    @State private var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.flaxPurple).frame(width: 28, height: 28)
                    Text("F").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Paste Meeting Notes")
                        .font(.headline)
                        .foregroundStyle(Color.flaxInk)
                    Text("Flaxie will extract action items and assign them")
                        .font(.caption).foregroundStyle(Color.flaxMuted)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.flaxMuted)
            }
            .padding()
            .background(Color.flaxCream)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                // Meeting title
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meeting Title (optional)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.flaxMuted)
                    TextField("e.g. Founder Sync, Q1 Planning", text: $meetingTitle)
                        .textFieldStyle(.roundedBorder)
                }

                // Notes
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meeting Notes")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.flaxMuted)
                    TextEditor(text: $notesText)
                        .font(.body)
                        .frame(minHeight: 200, maxHeight: 360)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                        .overlay(alignment: .topLeading) {
                            if notesText.isEmpty {
                                Text("Paste notes from Granola, Otter, Fireflies, Google Doc, or any text...")
                                    .font(.body)
                                    .foregroundStyle(Color.flaxMuted.opacity(0.7))
                                    .padding(6)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                // Source picker hint
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Color.flaxMuted).font(.caption)
                    Text("Works with Granola, Fireflies, Otter, Google Docs, or raw transcript text")
                        .font(.caption).foregroundStyle(Color.flaxMuted)
                }
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Extract Action Items") {
                    process()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.flaxPurple)
                .disabled(notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)

                if isProcessing {
                    ProgressView().controlSize(.small)
                }
            }
            .padding()
            .background(Color.flaxCream)
        }
        .frame(width: 520)
        .background(Color.flaxCream)
    }

    private func process() {
        let text = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isProcessing = true
        let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await appState.processManualNotes(text, meetingTitle: title.isEmpty ? nil : title)
            await MainActor.run {
                isProcessing = false
                dismiss()
            }
        }
    }
}
