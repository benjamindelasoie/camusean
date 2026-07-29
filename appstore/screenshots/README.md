# Screenshots

> **This directory is currently empty — regenerate before any submission.**
>
> The previous set was deleted on 2026-07-29 because it predated two rounds of visual
> change: the design pass (palette, Dynamic Type, touch targets, card surface) and the
> review-vertical work (three grades, audio, card provenance and state, a rebuilt stats
> strip). Every screen in it showed a UI that no longer exists, which is worse than
> having no screenshots at all — stale store assets misrepresent the app to reviewers
> and to buyers.
>
> `./scripts/capture-screenshots.sh /tmp/camusean-container`
>
> `scripts/preflight-submission.sh` blocks on an empty directory, so this cannot be
> forgotten on the way to a submission.

Captured by `../../scripts/capture-screenshots.sh` at **1320x2868** (6.9" class — the
primary required iPhone size), no alpha channel. Regenerate any time; do not hand-edit.

## Which to actually upload

App Store Connect accepts 1–10 per size. **Upload 01, 02 and 03. Leave 04 and 05 out.**

| File | Upload? | Why |
|---|---|---|
| `01-read.png` | **yes** | The pitch, a real book attached, one clear call to action. |
| `02-review.png` | **yes** | Shows the flashcard deck and that words accumulate ("1 of 29"). |
| `03-review-revealed.png` | **yes** | The payoff — a French word, its meaning, a real example sentence. |
| `04-settings.png` | no | Foregrounds the **Anthropic API Key** field. Nothing about a settings screen sells the app, and advertising that the app wants an API key invites a reviewer to ask why a consumer app needs one — a question better answered in the review notes than raised on the storefront. |
| `05-privacy.png` | no | A wall of policy text. The policy is already linked from App Store Connect and reachable in-app, which is what Guideline 5.1.2 asks for. It sells nothing. |

Keep 04 and 05 in the repo anyway: they are evidence that the in-app privacy policy
exists, which is worth having on hand if App Review ever queries it. That argument only
holds while they depict the shipping build — stale evidence is not evidence, which is why
the previous set was deleted rather than kept around.

## Missing: the reading result card

The best screen in the app — the spoken word, its definition, and the new grammar note —
is **not** in this set. Capturing it needs a live lookup, which needs a seeded API key
(see `../SUBMISSION-CHECKLIST.md`). Once `camusean/Secrets.plist` exists:

1. Extend `camuseanUITests/ScreenshotTests.swift` to launch with
   `app.launchArguments += ["-qaWord", "disparu"]` — the DEBUG mic-bypass hook that
   drives the full lookup path without a microphone (the simulator has none).
2. Re-run `./scripts/capture-screenshots.sh /tmp/camusean-container`.

Use an inflected word like `disparu` so the grammar note appears; that line is the
newest and most distinctive thing the app does.

## Note on content

These contain real vocabulary and books pulled from Benja's device (29 words, three
Camus titles). It reads as authentic rather than mocked up, but it is real personal
reading history — worth a glance before it goes public.
