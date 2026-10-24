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

The shared scheme includes 48 domain/persistence/Health boundary tests and nine UI checks for logging, cross-session projects, honest recaps, gyms, custom grades, the account portal, and optional media selection, preview, and persistence. UI tests use a separate persistent store and reset only that test store. Tiny bundled route fixtures are seeded into the test app’s Files folder automatically; tests still attach them through the real importer.

Source folders are synchronized with Xcode: adding a Swift file does not require editing the project. `scripts/create_project.py` reproduces the project configuration using Python's standard library. Avoid regenerating after manual project-setting changes without updating that script.

## Implemented in the initial version

- Journal / Projects / Progress tabs, with Settings and history in Journal.
- Start, resume, backdate, edit, finish/review, and delete sessions.
- Keep stable climbs/projects across sessions, with photo previews, a private notebook, and complete attempt history.
- Record additional unlogged batches or whole-session totals, keeping unknown metrics unknown and rejecting contradictions.
- Correct attempt outcomes, day/order/precision, difficulty, dates, and prior history; preserve uncertainty when deleting evidence.
- Read and explicitly link a selected Apple Health climbing workout; refresh/replace/unlink it without changing journal activity.
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

Sessions retain calendar date and original time zone. Attempts retain difficulty descriptors from logging; independent climb UUIDs link project history across sessions. Aggregate recap entries never masquerade as individual attempts.

## Storage and scope

Climbing data and route media stay in the app's local SwiftData store. Apple/Google sign-in uses the providers’ native SDKs; cloud log sync and cloud media upload are not configured. Export backups to Files; uninstalling the app can delete the local log. Grade scales remain separate and are never automatically converted. Backups include saved gyms and media; JSON backup files are limited to 150 MB.

This is a development build. Follow-up work includes broader history filters, goals, rope climbing, an app icon, private synchronization, and device testing. Physical-device signing, OAuth provider IDs, App Store distribution, and cloud sync are not configured. HealthKit read/link behavior and source compatibility require signed physical-device testing; workout export is absent.

See [PRODUCT_REQUIREMENTS.md](PRODUCT_REQUIREMENTS.md) for feature contracts and acceptance gates, [PLAN.md](PLAN.md) for product direction and [DEVELOPMENT.md](DEVELOPMENT.md) for validation status and manual checks.

Repository: [FROZENPOP/ClimbingAppIOS](https://github.com/FROZENPOP/ClimbingAppIOS). The connected GitHub plugin can publish authorized changes; separate local Git authentication is optional.


## Quick use

1. From **Journal**, open **Settings → Saved gyms**, add a gym, and choose its default scale. For custom scales, name the scale and optionally list grade choices.
2. Start a session. Your default gym is selected; each climb inherits that gym and scale. Use the gym menu to switch or add another gym.
3. Type a custom grade or tap a saved choice. Add photos/videos optionally, then Save and log attempts/sends.
4. Open **Settings → Sign in or create an account** for the Apple/Google portal. Provider activation is documented in AUTH_SETUP.md.

Projects can be saved while creating/editing a climb. Use **Choose existing climb or project** in a later session; use **Log a past session** for a recap without individual attempt details. Apple Health linking is available in session details and does not require app login.
