# Apple and Google sign-in setup

The app contains native Apple and Google sign-in integrations, an account portal in Settings, Keychain session storage, local sign-out, and separate local databases for each provider/account. The tracked provider configuration is blank. Google sign-in requires a valid iOS client ID, callback scheme, and a build with working Keychain signing. Sign in with Apple has its own team/App ID/capability requirements.

The portal keeps providers disabled when their identifiers/configuration are missing. It never simulates a successful sign-in. Guest logging, gyms, custom grades, and media remain usable without an account.

## Local build configuration

Create `Configuration/Auth.local.xcconfig` (ignored by Git):

```xcconfig
DEVELOPMENT_TEAM = YOUR_APPLE_TEAM_ID
APPLE_SIGN_IN_ENABLED = YES
GOOGLE_CLIENT_ID = YOUR_IOS_CLIENT_ID.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.YOUR_IOS_CLIENT_ID
```

Use the exact reversed client ID from Google Cloud Console; the example above is illustrative. These are public identifiers, not client secrets. Never embed an OAuth client secret, service-account key, or Apple signing private key in the app.

The tracked `Configuration/Auth.xcconfig` includes this local file when present. `Info.plist` registers the Google callback scheme from these values. Signing remains automatic once a team is selected.

## Apple

1. Select your development team for the ClimbingApp target in Xcode.
2. Register the bundle ID `com.frozenpop.ClimbingApp` in that team, or choose an available bundle ID and update both providers to match it.
3. Enable Sign in with Apple for that App ID and the target's Signing & Capabilities. The entitlement file is already present.
4. Set `APPLE_SIGN_IN_ENABLED = YES` in the local configuration and rebuild with signing enabled.
5. Test on a signed build with a real Apple account. Check initial authorization, returning sign-in, cancellation, credential revocation, relaunch, and local sign-out.

Apple reference: [Sign in with Apple entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.applesignin).

## Google

1. Create or select a Google Cloud project and configure its OAuth consent screen.
2. Create an **iOS OAuth client** for the exact app bundle ID; add the Apple team ID if requested by the console.
3. Copy the client ID and reversed client ID into the local configuration above. Add test users while the consent screen is in testing mode.
4. For Simulator, run `python3 scripts/ios_dev.py run`: it uses local ad-hoc signing and an unsynced build cache so Keychain works, without paid Apple membership. For a physical iPhone, configure Apple development signing in Xcode.
5. Test browser-based sign-in, callback handling, cancellation, relaunch/restore, expired credentials, and sign-out.

Google Sign-In 10.0.0 is pinned through Swift Package Manager; its official SwiftUI button, authentication flow, callback handler, and credential restoration are used. The SDK manages its tokens. Unavailable-provider/guest builds do not attempt Keychain access. Signed-in builds use Keychain. The app stores only the selected account's provider, stable subject, name, and optional email in its own Keychain entry.

Google references: [Project configuration](https://developers.google.com/identity/sign-in/ios/start-integrating), [Sign-in integration](https://developers.google.com/identity/sign-in/ios/sign-in), and [SDK releases](https://github.com/google/GoogleSignIn-iOS/releases).

## Local account behavior

- Guest data stays in the original local database, including existing V1 logs that migrate to V2.
- Each signed-in identity has its own database and media. Storage directory names are SHA-256 hashes of provider + stable subject; email addresses are not used as identifiers.
- Signing out returns to the guest log. It does not delete account data or revoke the provider's entire account authorization.
- Signing back into the same identity on this iPhone reopens its local database. Apple and Google identities are not automatically linked by email.
- To move a guest log into an account, export a backup before signing in, then restore it in that account. Restore requires explicit replacement confirmation.
- A previously signed-in user's local log remains available during a temporary network failure; known credential revocation/no-auth states clear the session.

This version has no server-side account database, API session, cloud sync, or cloud media upload. A future backend must verify provider identity tokens server-side before granting access to remote data; client profile fields alone are not server authentication. Do not expose backend endpoints that trust an arbitrary client-supplied user ID.


Route attachments can be chosen from Photos or Files. The app’s Documents folder is available through Files for user-supplied source files; private account databases and attached media live separately under Application Support. Import copies file contents into the selected account’s store, so removing an attachment does not delete the source file from Photos or Files.

## Apple Health configuration

The entitlement and read-purpose string are present. Enable HealthKit for the chosen App ID/team and target before signed-device testing. The implementation requests **read** access only to climbing workouts, active energy, and heart rate when the user explicitly chooses the session linking action. No Health write entitlement purpose, workout recording, background delivery, export, or wearable compatibility is advertised. Health links/statistics are omitted from JSON backup and private account movement.

### Simulator Keychain errors

A configured client ID does not prove secure credential storage works. The earlier `CODE_SIGNING_ALLOWED=NO` launcher left only a linker signature, without normal app signing/entitlements. The updated helper uses Xcode local simulator signing (`CODE_SIGN_IDENTITY=-`) and builds outside synced Documents folders. A dedicated test writes, reads, and removes a fixture under a separate Keychain service; it never signs in a fake account or touches the current account’s item. Complete Google authorization still requires the user’s real account consent.

After the first successful provider sign-in on this installation, the app offers local profile setup. Users can choose their own display name, an optional photo, and a short bio; editing these later never changes the provider subject or sign-in email. Profiles stay isolated per provider identity, including separate guest information, and remain on the phone after sign-out.
