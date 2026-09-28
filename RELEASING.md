# Store builds

`ci.yaml` runs Flutter analysis and tests on every push and pull request. A push to `main` builds a signed APK/AAB, publishes the AAB to Google Play internal testing, and creates a GitHub nightly prerelease. `testbuild.yaml` produces a signed APK on demand. `release.yaml` builds from a version tag or manual dispatch: prerelease tags target Play's `alpha` track; stable tags stage a **production draft** that must be rolled out manually in Play Console. Both workflows upload an iOS build to TestFlight when all Apple signing secrets are present. Tagged prereleases also request external TestFlight testing.

The Android package and iOS bundle ID are `de.freal.unustasis`. Builds use Flutter 3.41.9 and a seconds-since-2020 build number (greater than the app's existing `+N` codes); do not reuse a version code from a previous store upload.

## Google Play

The repository's Actions secrets `KEYSTORE` (base64 JKS), `KEYSTORE_PASSWORD`, and `KEY_ALIAS` sign Android builds with the **stasis upload key**, not a different application's key. Preserve the original keystore securely; check its upload certificate against Play Console's App integrity page before the first CI upload. `android/key.properties` and the JKS must never be committed.

The Play publisher is `stasis-play-publisher@android-apps-508215.iam.gserviceaccount.com`. The `github-actions/stasis` Workload Identity provider in Google Cloud accepts OIDC tokens only from `rescoot/stasis` (audience `https://github.com/rescoot`). Its service account grants only that repository `roles/iam.workloadIdentityUser`. GitHub needs no stored Google service-account key. **In Play Console, invite this service account under Users and permissions and grant app-scoped access to stasis for unu:** view app information, manage testing releases, and manage production releases/drafts as required by the selected track. The Google Play Android Developer API must be linked to the `android-apps-508215` project and enabled. Play may require an initial manual release/acceptance of transfer-related agreements before API uploads work.

For a release, update `pubspec.yaml` to the desired version, write `changelog.md` for the GitHub release, and add `distribution/play/metadata/android/en-US/changelogs/<version>.txt` (plus any translations). Notes must be nonempty and at most 500 characters. Commit before tagging; a tag must match the version before `+` in pubspec. For example, `2.0.6-beta.1+47` uses tag `2.0.6-beta.1` and changelog `2.0.6-beta.1.txt`. A manual dispatch uses the current pubspec version and lets you choose a Play track; a production dispatch is always a draft. Do not promote a release without reviewing the built app and notes.

Nightly notes come from commit subjects since the preceding nightly tag. Publishing verifies the uploaded bundle's SHA-256 and version code and checks the committed Play track; it does not change production while uploading a testing build.

## Apple App Store Connect

The iOS app and its widget must be in the same Apple Developer team. Until the app has been transferred, iOS jobs skip because no Apple secrets are configured. Once the transfer completes:

1. Confirm the bundle IDs `de.freal.unustasis` and `de.freal.unustasis.ScooterWidget` and the `group.de.freal.unustasis` app group exist in the team with the necessary capabilities (including NFC for the app). The share extension is not embedded in the Runner archive.
2. Create an Apple Distribution certificate and two App Store Connect provisioning profiles named **Stasis App Store CI** and **Stasis Widget App Store CI**. Include that certificate and the app group entitlement in both profiles. Profiles are downloaded by CI at build time and checked against the imported certificate.
3. Set these repository Actions secrets: `APPLE_TEAM_ID` (ten-character team ID), `APPSTORE_ISSUER_ID`, `APPSTORE_KEY_ID`, `APPSTORE_PRIVATE_KEY` (full `.p8` contents), `IOS_DIST_CERT_P12` (base64-encoded `.p12`), and `IOS_DIST_CERT_PASSWORD`. Use an App Store Connect API key with sufficient app-management permission. Never commit certificates or API keys.
4. Configure TestFlight export compliance and any required beta review information. For external testing, add testers to an external group named `External Testing` (or have exactly one external group). Verify the build is approved before announcing external availability.

CI configures manual Release signing for the app and widget using the team secret and those profile names, exports an IPA and uploads it to TestFlight. It publishes localized What to Test notes from the release changelogs, or English commit notes for nightlies. Tagged prereleases also assign the build to the external group and submit it for TestFlight review. The `testflight-distribute.yaml` workflow can retry external distribution for an already uploaded prerelease build. TestFlight is not an automatic public App Store release; release that build manually through App Store Connect after review.
