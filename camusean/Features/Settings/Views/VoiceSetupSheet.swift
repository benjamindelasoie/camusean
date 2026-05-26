import SwiftUI

// Explains how to download Apple's Enhanced/Premium voices. There is no public API to
// deep-link to Settings → Accessibility → Spoken Content → Voices (the `prefs:` scheme is
// private and gets apps rejected), so this is instructional. Shared by the first-run
// auto-prompt in ReadingSessionView and the re-openable "Voice" row in Settings.
struct VoiceSetupSheet: View {
    // Languages whose audio quality matters (reading language + English), shown with status.
    let languages: [ReadingLanguage]
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Hear the best voices")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .padding(.top, 12)

            Text("Camusean reads words and definitions out loud. Apple's built-in voice sounds robotic. The Enhanced voices are dramatically better, but you download them once in iOS Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            // Per-language status so the user sees exactly which voice still needs downloading.
            VStack(spacing: 8) {
                ForEach(languages) { lang in
                    HStack(spacing: 10) {
                        Text(lang.flag)
                        Text(lang.name)
                            .font(.callout.weight(.medium))
                        Spacer()
                        statusBadge(for: lang)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.07), in: .rect(cornerRadius: 10))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                instructionRow(number: "1", text: "Open the Settings app.")
                instructionRow(number: "2", text: "Accessibility → Spoken Content → Voices.")
                instructionRow(number: "3", text: "Pick \(languageList).")
                instructionRow(number: "4", text: "Tap the cloud icon next to a voice marked Enhanced or Premium.")
            }
            .padding(.top, 4)

            Spacer()

            Button(action: onDone) {
                Text("Got it")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Color.camusean)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 36)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func statusBadge(for lang: ReadingLanguage) -> some View {
        if TTSService.hasEnhancedVoice(forLanguagePrefix: lang.prefix) {
            Label("Enhanced", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.40))
        } else {
            Label("Default", systemImage: "exclamationmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // "English" / "French and English" / "Spanish, French and English"
    private var languageList: String {
        let names = languages.map(\.name)
        switch names.count {
        case 0: return "your reading language and English"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let head = names.dropLast().joined(separator: ", ")
            let tail = names.last ?? ""
            return "\(head) and \(tail)"
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.camusean)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(3)
        }
    }
}

#Preview {
    VoiceSetupSheet(languages: ReadingLanguage.all.prefix(2).map { $0 }, onDone: {})
}
