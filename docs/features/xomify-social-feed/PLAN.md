# Plan: Xomify Social Feed (Epic)

**Status**: Ready
**Type**: Epic
**Created**: 2026-04-17
**Last updated**: 2026-04-17 (open questions resolved)
**Owner**: Dominick
**Repos touched**: `xomify-ios`, `xomify-backend`, `xomify-frontend`
**Source brainstorm**: [BRAINSTORM.md](./BRAINSTORM.md)

---

## Summary

Ship the full "BeReal for music" social layer across the three-repo ecosystem: a friend-scoped shares feed with per-share interactions (queue + rate), group-based feed filtering, APNs push + daily digest, and an X/Twitter-style navigation shell on iOS. No MVP staging — build the whole thing in one coordinated epic, delivered as an ordered series of sub-feature PRs via `/orchestrate`.

Success = Dom and 4 friends can open the iOS app, see each other's recent shares filtered by group, queue a track in one tap, rate it, and get a push when ≥3 friends queue something they shared. Backend and Angular web client stay in parity.

---

## Scope

### In scope (locked by BRAINSTORM Decisions, 2026-04-17)

- **Share atom**: `{trackUri, sharedBy, sharedAt, caption?, moodTag?, genreTags?}`. Caption ≤140 chars. `moodTag` single enum (hype / chill / sad / party / focus / discovery). `genreTags` array of strings, ≤3.
- **Fan-out model**: fan-out-on-read. New `shares` table keyed by `sharedBy`; feed lambda queries each accepted friend in parallel, merge-sorts by timestamp, applies group filter.
- **Audience model**: built for a real social feed with group filters; dogfooded with 5 friends first. No cold-start/invite flow in v1.
- **Signal loop**: `share_interactions` table. Per-share, per-viewer queue-add + rating tracked. Surfaces "queued by N friends" chip on feed items and who-queued-who-rated on sharer's profile.
- **Notifications**: APNs device-token storage, per-sharer push at ≥3 friend-queues threshold, **weekly** digest cron at a fixed UTC time (per-user time selection deferred — see Locked Answers).
- **Groups**: reused as feed filter chips, not as shared queues. iOS gets a groups management UI (create / add member / remove member / list). Existing `groups_add_song` / `groups_song_status` lambdas remain deployed but get no iOS UI.
- **Ratings integration**: reuse existing `ratings_track` / `ratings_publish`. Share cards show sharer's rating inline if present. Rating from the feed writes back to the existing ratings table.
- **iOS navigation**: X/Twitter-style. Persistent header (avatar → drawer, "Xomify" wordmark center; search icon dropped from v1 — see Locked Answers). 4 bottom tabs: `Home` · `Feed` · `Releases` · `Builder`. Drawer holds: Profile, Stats (Top Items + Wrapped sub-nav), Following, Friends (+ invite-a-friend), Groups, Ratings history, Settings, Help/About, Sign out.
- **Feed screen**: persistent header + horizontal filter chips (`All Friends`, per-group) + feed cards (queue / rate / "queued by N" chip) + pull-to-refresh + FAB compose.
- **Pre-plan cleanup**: purge the stray `Xomfit/` tree (blocks all other work).
- **Frontend parity**: Angular schema updates to match new `shares_*` endpoints where the existing `social/` and `share.service.ts` surfaces diverge.

### Out of scope (explicit)

- Stories / 24h ephemeral shares.
- Friend-of-friend discovery, public profiles.
- Reply-with-a-song threading.
- Groups-as-shared-queue UI (backend lambdas stay; no iOS UI).
- Album-level or playlist-level shares (track-only in v1).
- Abuse tooling (rate-limit, block, report) beyond what the existing friends graph provides.
- In-app full-text search. **Search icon dropped from v1 header** per Locked Answers.
- Per-user digest time-of-day selection. **Weekly fixed-UTC cron for v1** per Locked Answers; harden to per-user timing later.
- **Xomify Angular web app cleanup** (broken/unused top-nav tabs). Tracked separately — see Related Work below.

---

## Critical decisions already locked (do not re-litigate)

Lifted verbatim from `BRAINSTORM.md` → `DECISIONS (2026-04-17)`:

