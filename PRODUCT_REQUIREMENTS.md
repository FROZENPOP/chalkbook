# Private climbing journal

The app is an offline, iPhone-first journal for indoor bouldering. Logging, projects, recaps, correction, history, and progress work without an account, Health access, a gym integration, or a backend. Minimum deployment remains iOS 17. Standard iPhones take priority; Duo, iPad-specific work, Apple Watch, outdoor guidebooks, subscriptions, AI coaching, messaging, and gym administration are deferred.

## Implemented journeys

| Journey | Implementation |
| --- | --- |
| Log while climbing | Journal starts or resumes the single active session. Create an unnamed climb or choose an existing climb/project. The selected climb persists; large Failed/Sent controls record individual outcomes with a short accidental-tap debounce. Undo uses persisted records and works after relaunch. Finish opens a review. |
| Resume a project | Projects are a status on a stable climb UUID. Active, observed/historically declared sent, and archived states; photo previews; editable private notebook entries; complete attempt history across sessions; Try this session reuses the same climb. Matching color/grade never merges climbs. |
| Recap afterward | Journal → Log a past session creates a completed recap, with optional known duration. Recalled activity accepts nullable attempts and sends, with explicit additional-batch or whole-session coverage. Individual remembered attempts are a separate, deliberate input with day precision. |
| Reflect and correct | Journal contains history and Settings. Edit session dates/times/notes, difficulty/prior history, individual outcomes/day/order/precision, notebook entries, media, gyms, and recalled batches. Progress has time filters, text equivalents, duration/frequency charts, evidence/completeness labels, and separate difficulty contexts. |
| Health read and link | Contextual read authorization, nearby climbing workouts with source/date/duration/overlap, explicit selection/replacement, per-workout available energy/heart rate, refresh/unlink, duplicate UUID prevention, similar-record warnings, and integration-off cleanup. Real-device acceptance remains pending. |
| Later share | Deliberately absent until real server authorization and synchronization exist. No Friends tab, fake feed, or simulated published activity. |

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

Frozen V1/V2 schemas preserve existing installations. V3 retains the initial journal development schema. Current V4 adds Health link metadata and color guides; the custom migration freezes legacy attempt descriptors before future edits. Store-open failures display a retry screen and never erase data. Editors retain drafts on failed saves; logging failures roll back and remain visible for retry.

Media imports finish reading and validation before any database mutation. SwiftData manages transactional external binary storage in Application Support; this intentionally uses its managed references and cleanup instead of a second hand-maintained file ledger. Thumbnail previews are regenerated from originals. Files and Photos source items are never deleted. Protected local directories/store files and protected temporary video copies are used; media/notes/measurements are not printed by application diagnostics. Video support is retained from the earlier app as an optional feature.

Backup JSON V3 includes independent/orphan projects, links between journal records, notes, recalled batches, difficulty snapshots, gyms, and media checksums. V1/V2 JSON remains importable. Health links/measurements and authentication tokens are excluded; restore requires replacement confirmation and is idempotent by journal UUID. Restore clears Health links, so the user must link again. Each provider identity and the guest have separate local stores/preferences; no private synchronization exists yet.

Semantic typography, text alongside colors/icons, large primary controls, 44-point action targets, adaptive vertical metric/button layouts at accessibility sizes, accessible labels, and chart text equivalents are implemented. Native system transitions respect Reduce Motion; custom animation is unnecessary. Simulator checks cannot replace physical VoiceOver and real-world usability checks.

## Ordered acceptance gates

| Milestone | State and outstanding gate |
| --- | --- |
| 1. Complete local journal | Implemented. Domain/persistence and simulator journey tests provide evidence. iOS 17 runtime, physical VoiceOver, airplane-mode usability, low-storage interruption, and on-device Photos checks remain release gates. |
| 2. HealthKit linking | Read/link code and substitute/rule tests implemented. Requires a signed physical iPhone with Health capability for authorization, partial availability, delayed delivery, and each advertised wearable/source. No source compatibility is claimed. |
| 3. Accounts and private sync | Existing Apple/Google portal and local account isolation remain. Live OAuth requires provider IDs/team. Managed backend, owner authorization, explicit idempotent guest attachment, revisions/outbox/tombstones, multi-device convergence, destructive conflict handling, and server account deletion are not implemented. Health stays outside normal sync. |
| 4. Friends and reviewed recaps | Deferred behind milestone 3. Private profiles, approved followers, follower-only independent recap drafts/preview/publish/update/delete, visibility enforcement, blocking/reporting, and an actionable moderation queue are required. Omit comments/messages initially. Never include private notebook/health fields. Source deletion should default to recap deletion and show pending server removal offline. |
| 5. Optional workout export | Deferred. Requires separate write consent, app-owned manual workout provenance, stable sync identifiers/versions, an export ledger, repeat-export replacement, and exclusion of imported/app-origin loops. Journal must work without write authorization. |

Health read authorization never reveals denied read access. Empty results say “No accessible data found.” Missing statistics stay unavailable, not zero. Linking does not create/modify manual activity, infer unrelated samples, auto-merge candidates, or write workouts. No readiness/strain/recovery scores are assumed.

The supplied Windows/empty-workspace inspection statement is superseded: development here is on a Mac with Xcode and an existing repository. See DEVELOPMENT.md for actual test evidence and unverified items.
