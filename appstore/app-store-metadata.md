# Camusean — App Store Connect metadata

Copy-paste source for the App Store listing. Each section notes the field it maps
to and Apple's character limit. The whole point is to read as a *specific, original
product* (anti-4.3-spam), not a generic language-learning template — so the copy
foregrounds the unique speak-while-reading workflow and avoids keyword stuffing.

---

## App Name  (field: Name · max 30 chars)
Camusean

## Subtitle  (field: Subtitle · max 30 chars)
Primary:
> Speak a word, hear its sense        (28 chars)

Alternates:
> Voice lookups while you read         (28 chars)
> Hear definitions as you read         (28 chars)

## Promotional Text  (field: Promotional Text · max 170 chars · editable without review)
> Reading a book in another language? Don't break your stride to type. Say the
> word out loud and Camusean speaks the definition back — then saves it for review.

---

## Description  (field: Description · max 4000 chars)

Reading literature in a language you're still learning means stopping every few
lines to look something up. You put the book down, open a dictionary app, type
the word, read the entry, switch back — and the thread of the sentence is gone.

Camusean removes that interruption. Keep the physical book in your hands. When
you hit a word you don't know, hold the button and just say it out loud. Within
about a second you hear the definition spoken back in your own language, see it
on screen, and the word is saved automatically. No typing. No tab-switching. No
losing your place.

Later, the words you looked up are waiting for you as flashcards. Swipe through
them, mark the ones you know, and keep the rest in rotation.

HOW IT WORKS
• Start a reading session and keep reading.
• Hit an unknown word? Hold the button and say it aloud.
• Hear and see its definition instantly.
• Review your saved words as flashcards whenever you like.

BUILT FOR REAL READING
• Voice-first — designed for hands-on-the-book reading, not screen tapping.
• Spoken definitions, so your eyes stay on the page.
• Made for physical books and reading flow, not drills and streaks.
• Set your reading language; definitions come back in your native language.

PRIVATE BY DESIGN
• No account, no sign-up, no ads.
• Your saved words live on your device.
• No tracking, no analytics profiles, nothing sold.

Camusean is for people who read seriously in another language — novels, essays,
poetry — and want to understand without breaking the spell of the page.

Note: the voice lookup works best on a physical device with microphone and
speech-recognition permission enabled.

---

## Keywords  (field: Keywords · max 100 chars · comma-separated, no spaces)
reading,vocabulary,language,dictionary,books,literature,French,flashcards,voice,pronunciation

(91 chars. Honest and specific — no competitor names, no repetition of the app
name or words already in the title/subtitle, which Apple ignores anyway.)

---

## What's New  (field: Version release notes — for the resubmission build)
> New app icon and visual polish. Faster spoken-word-to-definition lookup.

---

## Category  (field: Primary / Secondary Category)
Primary:  Education
Secondary: Reference

(Education + Reference fit the dictionary/reading use case. Avoid the most
crowded buckets if a more precise one fits — precision is an anti-spam signal.)

---

## URLs  (fields: Support URL / Marketing URL / Privacy Policy URL)
LIVE as of 2026-07-28. appstore/web/ is deployed to Vercel (project `camusean`).
Paste these verbatim into App Store Connect:
• Support URL:        https://camusean.vercel.app/
• Marketing URL:      https://camusean.vercel.app/
• Privacy Policy URL: https://camusean.vercel.app/privacy.html

⚠️ Use the bare `camusean.vercel.app` host and NOTHING else. The project-scoped
aliases (camusean-<hash>-benjamindelasoies-projects.vercel.app) sit behind Vercel
Authentication and redirect to a vercel.com login page — an App Review reviewer
would hit a login wall, which is a 5.1.2 rejection. Those protected URLs still
answer HTTP 200 on the redirect, so a status-code check alone will not catch it;
verify by following redirects:
    curl -sL -o /dev/null -w '%{url_effective}\n' https://camusean.vercel.app/privacy.html

Redeploy after editing the html:  vercel deploy --cwd appstore/web --prod --yes

A real, resolving web presence is a meaningful "this is a genuine product"
signal for a 4.3 review.
