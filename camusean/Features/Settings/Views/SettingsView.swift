import SwiftUI

struct SettingsView: View {
    @AppStorage("sourceLanguageLocale") private var sourceLanguageLocale = "fr-FR"
    @AppStorage("sourceLanguageName") private var sourceLanguageName = "French"
    @AppStorage("targetLanguageName") private var targetLanguageName = "English"

    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var saveMessage = ""

    private let languageOptions: [(name: String, locale: String)] = [
        ("French", "fr-FR"),
        ("Spanish", "es-ES"),
        ("Italian", "it-IT"),
        ("German", "de-DE"),
        ("Portuguese", "pt-PT"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading Language") {
                    Picker("Language", selection: $sourceLanguageLocale) {
                        ForEach(languageOptions, id: \.locale) { option in
                            Text(option.name).tag(option.locale)
                        }
                    }
                    .onChange(of: sourceLanguageLocale) { _, newLocale in
                        sourceLanguageName = languageOptions.first { $0.locale == newLocale }?.name ?? "French"
                    }
                    Text("Words in this language will be transcribed and defined in English.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Anthropic API Key") {
                    HStack {
                        if showAPIKey {
                            TextField("sk-ant-...", text: $apiKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("sk-ant-...", text: $apiKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Save Key") {
                        saveKey()
                    }
                    .disabled(apiKey.isEmpty)
                    if !saveMessage.isEmpty {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundStyle(saveMessage.contains("saved") ? .green : .red)
                    }
                    Link("Get an API key at anthropic.com", destination: URL(string: "https://console.anthropic.com")!)
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                apiKey = KeychainService.loadAPIKey().map { String(repeating: "•", count: min($0.count, 20)) } ?? ""
            }
        }
    }

    private func saveKey() {
        do {
            try KeychainService.saveAPIKey(apiKey)
            saveMessage = "Key saved"
            apiKey = String(repeating: "•", count: min(apiKey.count, 20))
            showAPIKey = false
        } catch {
            saveMessage = "Failed to save key"
        }
    }
}

#Preview {
    SettingsView()
}
