# Friends setup

Friends uses mutual requests, not followers. Groups are deferred. A public account still requires friend-request approval. Each reviewed session snapshot can be Private, Friends, or Public. Private accounts cap Public entries to approved friends. Local journals remain private and offline; this is not full journal synchronization.

## Create the backend

1. Create a Supabase account and a project in your chosen organization/region. Keep the database password outside this repository.
2. In the project SQL Editor, run `supabase/migrations/20261025033437_friends.sql` once. It creates profiles, requests/friendships, blocks, reviewed session summaries, and a private reports queue, with row-level security and authenticated mutation functions. Use a dedicated development project first.
3. In **Project Settings → API / API Keys**, copy the Project URL (`https://YOUR_PROJECT_REF.supabase.co`) and a **publishable** key (`sb_publishable_...`). Never put a secret key, service-role key, database password, or Google client secret in the app.
4. Create the ignored file `ClimbingApp/Social/Supabase.local.json`:

   ```json
   {
     "projectURL": "https://YOUR_PROJECT_REF.supabase.co",
     "publishableKey": "sb_publishable_YOUR_KEY"
   }
   ```

   Xcode’s synchronized app folder includes this resource on the next build. Only publishable keys are accepted. The file is intentionally ignored by Git; recreate it on another development machine. The project URL and publishable key are public client configuration, protected by server authorization.

## Connect Google to Supabase

Existing Google sign-in to the local app and signing in to Supabase are separate steps. The native Google SDK supplies an ID token, and Supabase verifies it before issuing its own authenticated session.

1. In Google Cloud project `YOUR_GCP_PROJECT`, open **Google Auth Platform → Clients**. Keep the existing iOS client:
   - Bundle ID: `com.frozenpop.ClimbingApp`
   - iOS client ID: `YOUR_IOS_CLIENT_ID.apps.googleusercontent.com`
   - URL scheme: `com.googleusercontent.apps.YOUR_IOS_CLIENT_ID`
2. Create a **Web application** OAuth client for Supabase. Its Authorized redirect URI is `https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback` (also shown on Supabase’s Google provider screen). No website is needed for the native ID-token flow.
3. In **Supabase → Authentication → Sign In / Providers → Google**, enable Google. Enter client IDs as a comma-separated list, **web client ID first, then the existing iOS client ID**. Put the web client secret only in the Supabase dashboard. Do not put it in an xcconfig, JSON file, or app source.
4. In Google **Data Access**, configure `openid`, `userinfo.email`, and `userinfo.profile`. While the Google app is in Testing, add each test Google account under **Audience → Test users**.
5. Save, rebuild with `python3 scripts/ios_dev.py run --device iphone16`, sign in with Google, open **Friends**, and create a username/display name. This explicitly publishes those two fields; local email, bio and profile photo are not uploaded. Native SDK credentials remain in Keychain; Supabase access tokens are held only in memory and renewed using the native Google identity.

Apple accounts connect too. In **Authentication → Providers → Apple**, enable Apple and add the bundle ID `com.frozenpop.ClimbingApp` under Client IDs; native sign-in needs no secret key. Apple can't re-issue an identity token silently, so the app asks Apple to confirm once (**Continue with Apple** in Friends), then keeps Supabase's rotating refresh token in the Keychain for later launches. Signing out clears it. Google-connected Friends does not require paid Apple enrollment in Simulator.

