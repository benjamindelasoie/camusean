import SwiftUI

// The "nothing here yet" shape, used by every empty and caught-up state in the app.
//
// This existed four times before it existed once: `ReviewView.emptyState`,
// `ReviewView.allCaughtUp`, `LibraryView.emptyState`, and `LibraryView.noMatchesState`.
// Two of them were byte-identical, and the 2026-07-28 design pass had to apply the same
// font and colour edit in both files to keep them in step.
//
//   ╭───────────────╮
//   │   ( glyph )   │  tinted circle, decorative — hidden from VoiceOver
//   │     Title     │  serif, title2
//   │    Message    │  callout, secondary, centred
//   │   [ action ]  │  optional
//   ╰───────────────╯
struct EmptyStateView<Action: View>: View {
    let systemImage: String
    let title: String
    let message: String
    var tint: Color = Color(.systemGray2)
    var circleFill: Color = Color(.systemGray6)
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 100, height: 100)
                Image(systemName: systemImage)
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            action()
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Action == EmptyView {
    init(
        systemImage: String,
        title: String,
        message: String,
        tint: Color = Color(.systemGray2),
        circleFill: Color = Color(.systemGray6)
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            message: message,
            tint: tint,
            circleFill: circleFill,
            action: { EmptyView() }
        )
    }
}

#Preview("No words") {
    EmptyStateView(
        systemImage: "books.vertical",
        title: "No words yet",
        message: "Start a reading session\nto build your vocabulary."
    )
}

#Preview("Caught up") {
    EmptyStateView(
        systemImage: "checkmark",
        title: "All caught up",
        message: "Come back tomorrow.",
        tint: .camuseanText,
        circleFill: Color.camusean.opacity(0.10)
    ) {
        Text("Browse all your words →")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.camuseanText)
    }
}
