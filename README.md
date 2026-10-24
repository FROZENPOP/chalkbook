# Climb Log · iOS

A native, offline-capable personal bouldering log built with SwiftUI, SwiftData, and Swift Charts.

## Development

- Xcode 27.1 (27A9275), Swift 6.4 toolchain; project uses Swift 5 language mode.
- iOS 17.0 minimum deployment target; standard iPhones are the initial supported device family. iPhone Duo and iPad-specific work are deferred.
- Google Sign-In 10.0.0 is pinned through Swift Package Manager; Xcode resolves its dependencies. SwiftUI, SwiftData, PhotosUI, AVKit, and Charts ship with Xcode.
- Guest logging needs no account configuration. See [AUTH_SETUP.md](AUTH_SETUP.md) to enable live Apple and Google sign-in.
- Open `ClimbingApp.xcodeproj`, choose the **ClimbingApp** scheme, select **Climb Log - iPhone 16 (iOS 27.0)**, and Run.
- A physical iPhone requires selecting your own development team in Signing & Capabilities. No team is embedded in this repository.

For a repeatable setup, use the standard-library-only helper. It selects the newest installed runtime compatible with the selected phone and never chooses the Duo:

```sh
python3 scripts/ios_dev.py check
python3 scripts/ios_dev.py run
python3 scripts/ios_dev.py test
python3 scripts/ios_dev.py test --device se
```

The default is iPhone 16; `--device se` uses iPhone SE (3rd generation) for compact-screen checks. Xcode 27 displays simulators in Device Hub. The installed iOS 27.1 runtime supports the Duo only; standard iPhones use the installed iOS 27.0 runtime.

Command-line build:

```sh
xcodebuild -project ClimbingApp.xcodeproj -scheme ClimbingApp \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

List available simulators with `xcrun simctl list devices available`, then use a device's UUID:

```sh
xcodebuild -project ClimbingApp.xcodeproj -scheme ClimbingApp \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test
```

The shared scheme includes 29 unit/persistence tests and UI coverage for logging, gyms, custom grades, the account portal, and optional media selection, preview, and persistence. UI tests use a separate persistent store and reset only that test store. Tiny bundled route fixtures are seeded into the test app’s Files folder automatically; tests still attach them through the real importer.

Source folders are synchronized with Xcode: adding a Swift file does not require editing the project. `scripts/create_project.py` reproduces the project configuration using Python's standard library. Avoid regenerating after manual project-setting changes without updating that script.

## Implemented in the initial version

- Start, resume, backdate, edit, finish, and delete sessions.
- Add/edit/delete climbs with V or Fontainebleau grades, hold color, styles, notes, and previous experience.
- Record unsuccessful attempts and sends, undo the latest attempt, and review attempt history.
- Distinguish flashes, first-try sends this session, and repeats.
- Browse session history by gym or calendar date, with a completed-session filter.
- View activity by week, attempts, sends, completion rate, and highest send per grade scale over 30 days, 90 days, or all time.
- Save gyms, choose a default gym, and switch or add gyms directly from session/climb forms.
- Give each gym its own named scale; type a grade freely or tap a saved grade choice.
- Attach up to 3 route photos or videos (25 MB each) from Photos or Files and view them from the route.
- Sign in/out using Apple or Google once provider setup is complete; each identity has a separate local log.
- Export versioned JSON backups, validate and preview a restore, replace the log with confirmation, and delete local data.
- Save every mutation explicitly; roll back failed changes and show an error.

Sessions store a calendar date separately from timestamps to keep their date stable when traveling. Progress counts each session's climb entry once; linking the same physical climb across sessions is a future projects feature.

## Storage and scope

Climbing data and route media stay in the app's local SwiftData store. Apple/Google sign-in uses the providers’ native SDKs; cloud log sync and cloud media upload are not configured. Export backups to Files; uninstalling the app can delete the local log. Grade scales remain separate and are never automatically converted. Backups include saved gyms and media; JSON backup files are limited to 150 MB.

This is a development build. Follow-up work includes broader history filters, persistent projects, goals, rope climbing, an app icon, cloud sync, and device testing. Physical-device signing, OAuth provider IDs, App Store distribution, and cloud sync are not configured.

See [PLAN.md](PLAN.md) for product direction and [DEVELOPMENT.md](DEVELOPMENT.md) for validation status and manual checks.

Repository: [FROZENPOP/ClimbingAppIOS](https://github.com/FROZENPOP/ClimbingAppIOS). Keep changes local until ready to publish. The connected GitHub plugin can publish changes; separate local Git authentication is optional.


## Quick use

1. Open **Settings → Saved gyms**, add a gym, and choose its default scale. For custom scales, name the scale and optionally list grade choices.
2. Start a session. Your default gym is selected; each climb inherits that gym and scale. Use the gym menu to switch or add another gym.
3. Type a custom grade or tap a saved choice. Add photos/videos optionally, then Save and log attempts/sends.
4. Open **Settings → Sign in or create an account** for the Apple/Google portal. Provider activation is documented in AUTH_SETUP.md.
