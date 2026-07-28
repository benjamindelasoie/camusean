import SwiftUI

struct SettingsView: View {
    @AppStorage("sourceLanguageLocale") private var sourceLanguageLocale = "fr-FR"
    @AppStorage("sourceLanguageName") private var sourceLanguageName = "French"
    @AppStorage("targetLanguageName") private var targetLanguageName = "English"
    @AppStorage("showSessionDebugOverlay") private var showSessionDebugOverlay = false
    @AppStorage("wordCorrectionEnabled") private var wordCorrectionEnabled = true

    @State private var apiKey = ""
    /// Whether the Keychain already holds a key — tracked separately because the masked
    /// `apiKey` string is not visible in a SecureField (see `apiKeySection`).
    @State private var hasStoredKey = false
    @State private var showAPIKey = false
    @State private var saveMessage = ""
    @State private var saveSuccess = false
    @State private var showVoiceSheet = false

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
        } header: {
            Text("Language")
        } footer: {
            Text("Words spoken in this language will be transcribed and defined in English.")
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
                            .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.40))
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
            // SwiftUI's SecureField does not render text it was given programmatically, so a
            // stored key shows as a completely blank box — indistinguishable from "no key set".
            // That matters beyond tidiness: App Review is told the dictionary is pre-configured,
            // and a reviewer who opens Settings to an empty key field may reasonably conclude it
            // is not, which is a Guideline 2.1 conversation nobody wants. State it in words.
            if hasStoredKey {
                Label("A key is already set up", systemImage: "checkmark.seal.fill")
                    .font(.callout)
                    .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.40))
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
                    .foregroundStyle(saveSuccess ? Color(red: 0.18, green: 0.62, blue: 0.40) : .red)
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
            let stored = KeychainService.loadAPIKey()
            hasStoredKey = !(stored ?? "").isEmpty
            apiKey = stored.map {
                String(repeating: "•", count: min($0.count, 20))
            } ?? ""
        }
    }

    // MARK: - About Section

    // App Review guideline 5.1.2 expects the privacy policy to be reachable from inside the
    // app, not just from the App Store listing. Pushed rather than linked out so it still
    // works with no network.
    private var aboutSection: some View {
        Section {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
        } header: {
            Text("About")
        } footer: {
            Text("Camusean has no account and no cloud sync. Your saved words stay on this iPhone.")
        }
    }

    // MARK: - Developer Section

    private var developerSection: some View {
        Section {
            Toggle(isOn: $showSessionDebugOverlay) {
                Label("Session debug overlay", systemImage: "ladybug")
            }
            Toggle(isOn: $wordCorrectionEnabled) {
                Label("Correct misheard words", systemImage: "wand.and.sparkles")
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Session debug overlay shows a live recognition diagnostics panel on the reading screen. Correct misheard words lets the dictionary fix likely speech-recognition misfires before defining; turn off to keep the exact transcription (misfires are still logged either way).")
        }
    }

    // MARK: - Save

    private func saveKey() {
        do {
            try KeychainService.saveAPIKey(apiKey)
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
