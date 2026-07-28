import SwiftUI

// In-app privacy policy (App Review guideline 5.1.2 wants the policy reachable inside the
// app, not only from the App Store listing).
//
// Rendered natively rather than as a Link to the hosted copy, for two reasons: the app has
// no hosted URL yet, and a native screen still works with no network — which matters for an
// app whose whole premise is reading somewhere quiet.
//
// ⚠️ THIS IS A SECOND COPY. The canonical, publicly-served version is
// `appstore/web/privacy.html`, which is what the App Store Connect Privacy Policy URL points
// at. Any change to one MUST be mirrored in the other, including the effective date — a
// mismatch between the in-app and hosted policy is itself a 5.1.2 problem.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(Self.effectiveDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(Self.lead)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(Self.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                        ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Content

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let paragraphs: [String]
    }

    private static let effectiveDate = "Effective July 28, 2026"

    private static let lead = """
        Camusean is built to be private. There is no account to create, nothing to log in to, \
        no advertising, and no analytics tracking you. This page explains exactly what happens \
        to your data.
        """

    private static let sections: [Section] = [
        Section(title: "What we don't collect", paragraphs: [
            "No account, name, email, or login is required to use the app.",
            "No advertising identifiers, no third-party analytics or tracking SDKs.",
            "We do not build a profile of you, and we never sell data. There is nothing to sell."
        ]),
        Section(title: "Microphone and speech recognition", paragraphs: [
            """
            When you start a reading session and use push-to-talk, the app records audio so it \
            can recognize the word you spoke. Audio is captured only while you are holding the \
            talk button, it is used solely to transcribe what you said, and the app does not \
            store your recordings.
            """,
            """
            Recognition uses Apple's built-in speech frameworks. On iOS 26 and later this runs \
            entirely on your iPhone — the audio never leaves the device. On earlier versions of \
            iOS, the app asks Apple to transcribe on-device as well, but that is only possible \
            when your iPhone has already downloaded the offline assets for the language you are \
            reading. When it has not, Apple's Speech framework transcribes the audio on Apple's \
            servers, and Apple handles it under its own privacy policy. Either way, the \
            recording is never sent to us and is never stored.
            """
        ]),
        Section(title: "Word lookups", paragraphs: [
            """
            To define a word, the app sends the following over a secure connection to our \
            dictionary provider, Anthropic (the Claude API): the word or short phrase that was \
            recognized; the languages you have selected to read from and translate into; the \
            title of the book you picked for the session, if you picked one, used only to \
            choose the most fitting sense of a word; and any words you rejected a moment \
            earlier in the same session, so the app does not offer you the same wrong guess \
            twice.
            """,
            """
            Anthropic returns a definition and example sentence. These requests are not tied to \
            your identity — no account or personal information is attached. Anthropic processes \
            the request under its own terms and privacy policy.
            """
        ]),
        Section(title: "Books, the camera, and Open Library", paragraphs: [
            """
            You can attach a book to a reading session, either by typing its details or by \
            scanning the barcode on its back cover. If you scan, the camera is used only to \
            read the barcode. That happens entirely on your iPhone: no photo or video is saved, \
            and no image is ever transmitted anywhere.
            """,
            """
            To turn the barcode into a title and author, the app sends the book's ISBN to Open \
            Library, a free catalogue run by the Internet Archive. It may make up to three \
            requests: one to look up the edition, one to resolve the author's name, and one to \
            load the cover image shown on the confirmation screen. Open Library therefore \
            learns which book you are adding, along with your IP address, as any web request \
            would reveal. Nothing about you, your saved words, or your reading is sent — only \
            the ISBN. If you add a book by typing its details instead of scanning, no request \
            is made and the camera is never used.
            """
        ]),
        Section(title: "Words you save", paragraphs: [
            """
            The words you look up, and the books you add, are saved on your device so you can \
            review them as flashcards and see which book you learned a word in. This data lives \
            locally on your iPhone (via Apple's on-device storage) and is not uploaded to us or \
            to any server. There is no account and no cloud sync. Deleting the app removes it.
            """
        ]),
        Section(title: "Children's privacy", paragraphs: [
            """
            Camusean is not directed at children under 13 and does not knowingly collect \
            personal information from them.
            """
        ]),
        Section(title: "Changes to this policy", paragraphs: [
            """
            If this policy changes, the updated version will be posted with a new effective date.
            """
        ]),
        Section(title: "Contact", paragraphs: [
            "Questions about privacy? Email delasoiebenja@icloud.com."
        ])
    ]
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
