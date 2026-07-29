import XCTest

/// Captures the App Store screenshot set.
///
/// Run against an **iPhone 17 Pro Max** simulator — that is the 6.9" class (1320x2868),
/// which is the primary required size. Screenshots land as test attachments; pull them
/// out with `scripts/export-screenshots.sh`.
///
///     xcodebuild test -scheme camusean \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' \
///       -only-testing:camuseanUITests/ScreenshotTests \
///       -resultBundlePath /tmp/shots.xcresult
///
/// The Library and Review screens only look like a real product when the store has
/// words in it. This test does NOT seed data — it reuses whatever is already in the
/// simulator's container, so seed it first (see the script) rather than shipping
/// screenshots of an empty app.
///
/// `-voicePromptShown YES` goes in via the NSUserDefaults argument domain, which is
/// volatile per launch: it suppresses the enhanced-voice onboarding sheet that would
/// otherwise cover every shot on a simulator (which never has Enhanced voices), without
/// writing anything persistent.
final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-voicePromptShown", "YES"]
        app.launch()

        // 1 — Read tab: the pitch, the selected book, the call to action.
        XCTAssertTrue(app.buttons["Begin Reading"].waitForExistence(timeout: 20),
                      "Start screen never appeared; the app may have failed to launch.")
        attach(app, named: "01-read")

        // 2 — Review tab: the flashcard deck built from saved words.
        if tap(app, tab: "Review") {
            attach(app, named: "02-review")

            // 2b — the card flipped. The front is just a word; the definition is the
            // payoff, so this is the shot that shows what the app is actually for.
            let reveal = app.buttons["Reveal definition"]
            if reveal.waitForExistence(timeout: 5) {
                reveal.tap()
                Thread.sleep(forTimeInterval: 1.2)   // let the flip animation finish
                attach(app, named: "03-review-revealed")
            }
        }

        // 3 — Settings: languages, voice, and the privacy policy entry point.
        if tap(app, tab: "Settings") {
            attach(app, named: "04-settings")

            // 4 — The in-app privacy policy (guideline 5.1.2 evidence as well as a shot).
            //
            // Scroll first. The About section sits below the fold once Settings grows, and
            // `waitForExistence` returns false for a row that far down — which silently
            // dropped this screenshot from the set rather than failing the run. Guideline
            // 5.1.2 evidence going missing quietly is exactly the failure worth guarding.
            // Scroll until it is reachable. A fixed number of swipes is not enough at
            // accessibility text sizes, where the Settings form is several screens long.
            let privacy = app.buttons["Privacy Policy"]
            var swipes = 0
            while !privacy.exists && swipes < 8 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(privacy.waitForExistence(timeout: 5),
                          "Privacy Policy row not reachable after \(swipes) swipes — "
                          + "the guideline 5.1.2 screenshot would be missing from the set.")
            privacy.tap()
            attach(app, named: "05-privacy")
        }
    }

    // MARK: - Helpers

    /// Tab bar buttons are the only reliable navigation anchor here — the screens
    /// themselves are largely custom-drawn, so querying their contents is brittle.
    @MainActor
    private func tap(_ app: XCUIApplication, tab: String) -> Bool {
        let button = app.tabBars.buttons[tab]
        guard button.waitForExistence(timeout: 10) else {
            XCTFail("Tab '\(tab)' not found — screenshot set will be incomplete.")
            return false
        }
        button.tap()
        // Let the transition settle; a mid-animation capture is unusable for the store.
        Thread.sleep(forTimeInterval: 1.5)
        return true
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways   // default deletes on success, which is when we want them
        add(shot)
    }
}
