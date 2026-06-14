import Foundation
import Dependencies

// Book metadata resolved from a scanned/typed ISBN. The fields beyond title/author exist so the
// `Book` entity can grow into Hardcover/progress/catalog integrations later (stable join keys).
// `locale` is the app's BCP-47 reading locale ("fr-FR") resolved from Open Library's MARC code via
// our own ReadingLanguage table — nil when OL gives no/unknown language, in which case the add-book
// confirm card lets the reader pick. `author` is "" when OL has no by_statement (also editable).
struct BookMetadata: Equatable, Sendable {
    var title: String
    var author: String
    var locale: String?
    var coverURL: String?
    var isbn: String?
    var openLibraryEditionID: String?
    var openLibraryWorkID: String?
}

enum OpenLibraryError: LocalizedError, Equatable {
    case notFound      // 404, or a record with no usable title → caller falls back to manual search
    case network       // couldn't reach Open Library
    case decoding      // unexpected response shape

    var errorDescription: String? {
        switch self {
        case .notFound: "No book found for that barcode. Try searching by title."
        case .network: "Couldn't reach Open Library. Check your connection."
        case .decoding: "Got an unexpected response from Open Library."
        }
    }
}

// Open Library JSON Data API client. The `/isbn/{isbn}.json` edition endpoint reliably carries the
// language (MARC code), cover ids, work key, and a by_statement author string for the languages this
// app reads (verified against fr/en/es editions). The work record does NOT carry language, so there
// is deliberately no work-level language hop — a missing edition language goes straight to user-pick.
enum OpenLibraryService {

    // Live network fetch. URLSession follows the /isbn -> /books edition redirect automatically.
    nonisolated static func fetch(isbn: String, session: URLSession = .shared) async throws -> BookMetadata {
        let clean = normalizedISBN(isbn)
        guard !clean.isEmpty, let url = URL(string: "https://openlibrary.org/isbn/\(clean).json") else {
            throw OpenLibraryError.notFound
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            print("[OpenLibrary] network error for \(clean): \(error)")
            throw OpenLibraryError.network
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw OpenLibraryError.notFound
        }
        return try parseEdition(from: data, isbn: clean)
    }

    // Strip everything but digits (and a trailing X, valid in ISBN-10 check digits). Handles
    // hyphenated typed ISBNs and any stray characters from a barcode scan.
    nonisolated static func normalizedISBN(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isNumber || $0 == "X" })
    }

    // Pure, testable: decode the edition JSON and map it onto BookMetadata. `nonisolated static`
    // so the contract (MARC mapping, missing fields, cover building) is unit-testable with canned
    // JSON and no network.
    nonisolated static func parseEdition(from data: Data, isbn: String) throws -> BookMetadata {
        let edition: OLEdition
        do {
            edition = try JSONDecoder().decode(OLEdition.self, from: data)
        } catch {
            throw OpenLibraryError.decoding
        }

        guard let title = edition.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            // A record with no title is unusable — treat like a miss so the caller offers manual entry.
            throw OpenLibraryError.notFound
        }

        let marc = edition.languages?.first?.key.replacingOccurrences(of: "/languages/", with: "")
        let locale = marc.flatMap(marcToLocale)

        let coverURL: String? = {
            guard let id = edition.covers?.first(where: { $0 > 0 }) else { return nil }
            return "https://covers.openlibrary.org/b/id/\(id)-M.jpg"
        }()

        let editionID = edition.key?.replacingOccurrences(of: "/books/", with: "")
        let workID = edition.works?.first?.key.replacingOccurrences(of: "/works/", with: "")
        let author = edition.by_statement?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return BookMetadata(
            title: title,
            author: author,
            locale: locale,
            coverURL: coverURL,
            isbn: isbn,
            openLibraryEditionID: editionID,
            openLibraryWorkID: workID
        )
    }

    // MARC bibliographic language code -> app reading locale. Region ("fr-FR") comes from our own
    // ReadingLanguage table, never from Open Library. Accepts both the MARC bibliographic ("fre",
    // "ger") and ISO 639-2/T ("fra", "deu") spellings. Unknown/unsupported -> nil (user picks).
    nonisolated static func marcToLocale(_ marc: String) -> String? {
        let prefix: String?
        switch marc.lowercased() {
        case "fre", "fra": prefix = "fr"
        case "eng": prefix = "en"
        case "spa": prefix = "es"
        case "ita": prefix = "it"
        case "ger", "deu": prefix = "de"
        case "por": prefix = "pt"
        default: prefix = nil
        }
        guard let prefix else { return nil }
        return ReadingLanguage.all.first { $0.prefix == prefix }?.locale
    }
}

// Decodable shapes of the OL edition record. `nonisolated` so the synthesized Decodable conformance
// is usable from the nonisolated parser (the module defaults types to @MainActor). snake_case keys
// match the API; the `_` triggers no warning since these are file-private wire types.
private nonisolated struct OLEdition: Decodable {
    let title: String?
    let key: String?
    let by_statement: String?
    let languages: [OLKeyRef]?
    let works: [OLKeyRef]?
    let covers: [Int]?
}

private nonisolated struct OLKeyRef: Decodable {
    let key: String
}

// swift-dependencies seam. A closure client (not a protocol) because this is a stateless,
// off-main-actor network call — it sidesteps the @MainActor-default isolation a protocol would
// impose. testValue/previewValue are inert (throw notFound) so tests and previews never hit the
// network unless they override `$0.bookMetadata`.
struct BookMetadataClient: Sendable {
    var lookup: @Sendable (_ isbn: String) async throws -> BookMetadata
}

extension BookMetadataClient: DependencyKey {
    nonisolated static let liveValue = BookMetadataClient(lookup: { try await OpenLibraryService.fetch(isbn: $0) })
    nonisolated static let testValue = BookMetadataClient(lookup: { _ in throw OpenLibraryError.notFound })
    nonisolated static var previewValue: BookMetadataClient { testValue }
}

extension DependencyValues {
    nonisolated var bookMetadata: BookMetadataClient {
        get { self[BookMetadataClient.self] }
        set { self[BookMetadataClient.self] = newValue }
    }
}
