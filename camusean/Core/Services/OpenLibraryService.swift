import Foundation
import Dependencies

// Fields beyond title/author are stable join keys for later catalog integrations. `locale` is our
// BCP-47 reading locale, resolved from OL's MARC code via ReadingLanguage — nil when OL gives
// no/unknown language (reader picks). `author` is "" when OL has no by_statement.
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
    case network
    case decoding

    var errorDescription: String? {
        switch self {
        case .notFound: "No book found for that barcode. Try searching by title."
        case .network: "Couldn't reach Open Library. Check your connection."
        case .decoding: "Got an unexpected response from Open Library."
        }
    }
}

// The `/isbn/{isbn}.json` edition endpoint carries language (MARC code), cover ids, work key, and a
// by_statement author. The work record does NOT carry language, so there is deliberately no
// work-level language hop — a missing edition language goes straight to user-pick.
enum OpenLibraryService {

    // URLSession follows the /isbn -> /books edition redirect automatically.
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
        var meta = try parseEdition(from: data, isbn: clean)
        // Many editions have a null by_statement but list an author key — resolve the name with one
        // extra hop.
        if meta.author.isEmpty,
           let key = (try? JSONDecoder().decode(OLEdition.self, from: data))?.authors?.first?.key {
            meta.author = await fetchAuthorName(key, session: session) ?? ""
        }
        return meta
    }

    nonisolated static func fetchAuthorName(_ key: String, session: URLSession = .shared) async -> String? {
        guard let url = URL(string: "https://openlibrary.org\(key).json") else { return nil }
        guard let (data, _) = try? await session.data(from: url),
              let author = try? JSONDecoder().decode(OLAuthor.self, from: data),
              let name = author.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name
    }

    // Keep digits and a trailing X (valid in ISBN-10 check digits); strip hyphens and scan noise.
    nonisolated static func normalizedISBN(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isNumber || $0 == "X" })
    }

    // `nonisolated static` so the mapping is unit-testable with canned JSON and no network.
    nonisolated static func parseEdition(from data: Data, isbn: String) throws -> BookMetadata {
        let edition: OLEdition
        do {
            edition = try JSONDecoder().decode(OLEdition.self, from: data)
        } catch {
            throw OpenLibraryError.decoding
        }

        guard let rawTitle = edition.title?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTitle.isEmpty else {
            // No title is unusable — treat like a miss so the caller offers manual entry.
            throw OpenLibraryError.notFound
        }
        let title = cleanedTitle(rawTitle)

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

    // Reduce OL's cataloguing title (subtitle + series crammed into one field) to the short main
    // title. Drop trailing parenthetical/bracketed series info, then cut at the first subtitle
    // separator (":" most reliable, then dash, then comma). Aggressive on purpose — the confirm
    // card is editable for the rare over-trim.
    nonisolated static func cleanedTitle(_ raw: String) -> String {
        var t = raw
        if let r = t.range(of: #"\s*[\(\[].*$"#, options: .regularExpression) {
            t.removeSubrange(r)
        }
        for separator in [": ", ":", " — ", " - ", ", ", ","] {
            if let r = t.range(of: separator) {
                t = String(t[..<r.lowerBound])
                break
            }
        }
        let cleaned = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never return empty from over-trimming — fall back to the original trimmed title.
        return cleaned.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
    }

    // MARC language code -> app reading locale (region comes from ReadingLanguage, not OL). Accepts
    // both the MARC bibliographic ("fre", "ger") and ISO 639-2/T ("fra", "deu") spellings.
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

// `nonisolated` so the synthesized Decodable conformance is usable from the nonisolated parser
// (the module defaults types to @MainActor). snake_case keys match the API.
private nonisolated struct OLEdition: Decodable {
    let title: String?
    let key: String?
    let by_statement: String?
    let authors: [OLKeyRef]?
    let languages: [OLKeyRef]?
    let works: [OLKeyRef]?
    let covers: [Int]?
}

private nonisolated struct OLKeyRef: Decodable {
    let key: String
}

private nonisolated struct OLAuthor: Decodable {
    let name: String?
}

// A closure client (not a protocol) because this is a stateless, off-main-actor network call — it
// sidesteps the @MainActor-default isolation a protocol would impose. testValue/previewValue are
// inert (throw notFound) so tests/previews never hit the network unless they override it.
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
