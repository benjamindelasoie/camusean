import SwiftUI
import SwiftData

struct ReadingSessionView: View {
    @State private var vm = SessionViewModel()
    @Environment(\.modelContext) private var modelContext
    @State private var isHolding = false

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
            micButton
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
                Text("Hold the button and say a word")
                    .foregroundStyle(.secondary)
            case .listening:
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Listening…")
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
        .padding()
        .frame(minHeight: 120, alignment: .center)
    }

    private var micButton: some View {
        Circle()
            .fill(isHolding ? Color.red : Color.accentColor)
            .frame(width: 100, height: 100)
            .scaleEffect(isHolding ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHolding)
            .overlay {
                Image(systemName: "mic.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isHolding {
                            isHolding = true
                            Task { await vm.onMicPressed() }
                        }
                    }
                    .onEnded { _ in
                        isHolding = false
                        Task { await vm.onMicReleased() }
                    }
            )
            .accessibilityLabel("Hold to listen")
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

#Preview {
    ReadingSessionView()
        .modelContainer(for: Word.self, inMemory: true)
}
