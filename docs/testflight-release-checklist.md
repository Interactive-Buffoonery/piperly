# TestFlight Release Checklist

This checklist captures the repo-side state needed before archiving Piperly for
TestFlight validation. It intentionally does not automate upload or store local
signing account details in the repository.

## Current Repo Metadata

- Bundle identifier: `com.piperly.app` in `project.yml`
- Display name: `Piperly`
- Marketing version: `1.0`
- Build number: `1`
- Signing: automatic signing, with the developer team selected locally in Xcode
- Category: Education via `INFOPLIST_KEY_LSApplicationCategoryType`
- Device family: iPad only via `TARGETED_DEVICE_FAMILY = 2`
- Launch screen: `UILaunchStoryboardName` points to `LaunchScreen`
- App icon: single universal 1024x1024 icon with no alpha channel
- Privacy manifest: declares no tracking, no collected data, and UserDefaults
  required-reason API use

Do not change the version or build number unless App Store Connect rejects the
upload for a duplicate build number or the archive should use a new release
train.

## Pre-Archive Verification

Run these from the repo root before archiving:

```bash
xcodegen generate
plutil -lint Piperly/Info.plist Piperly/Resources/PrivacyInfo.xcprivacy
sips -g hasAlpha Piperly/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
xcodebuild -project Piperly.xcodeproj \
  -scheme Piperly \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected results:

- `plutil` reports both files are OK.
- `sips` reports `hasAlpha: no`.
- The generic iOS build succeeds.

## Archive And Upload

1. Open `Piperly.xcodeproj` in Xcode after running `xcodegen generate`.
2. Select the `Piperly` scheme.
3. Select **Any iOS Device (arm64)** or a connected iPad.
4. Confirm **Signing & Capabilities** uses the appropriate Apple Developer team
   for the archive and automatic signing.
5. Use **Product > Archive**.
6. In Organizer, choose **Distribute App > App Store Connect > Upload**.
7. Let Xcode manage signing during upload unless there is a concrete reason to
   use manual signing assets.

## Manual Physical-iPad Smoke Checklist

Run on a physical iPad before each archive. The simulator cannot fully exercise
TTS voices, and several Phase 1 correctness fixes are only verifiable by
behavior (they have no unit coverage by design).

Core flows:

- First-launch voice setup completes and a voice is selectable.
- Bundled sample books import on first launch and appear in the library.
- A book opens, pages turn left/right, and reading position is restored on
  reopen.
- Tapping a word speaks it aloud and collects it into the word list.
- Bookmarks add/remove with stickers and reappear in the bookmark list.
- Saved words appear in the Words tab and re-speak when tapped.
- Reader themes and font sizes apply live.

Phase 1 fix verification (behavior-only, no unit coverage):

- Repeated word taps speak every time, including tapping the same word twice in
  a row (INT-343).
- Importing two EPUBs with the same filename keeps both books with no overwrite
  or duplicate library entries (INT-344).
- Reading position and tapped words survive backgrounding the app immediately
  after a tap, then relaunching (flush-on-background, INT-344).
- A malformed or unopenable EPUB shows a recoverable error with a working
  "Try Again" button instead of crashing (INT-341).

## App Store Connect Fields To Complete Manually

Create or update the App Store Connect app record before external TestFlight
review:

- Bundle ID: register `com.piperly.app`, or update `project.yml` first if the
  final App Store bundle ID should be different.
- App name: Piperly.
- Primary category: Education.
- Age rating: answer based on child-facing EPUB reader behavior and parent-
  supplied content.
- Kids Category: opt in only if the app is ready to maintain the child-safety
  posture documented in `docs/app-store-privacy-review.md`.
- Privacy Policy URL: publish the policy text drafted in
  `docs/app-store-privacy-review.md`, then add the public URL.
- App privacy answers: use `docs/app-store-privacy-review.md`; the current
  repo posture is no tracking and no collected data.
- Beta App Description: describe Piperly as an iPad EPUB reader for kids with
  local reading state.
- Reviewer notes: describe local-only reading state and the absence of ads,
  analytics, tracking, in-app purchases, social features, account creation,
  external catalog browsing, or a developer-hosted backend.
- Sign-in information: not required.
- Export compliance: answer in App Store Connect based on Apple's current
  questionnaire. Piperly does not implement custom encryption in the app code;
  it relies on Apple platform networking and Readium dependencies.
- Contact information: provide the current review contact details.
- Testers: add internal testers after processing, and add external tester
  groups before submitting for beta review.

## Scope Notes

The repo-side release posture has changed in a few important places:

- App icon alpha has already been fixed.
- A launch screen exists and is wired through `UILaunchStoryboardName`.
- External catalog browsing has been removed.
- A privacy and child-safety review now exists in
  `docs/app-store-privacy-review.md`.

The remaining release work is therefore documentation and handoff clarity:
verify the repo-side metadata, document the archive path, and make manual App
Store Connect work explicit.
