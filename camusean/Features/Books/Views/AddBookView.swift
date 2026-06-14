import SwiftUI
import SwiftData

// Add-book sheet: scan a barcode (when the device supports it) → confirm/correct the enriched
// fields → save. Manual entry is always reachable (camera unsupported, denied, or no match), and
// the confirm form is the single funnel every path lands in. On save, `onAdded(book)` hands the
// new Book back so the caller can make it the active reading book.
struct AddBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let onAdded: (Book) -> Void

    @State private var vm = AddBookViewModel(
        cameraAvailable: BarcodeScannerView.isAvailable,
        cameraDenied: AddBookViewModel.isCameraDenied
    )

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add a book")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    if vm.stage == .confirm {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { saveAndDismiss() }
                                .disabled(!vm.canSave)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.stage {
        case .scanning:
            scanning
        case .looking:
            ProgressView("Looking up…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .confirm:
            confirmForm
        }
    }

    // MARK: Scanning

    private var scanning: some View {
        ZStack(alignment: .bottom) {
            BarcodeScannerView { payload in
                Task { await vm.handleScan(payload) }
            }
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                Text("Point the camera at the barcode on the back cover.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal)
                    .shadow(radius: 4)
                Button("Enter manually") { vm.switchToManualEntry() }
                    .buttonStyle(.borderedProminent)
                    .tint(.camusean)
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: Confirm / manual entry

    private var confirmForm: some View {
        Form {
            if let notice = vm.notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Book") {
                if let cover = vm.coverURL, let url = URL(string: cover) {
                    HStack {
                        Spacer()
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image.resizable().scaledToFit()
                            case .failure:
                                Image(systemName: "book.closed")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(height: 120)
                        .cornerRadius(6)
                        Spacer()
                    }
                }
                TextField("Title", text: $vm.title)
                TextField("Author", text: $vm.author)
            }

            Section("Reading language") {
                Picker("Language", selection: $vm.locale) {
                    ForEach(ReadingLanguage.all) { lang in
                        Text("\(lang.flag) \(lang.name)").tag(lang.locale)
                    }
                }
            }

            if vm.scannerOffered {
                Section {
                    Button("Scan a barcode instead") { vm.stage = .scanning }
                }
            }
        }
    }

    private func saveAndDismiss() {
        guard let book = vm.save(into: modelContext) else { return }
        onAdded(book)
        dismiss()
    }
}
