import Foundation
import SwiftData
import Observation
import Dependencies
import AVFoundation

// Drives the add-book flow: scan a barcode (or skip to manual entry) → enrich via Open Library →
// let the reader confirm/correct the fields → save a Book. Every Open Library failure path
// (no match, network down, no camera) degrades to the same editable confirm form, prefilled with
// whatever we have — so the reader can always finish by typing.
@Observable
@MainActor
final class AddBookViewModel {
    enum Stage: Equatable {
        case scanning       // camera up, waiting for a barcode
        case looking        // Open Library fetch in flight
        case confirm        // editable fields ready (from a scan, or blank for manual entry)
    }

    var stage: Stage

    // Editable confirm fields. `locale` always holds a value once we reach `.confirm` (defaulted to
    // the reader's current reading language when Open Library gives none), so a saved Book always
    // has a language for the session to use.
    var title = ""
    var author = ""
    var locale: String
    var coverURL: String?
    var isbn: String?
    var openLibraryEditionID: String?
    var openLibraryWorkID: String?

    // Non-fatal note shown above the form, e.g. when a scan found no match and we fell back to manual.
    var notice: String?

    // Whether re-scanning is even possible (device can scan AND camera isn't denied). Gates the
    // "Scan a barcode instead" affordance so we never drop the reader into a dead black camera.
    let scannerOffered: Bool

    var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    @ObservationIgnored @Dependency(\.bookMetadata) private var bookMetadata

    private static var currentReadingLocale: String {
        UserDefaults.standard.string(forKey: "sourceLanguageLocale") ?? "fr-FR"
    }

    // Camera permission is separate from device capability: a phone can be scan-capable but have
    // camera access denied, which would otherwise show a black scanner with no way out.
    static var isCameraDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    init(cameraAvailable: Bool, cameraDenied: Bool) {
        locale = Self.currentReadingLocale
        scannerOffered = cameraAvailable && !cameraDenied
        if scannerOffered {
            stage = .scanning
        } else {
            stage = .confirm
            // Only explain when the camera is *blocked*; a Simulator/old-device "no camera" needs
            // no apology — manual entry is simply the path.
            if cameraDenied {
                notice = "Camera access is off — turn it on in Settings to scan, or enter the book below."
            }
        }
    }

    // Called from BarcodeScannerView when a barcode is read.
    func handleScan(_ payload: String) async {
        let cleanISBN = OpenLibraryService.normalizedISBN(payload)
        stage = .looking
        do {
            let meta = try await bookMetadata.lookup(cleanISBN)
            apply(meta)   // apply sets/clears the notice (e.g. an undetected-language warning)
        } catch {
            // No match / unreachable / unusable record → manual entry, prefilled with the ISBN.
            isbn = cleanISBN
            if case OpenLibraryError.network = error {
                notice = "Couldn't reach Open Library — check your connection, or enter the details below."
            } else {
                notice = "Couldn't find that barcode automatically. Enter the details below."
            }
        }
        stage = .confirm
    }

    // Reader chose to skip the camera and type the book in.
    func switchToManualEntry() {
        notice = nil
        stage = .confirm
    }

    private func apply(_ m: BookMetadata) {
        title = m.title
        author = m.author
        // Open Library's language is authoritative when present; otherwise keep the reader's
        // current reading language as the default — and say so, so the picker choice is deliberate.
        if let resolved = m.locale {
            locale = resolved
            notice = nil
        } else {
            locale = Self.currentReadingLocale
            notice = "We couldn't detect this book's language — confirm it below."
        }
        coverURL = m.coverURL
        isbn = m.isbn
        openLibraryEditionID = m.openLibraryEditionID
        openLibraryWorkID = m.openLibraryWorkID
    }

    @discardableResult
    func save(into context: ModelContext) -> Book? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        let book = Book(
            title: trimmedTitle,
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            language: locale,
            isbn: isbn,
            openLibraryEditionID: openLibraryEditionID,
            openLibraryWorkID: openLibraryWorkID,
            coverURL: coverURL
        )
        context.insert(book)
        try? context.save()
        return book
    }
}