See the official [Google provider setup](https://supabase.com/docs/guides/auth/social-sign-in/auth-google) and [row-level security guide](https://supabase.com/docs/guides/database/postgres/row-level-security).

## Verify with two real test accounts

- Create profiles A and B. Send a request from A; it must stay pending until B accepts. Public profiles also require acceptance. Test decline, cancel, remove and re-request.
- Finish a local session. Choose **Session options → Share / privacy**, select summary fields and audience, inspect the exact preview, and save. Private is the default. A separate caption never copies local notes. Only explicitly reviewed bounded photo pairs may be included; private markup, full-resolution original files, exact times, gym locations and Health values remain excluded.
- Check Friends and shared progress on B. A private entry must stay hidden. A Friends entry appears only after acceptance. A Public entry on a public account is readable by signed-in climbers; switching A’s account to private restricts it immediately at the database.
- Remove the friendship or block the other account; friend-only access must disappear. Unblock from Friends; friendship is not automatically restored.
- Update a shared snapshot explicitly after journal corrections. “Refresh summary from journal” updates the draft; saving is still required. Later note edits never update published content.
- Remove a shared entry or delete its local source session. A protected, account-scoped removal outbox is saved before local deletion/unsharing, so both complete immediately without waiting for a connection. Friends may still see the snapshot and its photo pairs until removal syncs. Friends and Share / privacy show pending removals with Retry now. A failed local queue write keeps the source session and reports an error instead of losing the removal intent.
- Test airplane mode: journal logging still works; publishing/visibility/photo-draft saves still need a confirmed connection. Snapshot removal and social-profile deletion queue locally with an honest pending state. Reopen the app and reconnect to retry; also verify manual Retry now. Sign-out keeps the queue, other accounts and guests never execute it, and the same owner resumes it after returning.
- Delete a social profile from its editor; a durable deletion intent hides it locally, then the server cascades friendships, shared entries and photo pairs when connected. Until confirmed, creating another social profile or republishing removed content is blocked. The local journal remains. This removes social data, not the provider account or Supabase Auth identity.

Add friends searches Supabase by username prefix after a 300 ms debounce. Type 2–24 letters, numbers or underscores, optionally beginning with @. Search returns up to 30 matches; type more to narrow results. Your own account and blocked profiles are excluded. It is no longer limited to a locally loaded discovery list. The shared feed loads visible snapshots in 20-row session-day/UUID keyset pages; progress totals cover currently loaded entries and preserve unknown denominators. Pending removals stay hidden locally across refreshes. Full private journal sync and Apple backend authentication remain follow-up work.

Backup replacement affects local journal records only; independently published snapshots remain until explicitly removed or the social profile is deleted. Review shares before replacing a journal from a backup.

## Permission tests and moderation

Run `npm install && npm test` in `supabase/tests` with Node available. The pinned PGlite dependency executes the migration and PostgreSQL role/RLS fixtures without a hosted project. Tests cover request ownership, private/friends/public access, account privacy, idempotent snapshot updates, null totals, removal, blocking, reports, and anonymous denial. These do not replace two-user testing against hosted Supabase Auth/PostgREST before release.

Reports are stored in `public.social_reports`, unreadable to app users. Assign a moderator before making the feature available to external testers. In the Supabase dashboard, an authorized moderator can use:

```sql
select id, target_username, reason, comment_id, entry_id, content, created_at
from public.social_reports where reviewed_at is null order by created_at;

-- Remove what breaks the rules, then close the report.
delete from public.session_comments where id = '<comment_id>';
delete from public.shared_sessions where id = '<entry_id>';
delete from auth.users where id = '<target_id>'; -- removes the whole account
update public.social_reports set reviewed_at = now() where id = '<report id>';
```

Review new reports within a day. Reports keep a copy of the reported text and outlive both accounts for up to 12 months, as the privacy policy says. A database trigger rejects a short list of objectionable words in comments, captions, names and bios (`social_private.reject_objectionable`); edit the list there. Do not expose this table or administrative credentials to clients.

### Edge functions

Deploy `supabase/functions/revoke-apple` and `supabase/functions/report-alert`, keeping JWT verification on, then set these secrets in the Supabase dashboard. Never commit them.

- `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (the full `.p8` file from a Sign in with Apple key) and `APPLE_CLIENT_ID` (`com.frozenpop.ClimbingApp`). Without these, Apple accounts still delete, but the app tells the person to remove Chalkbook from their Apple Account themselves.
- `REPORT_ALERT_WEBHOOK_URL`, a Discord or Slack webhook. Without it, new reports raise no alert.

### Privacy policy

The policy is `ClimbingApp/App/privacy.html`, shown in the app from Settings and Join Friends. Host the same file at an HTTPS address for App Store Connect, and update both when it changes.

Current verification: native simulator builds, isolated PostgreSQL permission fixtures, and Google-to-Supabase connection and live username search with the configured account have been verified. Two-account friendship/sharing integration and physical-device verification remain pending.

## Profiles, ranked discovery, reactions, and friend invitations

For a fresh project, apply `supabase/migrations/20261026223012_profiles_search_reactions.sql` after the original migration, then `supabase/migrations/20261026223942_social_access_audit.sql`. These are already applied to the current development project. It adds optional profile details, ranked name/username search, and one replaceable reaction per person/session. Existing journals and shared session rows are retained. New clients show a migration-required message until this is applied.

Profile photos are opt-in 256-pixel JPEGs (at most 64 KiB), re-encoded without original metadata. Their base64 copies and short bios are stored in a separate RLS-protected table rather than a public storage bucket. Private accounts expose details only to their owner and accepted friends. Public account details are visible to authenticated climbers, subject to blocks. Local profile data is copied into the publication draft only when requested.

Search accepts names or usernames, ranks exact usernames first, and limits results to 30. Reactions are applause, fire, or strong; tap the selected reaction again to remove it. Session access and blocking apply to both reaction reads and writes. No comments, messages, groups, or contact upload are added.

The app registers `climblog://friend/UUID`. The QR screen and share action use that installed-app link until a web host is configured. For HTTPS invitations, host `web/friend-invites/invite.html` and set optional `inviteWebBaseURL` in the local JSON configuration. See that folder’s README for static hosting and the separate universal-link association step. Opening any invitation shows a profile for review and never sends or accepts a friend request automatically.

Before release, test two real accounts: private bio/photo denial before friendship, access after acceptance, revocation on removal/block, changing/removing a photo, exact-name search ordering, reaction update/removal, and access denial after making a shared entry private. Assign report moderation as described above. The current hosted database deployment is complete. HTTPS invite hosting still needs a website host/domain; the default Supabase backend hostname does not host the landing page.

## Offline removal queue

Removal intents use a versioned, atomic, file-protected JSON sidecar in Application Support/RemovalOutboxes/<provider-account-hash>, following the local profile storage pattern. It contains content/source UUID, kind, Supabase owner UUID, creation date, attempt count, sanitized last error and next-attempt date; no captions, photos, Health values, keys or tokens. It is outside journal backups. Existing installations first opened offline may lack a cached Supabase UUID: their intent is scoped to the provider account hash and is bound only after that same account successfully authenticates. A different verified Supabase UUID is rejected. Signing out does not erase queued work.

Launch/foreground, successful sign-in/session refresh and successful authenticated social requests trigger bounded retries (up to ten per trigger). Network failures use exponential 30-second to six-hour backoff and stop the batch. HTTP 401/403 pause automatic retries, retain the intent and show an access message; Retry now after reviewing/signing in bypasses the date but never the account check. Missing content/already-removed is successful; a missing RPC/schema is not. The existing owner-checked remove_shared_session RPC is idempotent and cascades reviewed photo pairs; no hosted migration is required. An in-flight publish/save finishes before queued deletion executes.

Removing an individual photo in the recap editor edits a reviewed replacement draft; saving that draft (like other publishing/visibility edits) still requires a connection. Removing the whole recap queues removal of all its photo pairs. Social-profile deletion uses the existing cascading RPC and clears superseded owner removals only after server confirmation. No new background mode, reachability service, private-journal sync or automatic publication is introduced.
