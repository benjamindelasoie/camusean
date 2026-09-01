import Dependencies
import SwiftUI
import SwiftData

// SwiftData models are reference types with live bindings: a TextField bound straight to
// `word.definition` writes through on every keystroke, so Cancel would be a lie. This edits a
// DRAFT and commits only on Save. Blank definitions are rejected — an empty definition is the
// app's "lookup failed" marker, so letting a reader type one would make that state ambiguous.
struct WordDetailSheet: View {
    let word: Word
    @Dependency(\.speechSynthesizer) private var synth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var draftDefinition = ""
    @State private var draftExample = ""
    @State private var saveError: String?

    @ScaledMetric(relativeTo: .largeTitle) private var wordSize: CGFloat = 36

    private var canSave: Bool {
        !draftDefinition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if isEditing { editor } else { reader }
                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    metadata
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancelEditing() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.disabled(!canSave)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Edit") { beginEditing() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        Button { speak() } label: {
            HStack(spacing: 10) {
                Text(word.word)
                    .font(.system(size: wordSize, weight: .bold, design: .serif))
                    .multilineTextAlignment(.leading)
                Image(systemName: "speaker.wave.2")
                    .font(.title3)
                    .foregroundStyle(Color.camuseanText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(word.word)
        .accessibilityHint("Hear it pronounced")
    }

    private var reader: some View {
        VStack(alignment: .leading, spacing: 18) {
            if word.definition.isEmpty {
                Text("Definition unavailable")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Text(word.definition)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
            }
            if !word.exampleSentence.isEmpty {
                Text(word.exampleSentence)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DEFINITION")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.8)
                TextField("What it means", text: $draftDefinition, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("EXAMPLE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.8)
                TextField("A sentence using it", text: $draftExample, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            }
            if !canSave {
                Text("A definition can't be empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let bookTitle = word.book?.title {
                metadataRow(icon: "book.closed", text: "From \(bookTitle)")
            }
            if let next = word.nextReviewDate {
                metadataRow(icon: "calendar", text: "Next review \(relativeDate(next))")
            } else {
                metadataRow(icon: "sparkles", text: "New — due now")
            }
        }
        .padding(.top, 8)
    }

    private func metadataRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func beginEditing() {
        draftDefinition = word.definition
        draftExample = word.exampleSentence
        saveError = nil
        isEditing = true
    }

    private func cancelEditing() {
        // The model was never touched — nothing to roll back.
        isEditing = false
        saveError = nil
    }

    private func save() {
        let definition = draftDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !definition.isEmpty else { return }
        word.definition = definition
        word.exampleSentence = draftExample.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try modelContext.save()
            isEditing = false
            saveError = nil
        } catch {
            // A silent `try?` here would lose a correction the reader just typed.
            saveError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func speak() {
        let locale = ReadingLanguage.locale(forName: word.sourceLanguage)
        let speaker = synth
        Task { @MainActor in
            await AudioSessionManager.shared.performPlayback {
                await speaker.speak(word.word, locale)
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