1. **Share atom**: track + optional caption + optional tags (mood/genre). Both caption and tags are in scope.
2. **Fan-out**: fan-out-on-read. Rationale: built for 5 friends now but must scale to "a real social feed of all your friends, filterable by groups you create." Read-time fan-out handles both — the friend-list-to-query grows naturally, and group filters are trivially expressible as "intersect fan-out source with group members."
3. **Audience**: dogfood with 5 friends, but built to support real social-feed usage with group filters. No MVP staging.
4. **Scope override**: "Full throttle, don't stage it out — build the whole thing."
5. **Navigation**: X/Twitter-style; 4 bottom tabs (Home · Feed · Releases · Builder); drawer holds everything else.
6. **Naming**: the social tab is `Feed`, not `Social`.
7. **Groups**: filter layer only; not shared queues. Management UI shipped on iOS.

Any sub-feature plan that wants to deviate from these must surface the delta to Dominick first.

---

## Locked answers to prior open questions (2026-04-17)

1. **APNs cert**: provisioned. Auth Key (`.p8`) at `/Users/dom/Downloads/AuthKey_A5X4MKX38D.p8`. Key ID: `A5X4MKX38D`. Team ID and iOS Bundle ID to be confirmed before `backend-interactions-and-notifications` starts (Team ID from Apple Developer account → Membership; Bundle ID from `Xomify-iOS.xcodeproj` → Info.plist). **Security action required**: move the `.p8` out of `~/Downloads` and upload to **AWS Secrets Manager** as `xomify/apns/auth-key` — do **not** commit the file to any repo. The `notifications_send` lambda reads from Secrets Manager at cold start.
2. **Search icon**: dropped from v1. Header is avatar top-left + "Xomify" wordmark center only. Re-scope later if/when we know what to search. Model/implementation stays permissive so we can add it later without a redesign.
3. **Spotify ToS on denormalized track metadata**: accepted. Denormalize `trackName` / `artistName` / `albumName` / `albumArtUrl` into the `shares` row for read performance. Matches how Spotify permits caching of track metadata for authenticated-user contexts. Dom will spot-check current developer ToS once before `backend-shares` ships.
4. **Cold start / invite flow**: **in scope**. Scope additions:
   - `ios-friends-management` gets an **Invite a Friend** button → iOS share sheet with deep link (TBD scheme, e.g. `https://xomify.app/invite/<code>`).
   - `ios-feed` empty-state design gets a dual CTA: "Invite a friend" (primary) + "Post your first share" (secondary → opens composer).
   - Backend: new lightweight `invite_create` lambda + `invites` table to mint deep-link codes tied to sender email. Recipient signup flow auto-friends the sender. Folded into `backend-shares` scope (same sub-feature so we don't create an 11th).
5. **Digest cadence**: **weekly, fixed UTC** for v1. Drop `digestTime` field from `device_tokens` schema; keep `digestEnabled` / `queueNotificationsEnabled`. Cron (`cron_shares_digest`) runs once per week (suggested: Sunday 18:00 UTC) instead of every-15-minute per-user bucketing. Simpler ops surface; per-user timing is a post-launch hardening task.

## Related work (tracked separately, not part of this epic)

- **xomify-frontend cleanup**: Angular app has several broken / unused top-nav tabs. Flagged 2026-04-17 by Dom. To be planned under its own brainstorm + plan cycle in `xomify-frontend`. Not blocking this epic.

---

## Sub-features

Each entry below becomes its own sub-feature plan via `/orchestrate xomify-social-feed`. Each sub-feature gets its own `docs/features/<sub-feature>/PLAN.md` with file-level steps. Do **not** expand those here.

| # | Sub-feature | Scope | Repos | One-liner | Depends on |
|---|-------------|-------|-------|-----------|------------|
| 1 | `repo-cleanup` | S | ios | Purge stray `Xomfit/` tree, unstage ~40 files, `.gitignore` hygiene. | — |
| 2 | `ios-nav-shell` | M | ios | New persistent header (avatar / wordmark / search), side drawer, 4-tab bar restructure. | 1 |
| 3 | `backend-shares` | M | backend | `shares` + `invites` DynamoDB tables + `shares_create` / `shares_feed` / `shares_delete` / `shares_user` / `invite_create` / `invite_consume` lambdas behind JWT authorizer. GSI for track-level lookup. | 1 |
| 4 | `backend-interactions-and-notifications` | L | backend | `share_interactions` table, `shares_interaction` lambda, `device_tokens` table, APNs send lambda, daily digest cron. | 3 |
| 5 | `ios-feed` | L | ios | Feed tab: feed list, share card, queue/rate actions, filter chips from groups, composer sheet + FAB, offline cache. Empty state has dual CTA ("Invite a friend" + "Post your first share"). | 2, 3 |
| 6 | `ios-groups-management` | M | ios | Drawer-resident Groups screen: list / create / add-member / remove-member. Wires to existing `groups_*` lambdas. | 2 |
| 7 | `ios-friends-management` | M | ios | Drawer-resident Friends screen: requests / pending / accepted / accept / reject / remove, plus **Invite a Friend** CTA (share-sheet deep link via new `invite_create` lambda). | 2, 3 |
| 8 | `ios-drawer-residents` | M | ios | Profile, Stats (Top Items + Wrapped sub-nav), Following, Ratings history, Settings, Help/About, Sign out. Mostly relocating existing views + one new combined Stats view + new Ratings history view. | 2 |
| 9 | `ios-notifications` | M | ios | APNs permission flow, device-token registration call, in-app signal UI (who-queued-who-rated on profile/share card), push-open deep links. | 2, 4 |
| 10 | `frontend-parity` | S–M (TBD) | frontend | Angular updates to match final `shares_*` schema. Touch: existing `social/`, `share.service.ts`, any affected page models. Detail deferred to sub-feature plan after #3 schema lands. | 3, 4 |

---

## Dependency graph

```
1. repo-cleanup
        │
        ├─► 2. ios-nav-shell ──┬─► 5. ios-feed ◄── 3. backend-shares
        │                      │                         │
        │                      ├─► 6. ios-groups-mgmt    │
        │                      │                         ▼
        │                      ├─► 7. ios-friends-mgmt   4. backend-interactions-and-notifications
        │                      │                         │
        │                      ├─► 8. ios-drawer-residents
        │                      │                         │
        │                      └─► 9. ios-notifications ◄┘
        │
        └─► 3. backend-shares ─► 4. backend-interactions-and-notifications ─► 10. frontend-parity
```

Suggested execution order (topological): `1 → 2 & 3 (parallel) → 4 → 6 & 7 & 8 (parallel, all unblocked once 2 ships) → 5 → 9 → 10`.

Each sub-feature ships as its own PR. Ordering above guarantees no PR breaks master.

---

## Schema additions (new DynamoDB tables)

Match existing xomify-backend table conventions (see `lambdas/common/friendships_dynamo.py`, `groups_dynamo.py`, `track_ratings_dynamo.py`). Exact table names / capacity to be finalized in `backend-shares` sub-feature plan.

### `shares`

- **PK**: `sharedBy` (string, user email)
- **SK**: `sharedAt#shareId` (string — ISO8601 timestamp + UUID v4, lexicographic sort = reverse-chrono with `ScanIndexForward=false`)
- **Attributes**:
  - `shareId` (UUID)
  - `trackId`, `trackUri`, `trackName`, `artistName`, `albumName`, `albumArtUrl` (denormalized from Spotify for render speed)
  - `caption` (optional, ≤140 chars)
  - `moodTag` (optional, enum: `hype|chill|sad|party|focus|discovery`)
  - `genreTags` (optional, list of strings, ≤3)
  - `createdAt` (ISO8601)
- **GSI**: `track-shares-index` — PK=`trackId`, SK=`sharedAt`. Supports "who else shared this track" lookup.

### `share_interactions`

- **PK**: `shareId`
- **SK**: `viewerEmail#action` (e.g. `alice@...#queued`, `alice@...#rated`)
- **Attributes**:
  - `viewerEmail`, `action` (`queued` | `rated`)
  - `rating` (int 1–5, present only when action=`rated`)
  - `createdAt`
  - `sharedBy` (denormalized for reverse lookup / notification fan-out)
- **GSI**: `viewer-interactions-index` — PK=`viewerEmail`, SK=`createdAt`. Supports "my recent queue/rate activity" for profile stats.

### `device_tokens`

- **PK**: `email`
- **SK**: `deviceToken` (APNs token string)
- **Attributes**:
  - `platform` (`ios`)
  - `digestEnabled` (bool)
  - `queueNotificationsEnabled` (bool)
  - `createdAt`, `updatedAt`
- **Note**: per-user `digestTime` dropped for v1 — digest is a weekly fixed-UTC cron. Add back when per-user timing is hardened post-launch.

### `invites`

- **PK**: `inviteCode` (short URL-safe string, e.g. 8-char base32)
- **Attributes**:
  - `senderEmail`
  - `createdAt`
  - `consumedAt` (null until used)
  - `consumedBy` (recipient email, null until used)
  - `expiresAt` (ISO8601, default +30 days)
- **GSI**: `sender-invites-index` — PK=`senderEmail`, SK=`createdAt`. Supports "my outstanding invites."

---

## New lambda surface

All behind the existing JWT `authorizer`. Follow existing single-purpose handler pattern (see `lambdas/friends_list/handler.py`, `lambdas/ratings_track/handler.py`). Response shapes use `success_response` from `common/utility_helpers.py`.

### `shares_create` — `POST /shares/create`

- **Request**:
  ```json
  {
    "email": "alice@...",
    "trackId": "...", "trackUri": "spotify:track:...",
    "trackName": "...", "artistName": "...", "albumName": "...", "albumArtUrl": "...",
    "caption": "optional ≤140",
    "moodTag": "hype | chill | sad | party | focus | discovery",
    "genreTags": ["..."]
  }
  ```
- **Response**: `{ "shareId": "...", "sharedAt": "..." }`

### `shares_feed` — `GET /shares/feed`

- **Query**: `email`, optional `groupId`, optional `limit` (default 50), optional `before` (timestamp for pagination)
- **Behavior**: fetch accepted friends from `friendships_dynamo.list_all_friends_for_user`; if `groupId`, intersect with `list_members_of_group`; parallel `Query` each `shares` PK with `ScanIndexForward=false`; merge-sort by `sharedAt`; enrich each share with `queuedCount`, `ratedCount`, `viewerHasQueued`, `viewerRating` from `share_interactions`; enrich with sharer's own rating from `track_ratings`.
- **Response**: `{ "shares": [Share...], "nextBefore": "timestamp|null" }`

### `shares_delete` — `DELETE /shares/delete`

- **Query**: `email`, `shareId`, `sharedAt`
- **Auth check**: requester email == `sharedBy`
- **Response**: `204 No Content`

### `shares_user` — `GET /shares/user`

- **Query**: `email` (requester), `targetEmail`, optional `limit`
- **Behavior**: returns one user's shares. Used by profile views on iOS and Angular.
- **Response**: `{ "shares": [Share...] }`

### `shares_interaction` — `POST /shares/interaction`

- **Request**: `{ "email": "...", "shareId": "...", "sharedBy": "...", "action": "queued|rated", "rating": 1-5 (if rated) }`
- **Behavior**: write to `share_interactions`; if action=`queued`, count total queued for this share and trigger APNs push to `sharedBy` when crossing the 3-friend threshold; if action=`rated`, also upsert into existing `track_ratings` so ratings stay canonical.
- **Response**: `{ "queuedCount": n, "ratedCount": m }`

### `device_token_register` — `POST /notifications/register`

- **Request**: `{ "email", "deviceToken", "digestEnabled", "queueNotificationsEnabled" }`
- **Response**: `{ "ok": true }`

### `invite_create` — `POST /invites/create`

- **Request**: `{ "email": "sender@..." }`
- **Behavior**: mint 8-char base32 code, write to `invites` table with `expiresAt = now + 30d`, return deep-link URL.
- **Response**: `{ "inviteCode": "...", "inviteUrl": "https://xomify.app/invite/<code>" }`

### `invite_consume` — `POST /invites/consume`

- **Request**: `{ "email": "recipient@...", "inviteCode": "..." }`
- **Behavior**: validate code not expired / not consumed; mark consumed; auto-create accepted friendship between sender and recipient via existing `friendships_dynamo` helpers.
- **Response**: `{ "ok": true, "senderEmail": "..." }`

### `notifications_send` — internal invoke only

- Not HTTP-exposed. Invoked by `shares_interaction` (queue threshold) and `cron_shares_digest`.
- Wraps APNs HTTP/2 send. Reads token + prefs from `device_tokens`.

### `cron_shares_digest` — EventBridge rule, runs weekly (Sunday 18:00 UTC)

- Scan `device_tokens` for all users with `digestEnabled = true`.
- For each, run `shares_feed` logic for the last **7 days**, build digest payload ("N new shares from your friends this week"), invoke `notifications_send`.
- Pattern mirrors existing `cron_release_radar` / `cron_wrapped`. Per-user time-of-day bucketing is deferred post-launch.

---

## iOS new models

New types live in `Models/XomifyModels.swift` (or a split file `Models/SocialModels.swift` if the former is getting crowded — sub-feature plan to decide). camelCase to match backend.

- `Share` — mirrors the share atom + interaction counts (`queuedCount`, `ratedCount`, `viewerHasQueued`, `viewerRating`, `sharerRating`).
- `FeedResponse` — `{ shares: [Share], nextBefore: String? }`.
- `CreateShareRequest` — for the composer.
- `ShareInteraction` — request/response for queue/rate events.
- `MoodTag` (enum, 6 cases, Codable via raw string).
- `GroupFilter` — light wrapper over existing group list item (id + name) for filter chip rendering.
- `DeviceTokenRegistration` — payload for APNs registration call.
- `DigestPreferences` — mirrors `digestEnabled` / `queueNotificationsEnabled`. (`digestTime` deferred.)
- `InviteLink` — `{ inviteCode, inviteUrl, expiresAt }` for the share-sheet flow.
- `Friend`, `FriendRequest`, `FriendsListResponse` — for Friends management screen (mirrors `friends_list` response).
- `Group`, `GroupMember`, `GroupsListResponse`, `GroupInfoResponse` — for Groups management screen (mirrors existing `groups_list` / `groups_info`).
- `UserRatingHistoryItem` — for Ratings history drawer screen.

---

## iOS file/folder changes (phase-level)

### New folders

- `Xomify-iOS/Views/Feed/` — Feed tab surfaces (feed view, share card, composer, filter chips, FAB).
- `Xomify-iOS/Views/Social/` — drawer-resident screens that are social-graph-oriented (Friends, Groups, Ratings history).
- `Xomify-iOS/Views/Shell/` — new nav shell (persistent header, drawer, tab bar host).
- `Xomify-iOS/ViewModels/Feed/` — `FeedViewModel`, `ShareComposerViewModel`, `ShareCardViewModel`.
- `Xomify-iOS/ViewModels/Social/` — `FriendsViewModel`, `GroupsViewModel`, `RatingsHistoryViewModel`.
- `Xomify-iOS/Services/NotificationsService.swift` — APNs registration + token handoff to backend.

### Files modified

- `Xomify-iOS/Views/MainTabView.swift` — gutted and replaced by new shell host; tab set reduced to 4 (`Home` / `Feed` / `Releases` / `Builder`).
- `Xomify-iOS/Services/XomifyService.swift` — extended with `createShare`, `getFeed`, `deleteShare`, `getUserShares`, `recordShareInteraction`, `registerDeviceToken`, `listFriends` / `acceptFriend` / `rejectFriend` / `removeFriend` / `requestFriend`, `listGroups` / `createGroup` / `addGroupMember` / `removeGroupMember` / `groupInfo`, `getRatingsHistory`.
- `Xomify-iOS/Models/XomifyModels.swift` — new model types listed above.
- `Xomify-iOS/XomifyApp.swift` (or equivalent app entry) — APNs registration hook on app launch.
- Existing `ProfileView`, `WrappedView`, `TopItemsView`, `ReleaseRadarView` views relocated where needed (most stay in tabs; Wrapped + Top Items get combined under a new Stats drawer screen).

### Files deleted (repo-cleanup)

- All of `Xomfit/` (~40 staged files) — not referenced by the xcodeproj, unrelated fitness app bleed-in.
- `.gitignore` gets entries to prevent recurrence if that project re-clones into this tree.

---

## Testing strategy

- **Lambda (pytest)**: unit tests per new handler mirroring existing `tests/test_groups_*.py` / `tests/test_friends_*.py` patterns. Mock DynamoDB via moto; mock APNs send. Coverage targets: `shares_create` (validation + write), `shares_feed` (fan-out merge + group filter + interaction enrichment), `shares_interaction` (threshold trigger), `cron_shares_digest` (time-bucket matching). One integration test per sub-feature wiring real DynamoDB-local.
- **iOS (XCTest)**: ViewModel tests for `FeedViewModel` (loading / filter swap / queue / rate), `ShareComposerViewModel` (validation), `FriendsViewModel`, `GroupsViewModel`, `NotificationsService` (token lifecycle). Service-layer tests for each new `XomifyService` method with mocked `NetworkService`. Snapshot tests for share card and composer sheet — optional, sub-feature call.
- **Integration (manual, dogfood)**: post-deploy smoke with 5-friend cohort: share → push fires at 3rd queue → digest arrives at user-chosen time → rating from feed lands in ratings history. Capture findings in `.claude/memory/session-log.md`.
- **Angular parity**: existing specs in `xomify-frontend/src/app/**/*.spec.ts` updated as schema changes land; sub-feature plan #10 enumerates exact specs to touch.

---

## Rollout / deployment

- Epic ships as **10 independent PRs**, one per sub-feature, in dependency order.
- Each PR is independently deployable and revertable: backend lambdas deploy via existing GitHub Actions path-filtered workflow; iOS sub-features ship in a single TestFlight build (accumulate on `master`, build on merge to a release branch).
- TestFlight cut happens after `ios-feed` (#5) lands; subsequent iOS sub-features layer in successive builds for the dogfood cohort.
- Feature flags **not** required — scope is friend-group-only and can be soft-launched to a 5-person TestFlight ring.
- Frontend parity (#10) ships last; Angular can run against new endpoints with graceful-degrade readers for missing `shares_*` surfaces until ready.

---

## Risks / tradeoffs

- **Fan-out-on-read scaling**: fine for 5–200 friends, pain point at 1k+. Accepted tradeoff per BRAINSTORM; revisit at 1k DAU — migration to hybrid model is non-trivial but the `shares` table schema survives.
- **Spotify ToS on track metadata persistence**: we denormalize `trackName` / `artistName` / `albumName` / `albumArtUrl` into the `shares` table. Spotify ToS permits caching track metadata so long as it's refreshable and not surfaced outside the Spotify-auth'd user context. Flagging for explicit confirmation — see Open Questions.
- **APNs cert provisioning**: new infra surface. If the Apple Developer account doesn't already have an APNs Auth Key issued, that's a ~1-day blocker before `backend-interactions-and-notifications` can end-to-end test. See Open Questions.
- **Drawer vs tab bar discoverability**: demoting Profile/Stats/Friends/Groups into a drawer reduces their discoverability vs the current tab-per-feature layout. Accepted tradeoff — drawer scales with future drawer-resident features, tab bar doesn't.
- **Schema drift between iOS and Angular**: backend is the source of truth; Angular #10 ships last and reconciles. Risk: if Angular is in active use during the iOS dogfood window, its social/share pages may render stale shapes until #10 merges. Mitigation: ship backend responses with additive fields only (no breaking rename of existing fields).
- **Groups-as-filter conceptual overload**: existing `groups_*` lambdas still support shared-queue use (`groups_add_song`, `groups_song_status`). The backend supports both meanings simultaneously; iOS only exposes the filter meaning. Risk: future developer assumes iOS's view of groups is complete. Mitigation: document in the sub-feature plan and in backend README.

---

## Open questions

All prior blockers resolved (see Locked Answers). Remaining known-unknowns, to be answered inside their respective sub-feature plans:

- [ ] **APNs Team ID + iOS Bundle ID** — needed to configure `notifications_send` lambda. Team ID from Apple Developer → Membership; Bundle ID from `Xomify-iOS.xcodeproj` / Info.plist. Resolve inside `backend-interactions-and-notifications` sub-feature plan.
- [ ] **Deep link scheme for invites** — `https://xomify.app/invite/<code>` (universal link, requires `apple-app-site-association` on xomify.app) vs custom scheme `xomify://invite/<code>`. Universal link is better UX; requires domain-hosted file. Resolve inside `backend-shares` + `ios-friends-management` sub-feature plans.
- [ ] **Frontend parity deadline** — does Angular need to ship in lockstep with iOS TestFlight, or can it lag by a week? Default assumption: Angular lags by one week; TestFlight dogfood proceeds on iOS alone. Resolve inside `frontend-parity` sub-feature plan.

---

## Skills / Agents to use

- **backend-engineer agent**: authoring the 3 new tables + 7 new lambdas. Already knows the `common/` patterns and `handle_errors` / `success_response` conventions.
- **ios-engineer agent**: nav shell, Feed UI, composer, drawer screens. Must respect MVVM constraint from `.claude/CLAUDE.md` — views never touch `XomifyService` directly.
- **code-reviewer agent**: run between sub-features on every PR before merge.
- **test-writer agent**: pair on pytest + XCTest coverage per sub-feature.
- **docs-writer agent**: produce the per-sub-feature `PLAN.md` documents during `/orchestrate`, using this epic plan as input.

---

## Next step

1. Review this plan. Flag any locked decisions you want to revisit.
2. Answer the open questions above (APNs cert, search behavior, Spotify ToS, digest UX, frontend cadence) — these don't block `/orchestrate` but will block specific sub-features.
3. Flip **Status** from `Draft` to `Ready`.
4. Run `/orchestrate xomify-social-feed` to break this into the 10 sub-feature plans with their own `PLAN.md` files under `docs/features/<sub-feature>/`.
5. Run `/execute <sub-feature>` per sub-feature in the dependency order above.
