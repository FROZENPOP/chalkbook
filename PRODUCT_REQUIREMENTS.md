# Private climbing journal

The app is an offline, iPhone-first journal for indoor bouldering. Logging, projects, recaps, correction, history, and progress work without an account, Health access, a gym integration, or a backend. Minimum deployment remains iOS 17. Standard iPhones take priority; Duo, iPad-specific work, Apple Watch, outdoor guidebooks, subscriptions, AI coaching, messaging, and gym administration are deferred.

## Implemented journeys

| Journey | Implementation |
| --- | --- |
| Log while climbing | Journal starts or resumes the single active session. Create an unnamed climb or choose an existing climb/project. The selected climb persists; large Failed/Sent controls record individual outcomes with a short accidental-tap debounce. Undo uses persisted records and works after relaunch. Finish opens a review. |
| Resume a project | Projects are a status on a stable climb UUID. Active, observed/historically declared sent, and archived states; photo previews; editable private notebook entries; complete attempt history across sessions; Try this session reuses the same climb. Matching color/grade never merges climbs. |
| Recap afterward | Journal → Log a past session creates a completed recap, with optional known duration. Recalled activity accepts nullable attempts and sends, with explicit additional-batch or whole-session coverage. Individual remembered attempts are a separate, deliberate input with day precision. |
| Reflect and correct | Journal contains history and Settings. Edit session dates/times/notes, difficulty/prior history, individual outcomes/day/order/precision, notebook entries, media, gyms, and recalled batches. Progress has time filters, text equivalents, duration/frequency charts, evidence/completeness labels, and separate difficulty contexts. |
| Health read and link | Contextual read authorization, nearby climbing workouts with source/date/duration/overlap, explicit selection/replacement, per-workout available energy/heart rate, refresh/unlink, duplicate UUID prevention, similar-record warnings, and integration-off cleanup. Optional nullable effort/HR/calorie trends and dated RHR/HRV context are merged in main (Health insights, PR #2). Real-device acceptance remains pending. |
| Hold Highlight v1 | Merged in main (PR #1): private on-device color selection, tolerance, reset/cancel and saved annotation settings, with original photo bytes preserved. Polish, multiple selections and opt-in reviewed photo pairs are included in this cumulative source (#5). |
| Friends and reviewed sharing | Mutual requests with explicit acceptance, public/private social profiles, and individually Private/Friends/Public session snapshots. Supabase schema/client/UI are in main and deployed to `climbing-app-dev`, with hosted permission audits passed. Two-account/device UI validation remains outstanding. No groups, followers, fake feed, or automatic uploads. |

## Domain contracts

- Stable UUIDs for sessions, climbs, attempts, aggregates, notes, media, gyms, and Health links. Sessions retain their original time zone. Timestamps and order are stored; summaries are derived.
- Every newly logged attempt has a session UUID, a climb relationship, stable order, outcome, precision, and a difficulty descriptor snapshot. Legacy attempts are backfilled during migration.
- A climb's original-session relationship is retained solely for migration compatibility. A nullifying many-to-many association supports subsequent sessions. Session deletion explicitly removes its attempts/aggregates/Health link while preserving climb identities, notebooks, and media. Removing project status preserves everything else.
- A successful first recorded attempt is not automatically a flash. Plain Swift rules produce confirmed / not flash / unknown with a reason. Earlier failures and prior attempts/completion prevent confirmation. Deleting historical evidence marks history incomplete; explicit Undo reverses a mistaken logging action. The editor requires an explicit completeness declaration to clear missing-history uncertainty.
- Recalled totals never create attempts or establish flashes, ordering, or distinct climbs. Whole-session values replace the corresponding metric rather than adding to detailed evidence. Additional batches are disjoint. Negative, contradictory, duplicated whole-metric coverage, and totals below evidence are rejected before mutation. Unknown metrics remain nullable.
- When expanding recalled activity into details, explicitly reduce/remove its batch first. Manual-entry input requires acknowledgement; live logging with additional batches asks whether the attempt is new disjoint activity. Whole totals must still cover all detailed evidence.
- Difficulty supports exact, range, color, combined color/range, and unknown. Scales and gyms stay separate; no arithmetic/conversions on grade labels. Current climb edits preserve attempt snapshots unless the user explicitly chooses to correct old difficulty too. Local gym color guides are descriptions, copied into new climbs and snapshots.
- Flash denominators include only sent climbs whose prior history is known. Distinct climbs use UUIDs, not session rows or remembered send totals. Grade distributions use recorded snapshots; recalled activity is excluded from attempt-level analysis.

## Persistence, privacy, and accessibility

One SwiftUI app with feature folders, SwiftData, Observation, Swift Charts, and test targets. `JournalRules.swift` contains plain domain counting/classification. HealthKit has a narrow injectable reader. No generic repository framework or per-feature packages.

Frozen V1/V2 schemas preserve existing installations. V3 retains the initial journal development schema. V4 adds Health link metadata and color guides; V5 adds local gym addresses and Maps-backed gym autocomplete; current V6 adds a pinned notebook note and normalized private route-photo markup; the custom migration freezes legacy attempt descriptors before future edits. Store-open failures display a retry screen and never erase data. Editors retain drafts on failed saves; logging failures roll back and remain visible for retry.

Media imports finish reading and validation before any database mutation. SwiftData manages transactional external binary storage in Application Support; this intentionally uses its managed references and cleanup instead of a second hand-maintained file ledger. Thumbnail previews are regenerated from originals. Files and Photos source items are never deleted. Protected local directories/store files and protected temporary video copies are used; media/notes/measurements are not printed by application diagnostics. Video support is retained from the earlier app as an optional feature.

Backup JSON V6 retains pinned notes/photo markup, includes versioned multiselection hold-highlight settings, and preserves independent/orphan projects, links between journal records, notes, recalled batches, difficulty snapshots, gyms, and media checksums. V1–V5 JSON remains importable. Health links/measurements and authentication tokens are excluded; restore requires replacement confirmation and is idempotent by journal UUID. Restore clears Health links, so the user must link again. Each provider identity and the guest have separate local stores/preferences; no private synchronization exists yet.

Semantic typography, text alongside colors/icons, large primary controls, 44-point action targets, adaptive vertical metric/button layouts at accessibility sizes, accessible labels, and chart text equivalents are implemented. Native system transitions respect Reduce Motion; custom animation is unnecessary. Simulator checks cannot replace physical VoiceOver and real-world usability checks.

## Ordered acceptance gates

| Milestone | State and outstanding gate |
| --- | --- |
| 1. Complete local journal | Implemented. Domain/persistence and simulator journey tests provide evidence. iOS 17 runtime, physical VoiceOver, airplane-mode usability, low-storage interruption, and on-device Photos checks remain release gates. |
| 2. HealthKit linking | Read/link and optional Health insights are implemented and merged in main (PR #2), with substitute/rule/UI tests. Requires a signed physical iPhone with Health capability for authorization, partial availability, delayed delivery, and each advertised wearable/source. No source compatibility is claimed. |
| 3. Accounts and private sync | Optional Apple/Google portal and local account isolation are implemented; Google-to-Supabase Simulator authentication is verified. Supabase managed backend/social owner authorization are deployed. Apple provider/signed-device checks remain. Private-journal sync still needs explicit idempotent guest attachment, sync authorization, revisions/outbox/tombstones, multi-device convergence, destructive-conflict handling and provider/server-account deletion. Health stays outside normal sync. |
| 4. Friends and reviewed recaps | Implemented in main and deployed to `climbing-app-dev`: mutual friend requests, public/private account privacy, separate reviewed session snapshots, database authorization, blocking/unblocking, reporting and a private moderation queue. The `friends` (`20261025033437`), `profiles_search_reactions` (`20261026223012`) and `social_access_audit` (`20261026223942`) migrations are applied and hosted API permission audits passed (SUPABASE_AUDIT.md). Two-account/device UI journeys remain a release gate. Groups, followers, comments and messaging are excluded. Source deletion waits for remote removal; an offline outbox remains follow-up work. See SUPABASE_SETUP.md. |
| 5. Optional workout export | Deferred. Requires separate write consent, app-owned manual workout provenance, stable sync identifiers/versions, an export ledger, repeat-export replacement, and exclusion of imported/app-origin loops. Journal must work without write authorization. |

Health read authorization never reveals denied read access. Empty results say “No accessible data found.” Missing statistics stay unavailable, not zero. Linking does not create/modify manual activity, infer unrelated samples, auto-merge candidates, or write workouts. No third-party strain/readiness/recovery score is assumed. The optional app effort estimate is explicitly labeled and documented in DEVELOPMENT.md; recovery context reports dated measurements without inventing a readiness score.

## Ordered merge pass — included in this source

- [PR #4](https://github.com/FROZENPOP/ClimbingAppIOS/pull/4): actionable Projects empty states; no backend dependency.
- [PR #5](https://github.com/FROZENPOP/ClimbingAppIOS/pull/5): hold-highlight polish and separately reviewed original/highlighted shared photo pairs. Hosted migration `20261030005609_shared_route_photo_pairs` is deployed and audited; the app change is included here.
- [PR #6](https://github.com/FROZENPOP/ClimbingAppIOS/pull/6): suggested friends, dismissal persistence and discovery opt-out. Hosted migration `20261030061722_suggested_friends` is deployed and its hosted audit passed, recorded in `e3320ab`; the app change is included here.

- [PR #7](https://github.com/FROZENPOP/ClimbingAppIOS/pull/7): documentation status refresh.
- [PR #8](https://github.com/FROZENPOP/ClimbingAppIOS/pull/8): Friends activity uses bounded keyset pages with retry, de-duplication and refresh; existing visibility/block policies apply to every page, with no backend change.

This source includes #4–#8; GitHub merges remain a separate supervisor action in the approved #4–#8 order. SUPABASE_AUDIT.md retains both hosted deployment records, with migration filenames and SQL unchanged. Shared photos require explicit review and remain owner/friends-only even on public summaries; private notes, Health values and full-resolution original files are never published. Suggested friends respect accepted mutual connections, blocks, pending requests, opt-outs and dismissals, without exposing friend lists. PLAN.md ends with the remaining work in priority order.

The supplied Windows/empty-workspace inspection statement is superseded: development here is on a Mac with Xcode and an existing repository. See DEVELOPMENT.md for actual test evidence and unverified items.
