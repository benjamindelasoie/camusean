import SwiftUI
import SwiftData

struct ReadingSessionView: View {
    @State private var vm = SessionViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            if !vm.isSessionActive {
                startScreen
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .scale(scale: 0.96).combined(with: .opacity)
                    ))
            } else {
                sessionScreen
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.03).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: vm.isSessionActive)
        .sheet(isPresented: $vm.showSummary) { summarySheet }
        .onAppear { vm.modelContext = modelContext }
    }

    // MARK: - Start Screen

    private var startScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            heroMark
            Spacer().frame(height: 36)
            heroText
            Spacer()
            startCTA
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 52)
    }

    private var heroMark: some View {
        ZStack {
            Circle()
                .fill(Color.camusean.opacity(0.07))
                .frame(width: 156, height: 156)
            Circle()
                .fill(Color.camusean.opacity(0.11))
                .frame(width: 120, height: 120)
            Image(systemName: "book.pages")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.camusean)
        }
    }

    private var heroText: some View {
        VStack(spacing: 14) {
            Text("Camusean")
                .font(.system(size: 38, weight: .bold, design: .serif))
            Text("Say a word you don't know.\nHear its meaning. Keep reading.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
            if case .error(let msg) = vm.phase {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
        }
    }

    private var startCTA: some View {
        VStack(spacing: 13) {
            Button {
                Task { await vm.startSession() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "waveform")
                    Text("Begin Reading")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.camusean)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 17))
            }
            Text("Requires microphone & speech recognition")
                .font(.caption2)
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }

    // MARK: - Session Screen

    private var sessionScreen: some View {
        VStack(spacing: 0) {
            sessionHeader
                .padding(.horizontal, 28)
                .padding(.top, 20)

            Spacer()

            statusDisplay
                .padding(.horizontal, 36)

            Spacer()

            OrganicMicView(
                isListening: isListening,
                isProcessing: isProcessing
            )

            Spacer()

            Button("End session") { vm.endSession() }
                .font(.subheadline)
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.bottom, 40)
        }
    }

    private var sessionHeader: some View {
        HStack {
            Text("CAMUSEAN")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(.tertiaryLabel))
                .kerning(2.5)
            Spacer()
            if vm.lookupCount > 0 {
                Text("\(vm.lookupCount) word\(vm.lookupCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.camusean)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.camusean.opacity(0.12))
                    .clipShape(Capsule())
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .animation(.spring(duration: 0.35, bounce: 0.2), value: vm.lookupCount)
            }
        }
    }

    private var statusDisplay: some View {
        Group {
            switch vm.phase {
            case .idle:
                Text("Starting…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)

            case .listening:
                if vm.partialTranscription.isEmpty {
                    Text("Say a word…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(vm.partialTranscription)
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .multilineTextAlignment(.center)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.88).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

            case .processing(let word):
                VStack(spacing: 14) {
                    Text(word)
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)
                    DotsView()
                }

            case .result(let word, let definition):
                VStack(spacing: 18) {
                    Text(word)
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)
                    Rectangle()
                        .fill(Color.camusean.opacity(0.45))
                        .frame(width: 30, height: 1.5)
                    Text(definition)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))

            case .error(let msg):
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.08), value: vm.partialTranscription)
        .frame(minHeight: 140, alignment: .center)
    }

    private var isListening: Bool {
        if case .listening = vm.phase { return true }
        return false
    }

    private var isProcessing: Bool {
        if case .processing = vm.phase { return true }
        return false
    }

    // MARK: - Summary Sheet

    private var summarySheet: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.camusean.opacity(0.09))
                    .frame(width: 108, height: 108)
                Image(systemName: "book.closed")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Color.camusean)
            }
            Spacer().frame(height: 28)
            Text("Session complete")
                .font(.system(size: 26, weight: .bold, design: .serif))
            Spacer().frame(height: 10)
            Text(vm.lookupCount == 0
                 ? "No words looked up"
                 : "\(vm.lookupCount) word\(vm.lookupCount == 1 ? "" : "s") saved to review")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") { vm.showSummary = false }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.camusean)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(30)
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Organic Mic View

private struct OrganicMicView: View {
    let isListening: Bool
    let isProcessing: Bool

    @State private var breathe = false
    @State private var spinAngle: Double = 0

    var body: some View {
        ZStack {
            // Breathing rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.camusean.opacity(0.13 - Double(i) * 0.03), lineWidth: 1)
                    .frame(
                        width: 88 + CGFloat(i) * 28,
                        height: 88 + CGFloat(i) * 28
                    )
                    .scaleEffect(breathe && isListening ? 1.13 : 1.0)
                    .opacity(isListening ? (breathe ? 1.0 : 0.25) : 0.0)
                    .animation(
                        isListening
                            ? .easeInOut(duration: 1.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.24)
                            : .easeOut(duration: 0.4),
                        value: breathe
                    )
            }

            // Processing arc
            if isProcessing {
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(
                        Color.camusean.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 102, height: 102)
                    .rotationEffect(.degrees(spinAngle))
            }

            // Core — grey base + amber overlay for smooth animated transition
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 86, height: 86)
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.camusean, Color.camusean.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 86, height: 86)
                    .opacity(isListening ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: isListening)
            }
            .shadow(
                color: isListening ? Color.camusean.opacity(0.35) : .clear,
                radius: 20, y: 7
            )

            Image(systemName: "mic.fill")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.white)
                .opacity(isListening || isProcessing ? 1.0 : 0.45)
                .animation(.easeInOut(duration: 0.3), value: isListening)
        }
        .onAppear {
            breathe = true
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spinAngle = 360
            }
        }
        .onChange(of: isListening) { _, newVal in
            if newVal { breathe = true }
        }
        .accessibilityLabel(isListening ? "Listening" : isProcessing ? "Processing" : "Standby")
    }
}

// MARK: - Dots Loading View

private struct DotsView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 5, height: 5)
                    .scaleEffect(animate ? 1.5 : 0.6)
                    .opacity(animate ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.17),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

#Preview {
    ReadingSessionView()
        .modelContainer(for: Word.self, inMemory: true)
}
