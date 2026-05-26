import SwiftUI

struct SettingsView: View {
    @AppStorage("sourceLanguageLocale") private var sourceLanguageLocale = "fr-FR"
    @AppStorage("sourceLanguageName") private var sourceLanguageName = "French"
    @AppStorage("targetLanguageName") private var targetLanguageName = "English"

    @State private var apiKey = ""
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
            apiKey = KeychainService.loadAPIKey().map {
                String(repeating: "•", count: min($0.count, 20))
            } ?? ""
        }
    }

    // MARK: - Save

    private func saveKey() {
        do {
            try KeychainService.saveAPIKey(apiKey)
            saveMessage = "Key saved"
            saveSuccess = true
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
