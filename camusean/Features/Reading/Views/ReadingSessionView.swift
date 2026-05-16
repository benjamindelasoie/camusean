import SwiftUI
import SwiftData

struct ReadingSessionView: View {
    @State private var vm = SessionViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                if !vm.isSessionActive {
                    startScreen
                } else {
                    sessionScreen
                }
            }
            .padding()
            .navigationTitle("Camusean")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $vm.showSummary) {
                summarySheet
            }
            .onAppear { vm.modelContext = modelContext }
        }
    }

    private var startScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "book.fill")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
            Text("Start a reading session to look up words by voice.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if case .error(let msg) = vm.phase {
                Text(msg)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .font(.caption)
            }
            Button {
                Task { await vm.startSession() }
            } label: {
                Label("Start Reading", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Spacer()
        }
    }

    private var sessionScreen: some View {
        VStack(spacing: 24) {
            statusArea
            Spacer()
            listeningIndicator
            Spacer()
            Button("End Session", role: .destructive) {
                vm.endSession()
            }
            .padding(.bottom)
        }
    }

    private var statusArea: some View {
        Group {
            switch vm.phase {
            case .idle:
                Text("Starting…")
                    .foregroundStyle(.secondary)
            case .listening:
                if vm.partialTranscription.isEmpty {
                    Text("Say a word…")
                        .foregroundStyle(.secondary)
                } else {
                    Text(vm.partialTranscription)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .transition(.opacity)
                }
            case .processing(let word):
                VStack(spacing: 8) {
                    Text(word).font(.title).fontWeight(.bold)
                    ProgressView()
                }
            case .result(let word, let definition):
                VStack(spacing: 8) {
                    Text(word).font(.title).fontWeight(.bold)
                    Text(definition)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            case .error(let msg):
                Text(msg)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .font(.callout)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.partialTranscription)
        .padding()
        .frame(minHeight: 120, alignment: .center)
    }

    private var listeningIndicator: some View {
        PulsingListeningView(isListening: {
            if case .listening = vm.phase { return true }
            return false
        }())
    }

    private var summarySheet: some View {
        VStack(spacing: 24) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Session complete")
                .font(.title)
                .fontWeight(.bold)
            Text("\(vm.lookupCount) word\(vm.lookupCount == 1 ? "" : "s") looked up")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Done") { vm.showSummary = false }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationDetents([.medium])
    }
}

private struct PulsingListeningView: View {
    let isListening: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.accentColor.opacity(0.3 - Double(i) * 0.08), lineWidth: 1.5)
                    .frame(width: 100 + CGFloat(i) * 32, height: 100 + CGFloat(i) * 32)
                    .scaleEffect(pulse && isListening ? 1.15 : 1.0)
                    .opacity(pulse && isListening ? 0.6 : 0.2)
                    .animation(
                        isListening
                            ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(Double(i) * 0.2)
                            : .default,
                        value: pulse
                    )
            }
            Circle()
                .fill(isListening ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 100, height: 100)
                .animation(.easeInOut(duration: 0.3), value: isListening)
                .overlay {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                }
        }
        .onAppear { pulse = true }
        .onChange(of: isListening) { _, _ in pulse = true }
        .accessibilityLabel(isListening ? "Listening for speech" : "Not listening")
    }
}

#Preview {
    ReadingSessionView()
        .modelContainer(for: Word.self, inMemory: true)
}
