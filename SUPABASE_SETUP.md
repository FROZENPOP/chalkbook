# Friends setup

Friends uses mutual requests, not followers. Groups are deferred. A public account still requires friend-request approval. Each reviewed session snapshot can be Private, Friends, or Public. Private accounts cap Public entries to approved friends. Local journals remain private and offline; this is not full journal synchronization.

## Create the backend

1. Create a Supabase account and a project in your chosen organization/region. Keep the database password outside this repository.
2. In the project SQL Editor, run `supabase/migrations/202610240001_friends.sql` once. It creates profiles, requests/friendships, blocks, reviewed session summaries, and a private reports queue, with row-level security and authenticated mutation functions. Use a dedicated development project first.
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

Apple connection remains deferred until Apple developer/sign-in setup is available. Google-connected Friends does not require paid Apple enrollment in Simulator.

See the official [Google provider setup](https://supabase.com/docs/guides/auth/social-sign-in/auth-google) and [row-level security guide](https://supabase.com/docs/guides/database/postgres/row-level-security).

## Verify with two real test accounts

- Create profiles A and B. Send a request from A; it must stay pending until B accepts. Public profiles also require acceptance. Test decline, cancel, remove and re-request.
- Finish a local session. Choose **Session options → Share / privacy**, select summary fields and audience, inspect the exact preview, and save. Private is the default. A separate caption never copies local notes. No media, exact times, gym locations, or Health values enter the payload.
- Check Friends and shared progress on B. A private entry must stay hidden. A Friends entry appears only after acceptance. A Public entry on a public account is readable by signed-in climbers; switching A’s account to private restricts it immediately at the database.
- Remove the friendship or block the other account; friend-only access must disappear. Unblock from Friends; friendship is not automatically restored.
- Update a shared snapshot explicitly after journal corrections. “Refresh summary from journal” updates the draft; saving is still required. Later note edits never update published content.
- Remove a shared entry or delete its local source session. When connected social functionality is configured, session deletion first removes the remote snapshot; failed removal retains the local session for retry. This initial release requires a connection rather than an offline deletion outbox.
- Test airplane mode: journal logging still works; social mutations show a retryable error and do not claim a successful save. Reopen the app and reconnect. Test sign-out/account switching for data isolation.
- Delete a social profile from its editor; friendships and shared entries cascade away while the local journal remains. This removes social data, not the provider account or Supabase Auth identity.

Add friends searches Supabase by username prefix after a 300 ms debounce. Type 2–24 letters, numbers or underscores, optionally beginning with @. Search returns up to 30 matches; type more to narrow results. Your own account and blocked profiles are excluded. It is no longer limited to a locally loaded discovery list. The shared feed contains the newest 200 visible snapshots; progress totals explicitly cover only these shared entries and preserve unknown denominators. Pagination, remote avatar storage, full private journal sync, and Apple backend authentication are follow-up work.

Backup replacement affects local journal records only; independently published snapshots remain until explicitly removed or the social profile is deleted. Review shares before replacing a journal from a backup.

## Permission tests and moderation

Run `npm install && npm test` in `supabase/tests` with Node available. The pinned PGlite dependency executes the migration and PostgreSQL role/RLS fixtures without a hosted project. Tests cover request ownership, private/friends/public access, account privacy, idempotent snapshot updates, null totals, removal, blocking, reports, and anonymous denial. These do not replace two-user testing against hosted Supabase Auth/PostgREST before release.

Reports are stored in `public.social_reports`, unreadable to app users. Assign a moderator before making the feature available to external testers. In the Supabase dashboard, an authorized moderator can use:

```sql
select id, reporter, target_id, reason, created_at
from public.social_reports order by created_at;
```

No automated moderation, email alerts, or service-role dashboard is shipped in the iOS app. Review reports and take account action through the secured backend. Do not expose this table or administrative credentials to clients.

Current verification: native simulator builds, isolated PostgreSQL permission fixtures, and Google-to-Supabase connection and live username search with the configured account have been verified. Two-account friendship/sharing integration and physical-device verification remain pending.
