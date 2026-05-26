import SwiftUI

struct ModelContainerErrorView: View {
    let error: Error
    let onReset: () -> Void
    let onRetry: () -> Void

    @State private var showResetConfirmation = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.camusean)

            VStack(spacing: 12) {
                Text("Couldn't open your library")
                    .font(.title2.weight(.semibold))

                Text("Camusean's saved-words database didn't load. Resetting clears your saved words and review schedule — your API key and language settings stay.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Text(error.localizedDescription)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 10))
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onRetry) {
                    Text("Try Again")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.camusean, in: .rect(cornerRadius: 12))
                        .foregroundStyle(.white)
                }

                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Text("Reset Saved Words")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .alert("Reset saved words?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive, action: onReset)
        } message: {
            Text("This deletes every saved word and review schedule. There's no undo.")
        }
    }
}

#Preview {
    ModelContainerErrorView(
        error: NSError(
            domain: "SwiftDataError",
            code: 134110,
            userInfo: [NSLocalizedDescriptionKey: "The model used to open the store is incompatible with the one used to create the store."]
        ),
        onReset: {},
        onRetry: {}
    )
}
