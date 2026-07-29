# Camusean — submission checklist

Status as of 2026-07-28. Two goals, and they are **not** the same path:

- **Get your friend testing** → TestFlight. Does not require App Store approval,
  screenshots, or finished store metadata. This is much closer than the full listing.
- **Get on the App Store** → full App Review. Needs everything below.

---

## THE ONE BLOCKER FOR BOTH — a seeded API key

`camusean/Secrets.plist` does not exist. Without it, `KeychainService.seedAPIKeyIfNeeded()`
finds nothing, and anyone who is not you opens the app to a key wall in Settings and
cannot look up a single word.

That fails **both** goals at once:
- Your friend downloads from TestFlight and the app does nothing.
- App Review hits Guideline 2.1 (incomplete / functionality not accessible to the
  reviewer) and rejects. Worse, `review-notes.txt` tells the reviewer the service is
  pre-configured — being contradicted by the build is a bad way to start a review.

**What to do (only you can — it is your Anthropic account):**

1. Create a **capped, revocable** key at <https://console.anthropic.com> — set a low
   monthly spend limit. The key ships inside the app bundle, so treat it as semi-public:
   anyone determined can extract it from the binary. The app also self-limits to 200
   lookups/day (`AnthropicService.dailyCap`).
2. `./scripts/set-api-key.sh sk-ant-...`
3. Rebuild.

Then confirm: **Settings should show a green "A key is already set up"** without you
typing anything. `./scripts/set-api-key.sh --status` reports the file side of it.

**The seeding path itself is already verified end-to-end** (2026-07-28) with a dummy
key on a freshly erased simulator: `Secrets.plist` is bundled into the `.app`,
`seedAPIKeyIfNeeded()` writes to the Keychain, and Settings reflects it. So the only
untested variable left is the key itself. Two things were fixed along the way:

- `seedAPIKeyIfNeeded()` used `try?`, which silently swallowed any Keychain failure —
  meaning a broken seed was indistinguishable from "no key supplied". It now logs the
  precise reason it bailed.
- A stored key rendered as a **completely blank field**, because SwiftUI's `SecureField`
  does not display text set programmatically. A reviewer told the service is
  pre-configured, opening Settings to an empty key box, would reasonably conclude
  otherwise. Hence the explicit status row.

---

## Ready — nothing further needed

| Item | State |
|---|---|
| Privacy manifest | `camusean/PrivacyInfo.xcprivacy`, verified bundled, reason CA92.1 |
| Privacy policy (public) | <https://camusean.vercel.app/privacy.html> — live, no login wall |
| Privacy policy (in-app) | Settings → About → Privacy Policy |
| Support / Marketing URL | <https://camusean.vercel.app/> — live |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` — no prompt at upload |
| Usage descriptions | Microphone, Speech Recognition, Camera — all specific and feature-tied |
| Debug harness | Release build fails if DebugBridge is linked (`scripts/verify-no-debug-bridge.sh`) |
| Screenshots | **Empty — must be regenerated.** `./scripts/capture-screenshots.sh /tmp/camusean-container` → 1320x2868 (6.9"), no alpha. Preflight blocks until they exist. |
| Store copy | `app-store-metadata.md` — name, subtitle, description, keywords, category |
| Review notes | `review-notes.txt` — includes why the app asks for the camera |
| Privacy labels / age rating | `privacy-labels-and-age-rating.md` |
| Build number | 1.0 (3) — bumped so the upload is not a duplicate |
| Device family | iPhone only (`TARGETED_DEVICE_FAMILY = 1`) — see below |
| Distribution signing | verified: archive + export produce an .ipa signed `Apple Distribution: Benjamin Delasoie (LWQ9NP6HVT)` |

### Why the app is now iPhone-only — reversible if you disagree

It previously declared `TARGETED_DEVICE_FAMILY = "1,2"`, i.e. iPad support. Two
consequences, and the first is a hard submission blocker:

1. **App Store Connect requires 13-inch iPad screenshots** from any app that runs on
   iPad. You could not have submitted without producing them.
2. Running it on an iPad Pro 13" showed the iPhone layout stretched across the screen —
   not broken, but vast dead space and a full-width primary button. That is the kind of
   thing Guideline 4.0 is about.

Since the product is explicitly phone-in-hand-while-holding-a-book, restricting to
iPhone removes both problems. It is one setting; set it back to `"1,2"` and produce iPad
screenshots if you ever want iPad users. The now-meaningless iPad orientation key was
removed at the same time.

---

## Getting your friend on TestFlight (fastest path)

1. Seed the API key (above) — otherwise this is pointless.
2. Xcode → Product → Archive, then Distribute App → App Store Connect → Upload.
3. Wait for processing (usually minutes; you get an email).
4. **Internal testing — no review:** App Store Connect → Users and Access → add his
   Apple ID → then TestFlight → Internal Testing → add him to the group. Up to 100
   testers, available as soon as the build finishes processing.
5. He installs TestFlight from the App Store and accepts the invite.

External testing (public link, up to 10,000) needs Beta App Review and a "What to
Test" note, but still needs no screenshots or store metadata. Only use it if you want
testers who cannot be added to your team.

---

## Submitting to the App Store

Everything in "Ready" plus:

1. Seed the API key.
2. Archive and upload (same as above).
3. In App Store Connect fill in, from the files in this folder:
   - Name, subtitle, description, keywords, category → `app-store-metadata.md`
   - Screenshots → `appstore/screenshots/` under the **6.9"** display size
   - Privacy nutrition labels → `privacy-labels-and-age-rating.md`
   - Age rating questionnaire → same file
   - App Review notes → `review-notes.txt`
   - Privacy Policy URL, Support URL, Marketing URL → `app-store-metadata.md`
4. Submit.

---

## Design checks (Guideline 4.0 / HIG)

**Dark Mode — supported, verified 2026-07-28.** Rendered every screen on a simulator in
dark appearance and audited the code: the flashcard and list surfaces use
`Color(.systemBackground)` and `Color(.systemGray5/6)`, which adapt automatically, and
every hardcoded `.white` is text sitting on the always-amber button, correct in both
modes. Nothing is unreadable.

**Dynamic Type — partial.** Body copy uses semantic fonts (`.callout`, `.footnote`,
`.headline`) and scales correctly, which is the part that matters. But 38 call sites use
fixed `.font(.system(size:))`, and only 3 pair it with `minimumScaleFactor`. Those are
mostly display text — the app title, the big serif word on the result card — where a
fixed size is a defensible design choice, and Apple does not reject for it. Worth
revisiting for accessibility, not for approval: a reader using large text will see the
headline stay put while everything around it grows.

## Known gaps, honestly

- **The reading result card is missing from the screenshot set.** It is the app's best
  screen — the word, its definition, and the new grammar note — but capturing it needs
  a live lookup, which needs the API key in the simulator. Once `Secrets.plist` exists,
  re-run `./scripts/capture-screenshots.sh /tmp/camusean-container` and extend
  `ScreenshotTests` to launch with `-qaWord bonjour` (the DEBUG mic-bypass hook) to get it.
- **The screenshots contain your real vocabulary** — 29 words and three Camus titles
  pulled from your device. Nothing sensitive, and it reads as an authentic product, but
  look them over before making them public.
- **No App Preview video.** Optional, but `demo-video-shotlist.md` already plans one,
  and for a voice-first app that a reviewer may test in a silent room it is genuinely
  persuasive. Consider it if the first submission is rejected under 4.3.
- **The previous rejection was code-50** (the QA bridge shipping in the app target).
  That specific failure is now structurally prevented, not just fixed.
