# TestFlight — external testing

Everything App Store Connect asks for when inviting testers who are **not** on your team.
External testing needs Beta App Review on the first build (roughly a day, lighter than full
App Review). Later builds of the same version usually go out without another review.

Still **not** required: screenshots, store description, keywords, category. Those are the
App Store listing, not TestFlight.

---

## THE BLOCKER — a seeded API key

Same one blocker as the App Store. Without `camusean/Secrets.plist`, a tester opens the app
to an empty key field and cannot look up a single word.

```
./scripts/set-api-key.sh sk-ant-...
```

Use a **capped, revocable** key with a low monthly spend limit. It ships inside the bundle,
so treat it as semi-public — extractable from the binary by anyone who cares to. The app
self-limits to `AnthropicService.dailyCap` (200) lookups per day. The file is gitignored.

Beta App Review will hit Guideline 2.1 without it, and `review-notes.txt` tells the reviewer
the service is pre-configured — being contradicted by the build is a poor start.

---

## Fields to fill

### Beta App Description
*(shown to testers in the TestFlight app)*

> Camusean is a reading companion for foreign-language books. While you read a physical
> book, say a word you don't know out loud and hear its meaning spoken back within about a
> second, without putting the book down. Words you look up are saved and come back later as
> flashcards, grouped by the book you met them in.
>
> Needs a microphone and works best with headphones or in a quiet room. Default reading
> language is French; Spanish, Italian, German, Portuguese and English are in Settings.

### Feedback Email
`delasoiebenja@icloud.com`

### Beta App Review Information
- **Contact:** Benjamin Delasoie · delasoiebenja@icloud.com
- **Phone:** *(required by Apple — fill in)*
- **Sign-in required:** No. There is no account and no login.
- **Notes:** paste `review-notes.txt` verbatim. It covers the device-only voice
  requirement, why the app asks for the camera, the grammar-note line, and the privacy
  posture.

---

## What to Test  (build 3)

Paste into the build's "What to Test" field. Written to point testers at what is genuinely
unproven rather than at everything.

> **Start here.** Read tab → Begin Reading → allow Microphone and Speech Recognition → say
> a French word out loud and pause. You should hear the definition within about a second.
> There is no button to hold; it listens for the whole session. Say the next word straight
> away. Tap End session when done.
>
> **Most useful things to tell me:**
>
> 1. **How long the pause feels** between finishing the word and hearing the definition.
>    This is the number I care most about.
> 2. **Words it mishears.** It tries to correct likely mistakes — tell me when it corrects
>    a word you didn't say, not just when it fails to understand you.
> 3. **Whether the voice sounds robotic.** If prompted to install Enhanced voices, please
>    do — Apple's default voices are noticeably worse and the app will say so on first run.
> 4. **The Review tab.** Swipe right for Good, left for Again, or use the three buttons
>    after revealing. Does the swipe threshold land where your thumb expects? Tap the small
>    speaker next to a word to hear it again.
> 5. **Audio while a session is running.** Start a reading session, switch to Review
>    without ending it, tap a speaker icon, then go back and say another word. Does it
>    still hear you? This specific path is untested on hardware.
> 6. **Large text.** Settings → Accessibility → Display & Text Size → Larger Text, pushed
>    high. Anything clipped, overlapping, or unreadable is a bug worth reporting.
>
> Known and not worth reporting: the reading-result card is not in the App Store
> screenshots yet; the app is iPhone-only.

---

## After upload

1. Build finishes processing (minutes; you get an email).
2. TestFlight → the build → fill "What to Test" (above).
3. TestFlight → External Testing → create a group → add your friend by email.
4. Submit for Beta App Review. First build only; expect about a day.
5. He installs TestFlight from the App Store and accepts the emailed invite.

If it is rejected, the likely cause is Guideline 2.1 from a missing API key — check
`./scripts/set-api-key.sh --status` before resubmitting.
