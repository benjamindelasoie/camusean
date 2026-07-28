# App Store Connect — privacy labels, age rating, and compliance answers

Paste-able answers for the App Store Connect questionnaires, plus the reasoning
behind each. Written 2026-07-28.

**Why this file exists.** Apple cross-checks four surfaces against each other, and a
mismatch between any two is its own rejection (Guideline 5.1.2):

1. `camusean/PrivacyInfo.xcprivacy` — the privacy manifest in the binary
2. App Store Connect privacy nutrition labels — this file
3. `appstore/web/privacy.html` — the public policy (also mirrored in the in-app
   `PrivacyPolicyView`)
4. What the app actually does at runtime

If you change any one of them, change all four.

---

## The app's actual data flows (the ground truth all four surfaces describe)

| # | What leaves the device | Where it goes | Tied to identity? |
|---|---|---|---|
| 1 | The recognized word or phrase, the source+target language names, the selected book's title, and any words rejected moments earlier in the session | `api.anthropic.com` | No — no account exists, no identifier is attached |
| 2 | A scanned or typed ISBN | `openlibrary.org` (edition, author, and cover requests) | No |

Nothing else. No analytics SDK, no advertising identifier, no crash reporter, no
account system, no cloud sync. Saved words and books never leave the device.

**Microphone audio is deliberately absent from that table.** The app never receives
or transmits the recording. It hands the microphone buffer to Apple's own Speech
framework and gets text back. On iOS 26+ that is fully on-device. On iOS 18–25 the
app now requests on-device recognition wherever the locale's offline assets exist,
and only falls back to Apple's servers when they do not — in which case Apple, not
Camusean, is the data controller. The privacy policy discloses this; the nutrition
labels should not claim the app collects audio, because it does not.

---

## Privacy nutrition labels

**"Do you or your third-party partners collect data from this app?" → Yes.**

Declaring Yes is the conservative reading. Apple defines "collect" as transmitting
data off-device where it can be accessed for longer than needed to service the
request in real time, and Anthropic retains API inputs briefly for trust and safety.
Answering No would be arguable but would contradict the privacy policy, which names
both third parties — and a contradiction is exactly what gets flagged.

For each data type below, answer **Not linked to you** and **Not used for tracking**.

| Data type | Purpose | Linked | Tracking |
|---|---|---|---|
| Other User Content | App Functionality | No | No |

**One judgment call worth knowing about.** The spoken word could plausibly be filed
under either *Other User Content* (it is text the user produced) or *Search History*
(it is a lookup query). Recommend **Other User Content**: the user is speaking a word
from a page, not searching a corpus the app maintains, and the app keeps no query
history server-side. If a reviewer pushes back, switching to Search History is a
metadata change, not a code change — but do not declare both, which overstates.

The ISBN is covered by the same entry. It is a book identifier the user chose to
scan, not an identifier *of the user*, so it must NOT be filed under *Identifiers* —
that category means device or user IDs and would wrongly imply tracking.

**Everything else in the questionnaire is No**: no contact info, health, financial
info, location, contacts, browsing history, purchases, identifiers, usage data, or
diagnostics.

Note `PrivacyInfo.xcprivacy` leaves `NSPrivacyCollectedDataTypes` as an empty array
on purpose — Apple documents that Xcode fails to generate a privacy report when it
encounters invented data-type constants, so the collection story is told here, in the
App Store Connect UI, which enumerates the approved categories itself. That is not a
contradiction between the two surfaces; the manifest's required part is the
`NSPrivacyAccessedAPITypes` declaration, which is present and correct (UserDefaults,
reason CA92.1).

---

## Age rating

Apple revised the age-rating questionnaire in 2025 and the exact question set moves,
so answer it from the live UI rather than from a list here. These are the facts you
will need, all verifiable in the source:

- **No violence, sexual content, nudity, profanity, crude humour, horror, gambling,
  or contests** of any kind.
- **No alcohol, tobacco, or drug references.**
- **No unrestricted web access.** There is no in-app browser. The only network calls
  are the two fixed API endpoints above plus a book cover image.
- **No user-to-user communication**, no social features, no user-generated content
  shared between users. The app is entirely single-user and local.
- **No in-app purchases, no advertising.**

**The one question that needs thought: AI-generated content.** Definitions come from
a large language model, so if the questionnaire asks whether the app displays
AI-generated content, the honest answer is **yes**. The output is tightly constrained
— a dictionary definition and one example sentence for a word the user spoke — but
answering no would be inaccurate. In principle a user could speak a vulgar word and
receive its definition, which is also true of any dictionary.

Expected outcome: **4+**. If the AI-content answer pushes it higher, accept the
higher rating rather than arguing; it does not affect TestFlight and barely affects
discovery for this category.

---

## Other compliance answers

| Question | Answer | Evidence |
|---|---|---|
| Export compliance / encryption | **No** — uses only standard HTTPS | `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` is already set, so App Store Connect will not prompt |
| Content rights — does it contain third-party content? | Book metadata and cover images come from Open Library (Internet Archive), used via their public API | Disclose if asked |
| Does it use IDFA? | **No** | No ad frameworks linked |
| Privacy Policy URL | `https://camusean.vercel.app/privacy.html` | Live, publicly reachable, no login wall |
| Support URL | `https://camusean.vercel.app/` | Live |

---

## Getting your friend testing — this does NOT need App Store approval

TestFlight is a separate, much shorter path than full App Review. Two options:

**Internal testing — no review at all, fastest.** Add his Apple ID under
App Store Connect → Users and Access, then add him to an internal TestFlight group.
Up to 100 internal testers, builds available within minutes of processing, and
**no Beta App Review**. This is the fastest way to get Camusean on his phone.

**External testing — needs Beta App Review.** Up to 10,000 testers by email or public
link. Requires a "What to Test" note and a review pass, but it is lighter and faster
than full App Review, and it does **not** require screenshots or finished store
metadata.

Either way the build must have a seeded API key (`camusean/Secrets.plist`), or he
will hit the key wall in Settings and the app cannot look anything up.
