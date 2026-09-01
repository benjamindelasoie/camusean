import Dependencies
import SwiftUI

struct SettingsView: View {
    @Dependency(\.apiKeyStore) private var apiKeyStore

    @AppStorage("sourceLanguageLocale") private var sourceLanguageLocale = "fr-FR"
    @AppStorage("sourceLanguageName") private var sourceLanguageName = "French"
    @AppStorage("targetLanguageName") private var targetLanguageName = "English"
    @AppStorage("showSessionDebugOverlay") private var showSessionDebugOverlay = false
    @AppStorage("wordCorrectionEnabled") private var wordCorrectionEnabled = true
    @AppStorage("autoSpeakOnReveal") private var autoSpeakOnReveal = false

    @State private var apiKey = ""
    /// Tracked separately because a SecureField won't render the masked `apiKey`
    /// (see `apiKeySection`).
    @State private var hasStoredKey = false
    @State private var showAPIKey = false
    @State private var saveMessage = ""
    @State private var saveSuccess = false
    @State private var showVoiceSheet = false
    /// Diagnostics stay hidden until the version row is tapped seven times.
    @State private var showDeveloperSection = false
    @State private var versionTapCount = 0

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                voiceSection
                apiKeySection
                aboutSection
                developerSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showVoiceSheet) {
                VoiceSetupSheet(languages: VoiceSetup.relevantLanguages()) {
                    showVoiceSheet = false
                }
            }
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        Section {
            Picker(selection: $sourceLanguageLocale) {
                ForEach(ReadingLanguage.all) { option in
                    HStack(spacing: 10) {
                        Text(option.flag)
                        Text(option.name)
                    }
                    .tag(option.locale)
                }
            } label: {
                Label("Reading language", systemImage: "globe")
            }
            .onChange(of: sourceLanguageLocale) { _, newLocale in
                sourceLanguageName = ReadingLanguage.named(locale: newLocale).name
            }

            // A reading preference, not a diagnostic — it changes which word gets defined.
            Toggle(isOn: $wordCorrectionEnabled) {
                Label("Correct misheard words", systemImage: "wand.and.sparkles")
            }

            // Off by default: a phone that starts talking the instant you flip a card isn't
            // something to opt people into silently.
            Toggle(isOn: $autoSpeakOnReveal) {
                Label("Speak words on reveal", systemImage: "speaker.wave.2")
            }
        } header: {
            Text("Language")
        } footer: {
            Text("Words spoken in this language will be transcribed and defined in English. "
                 + "Correcting misheard words lets the dictionary fix likely speech-recognition "
                 + "misfires before defining; turn it off to keep the exact transcription. "
                 + "Speaking on reveal plays the word aloud when you flip a flashcard \u{2014} you can "
                 + "always tap a word to hear it.")
        }
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        Section {
            ForEach(VoiceSetup.relevantLanguages()) { lang in
                HStack(spacing: 10) {
                    Text(lang.flag)
                    Text(lang.name)
                    Spacer()
                    if TTSService.hasEnhancedVoice(forLanguagePrefix: lang.prefix) {
                        Label("Enhanced", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.camuseanSuccess)
                    } else {
                        Text("Default")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                showVoiceSheet = true
            } label: {
                Label("How to download enhanced voices", systemImage: "speaker.wave.2")
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("Enhanced voices sound far better than the robotic default. You download them once in iOS Settings.")
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        Section {
            // SecureField won't render a programmatically set value, so a stored key looks like
            // a blank box — "no key set". App Review is told the dictionary is pre-configured, so
            // an empty-looking field risks a Guideline 2.1 rejection. State it in words.
            if hasStoredKey {
                Label("A key is already set up", systemImage: "checkmark.seal.fill")
                    .font(.callout)
                    .foregroundStyle(Color.camuseanSuccess)
            }

            HStack {
                Label {
                    if showAPIKey {
                        TextField("sk-ant-…", text: $apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("sk-ant-…", text: $apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                    }
                } icon: {
                    Image(systemName: "key.horizontal")
                }

                Button {
                    showAPIKey.toggle()
                } label: {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                saveKey()
            } label: {
                Label("Save key", systemImage: "checkmark.circle")
            }
            .disabled(apiKey.isEmpty)

            if !saveMessage.isEmpty {
                Label(saveMessage, systemImage: saveSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(saveSuccess ? Color.camuseanSuccess : .red)
            }
        } header: {
            Text("Anthropic API Key")
        } footer: {
            Link(destination: URL(string: "https://console.anthropic.com")!) {
                HStack(spacing: 4) {
                    Text("Get an API key at console.anthropic.com")
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                }
                .font(.caption)
            }
        }
        .onAppear {
            let stored = apiKeyStore.load()
            hasStoredKey = !(stored ?? "").isEmpty
            apiKey = stored.map {
                String(repeating: "•", count: min($0.count, 20))
            } ?? ""
        }
    }

    // MARK: - About Section

    // App Review guideline 5.1.2 expects the privacy policy reachable inside the app, not just
    // the App Store listing. Pushed, not linked out, so it works with no network.
    private var aboutSection: some View {
        Section {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            // Seven taps reveal Diagnostics: the overlay must stay reachable in Release to debug
            // TestFlight builds, but a reader shouldn't meet a "Developer" section by accident.
            Button {
                versionTapCount += 1
                if versionTapCount >= 7 { showDeveloperSection = true }
            } label: {
                LabeledContent("Version", value: appVersion)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Tap seven times to show diagnostics")
        } header: {
            Text("About")
        } footer: {
            Text("Camusean has no account and no cloud sync. Your saved words stay on this iPhone.")
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    // MARK: - Diagnostics Section

    @ViewBuilder
    private var developerSection: some View {
        if showDeveloperSection {
            Section {
                Toggle(isOn: $showSessionDebugOverlay) {
                    Label("Session debug overlay", systemImage: "ladybug")
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Shows a live recognition diagnostics panel on the reading screen.")
            }
        }
    }

    // MARK: - Save

    private func saveKey() {
        do {
            try apiKeyStore.save(apiKey)
            saveMessage = "Key saved"
            saveSuccess = true
            hasStoredKey = true
            apiKey = String(repeating: "•", count: min(apiKey.count, 20))
            showAPIKey = false
        } catch {
            saveMessage = "Failed to save key"
            saveSuccess = false
        }
    }
}

#Preview {
    SettingsView()
}
