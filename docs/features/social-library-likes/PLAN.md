# Plan: Social Library — Friend-Visible Likes

**Status**: Done
**Created**: 2026-04-26
**Last updated**: 2026-04-27
**Repos**: `xomify-backend` (Python Lambdas), `xomify-ios` (SwiftUI)

## Summary
Friends can see each other's **Likes count** on the profile stats row and drill into a friend-scoped **Likes page**. Today both surfaces are self-only because Spotify's `/me/tracks` is scoped to the authenticated user — the backend stores nothing about anyone's saved tracks. This plan adds backend persistence (push from iOS on cold open) plus two new endpoints, then un-gates the iOS Likes chip + destination on friend profiles.

Success: viewing a friend's profile shows a `Likes` chip with a real number, and tapping it loads that friend's most-recent saved tracks paginated from the backend.

## Goal & Non-Goals

### Goals
- Friend profile header shows a `Likes` count chip (alongside Friends / Ratings / Posts).
- Tapping the chip navigates to a Likes list scoped to the friend, paginated.
- Per-user opt-out via `likesPublic: Bool` (default ON, toggle in settings to flip OFF).
- Backwards compatible: missing `likesCount` on `FriendProfile` still renders today's 4-stat header (chip just hides).

### Non-Goals
- **Recently played is OUT of scope.** Dom confirmed we ship likes-social first and decide on recently-played as a follow-up.
- No real-time sync — push only happens on cold open (and is deduped backend-side).
- No infra changes in this plan. New API GW routes are flagged as a sub-task for `xomify-infrastructure` (Terraform).
- No Watch / widget surfaces.

## Architecture

```
+----------------+        cold-open hook         +-----------------------+
|   iOS app      | ----------------------------> |  POST /likes/push     |
| (viewer self)  |   {email, total, tracks[]}    |  lambdas/likes_push   |
+----------------+                               +-----------+-----------+
                                                             |
                                                             v
                                                  +----------+-----------+
                                                  |  users table:        |
                                                  |   likes_count        |
                                                  |   likes_updated_at   |
                                                  |   likes_public       |
                                                  |  user_likes table:   |
                                                  |   (email, trackId)   |
                                                  |   addedAt + meta     |
                                                  +----------+-----------+
                                                             |
+----------------+    GET /friends/profile        +----------+-----------+
|   iOS app      | <----------------------------- | friends_profile      |
| (viewing other)|   FriendProfile.likesCount     |   reads likes_count  |
+--------+-------+                                +----------------------+
         |
         |  tap Likes chip
         v
+----------------+    GET /likes/by-user           +---------------------+
|  LikesView     | -----------------------------> | lambdas/likes_by_user|
| (friend scope) |  ?email=me&targetEmail=friend  |  friendship check    |
+----------------+                                |  paginated read      |
                                                  +---------------------+
```

**Roll-out order** (matters — don't ship out of sequence):
1. Backend schema lands first (writers + readers ready).
2. Backend `/likes/push` lands so iOS has a target.
3. iOS push hook ships (no UI change yet — backfills data for a few days).
4. Backend `/likes/by-user` + `friends_profile` enrichment land.
5. iOS un-gates chip + ships friend-scoped LikesView.

## Schema Decision

### Chosen: **Option A — separate `user_likes` items table + counters on user record**

**Rationale**:
- Pagination depth isn't artificially capped at 200. Power users with 5K+ likes would get truncated under Option B.
- Keeps the user record small and hot. JSON blobs (Option B) inflate the user item, making every read of the user record more expensive.
- DynamoDB pricing favors many small items over fat ones for paginated access patterns.
- Friend likes-page reads only touch the `user_likes` table; the user record only stores `likes_count`, `likes_updated_at`, `likes_public`. Clear separation.

**Schema**:

```
users table (existing) — add columns:
  likes_count: Number          # cached total
  likes_updated_at: String     # ISO8601, last successful push
  likes_public: Bool           # default true, settings toggle flips

user_likes table (new):
  PK: email (String)
  SK: addedAt#trackId (String)   # composite, sortable desc by addedAt
  Attributes:
    trackId, trackName, artistName, albumArt, addedAt
  GSI (optional): by_track for "who liked this" — not needed v1
```

Pagination: query by `email` PK, `ScanIndexForward=False`, `LastEvaluatedKey` cursor maps to iOS `offset`/`hasMore` pattern.

**v1 cap**: push only the most-recent 200 saved tracks per cold-open sync. Top-200 covers the vast majority of "recent likes" UX needs and bounds the Spotify rate-limit blast radius (4 calls @ 50/page). Future opens catch up incrementally.

## Affected Files / Components

### xomify-backend (Python)

| File / Component | Change | Why |
|------------------|--------|-----|
| `lambdas/common/users_dynamo.py` (or equivalent) | Add `set_user_likes(email, count, updated_at, tracks)` and `get_user_likes(email, limit, cursor)` helpers | Centralized DAL for the new fields/table |
| `lambdas/common/share_visibility.py` (reference) | Reuse the friendship-check pattern | Don't reinvent auth — match existing convention |
| `lambdas/likes_push/handler.py` (new) | POST `/likes/push` — write counter + items, dedupe if unchanged within N hours | iOS sync target |
| `lambdas/likes_push/requirements.txt` (new) | Standard lambda deps | New lambda boilerplate |
| `lambdas/likes_by_user/handler.py` (new) | GET `/likes/by-user` — friendship-gated paginated read | Friend likes page data source |
| `lambdas/likes_by_user/requirements.txt` (new) | Standard lambda deps | New lambda boilerplate |
| `lambdas/friends_profile/handler.py` | Add `likesCount` (and `likesUpdatedAt` if cheap) to response payload, only when `likes_public == true` | Powers friend chip without extra round-trip |
| `tests/likes_push/` (new) | pytest: dedupe, schema validation, opt-out honored | Coverage |
| `tests/likes_by_user/` (new) | pytest: friendship enforcement, pagination, opt-out 403 | Coverage |
| `tests/friends_profile/` | Update to assert `likesCount` present when public, absent when private | Coverage |

**Infra (NOT in this plan, flag separately)**:
- `xomify-infrastructure` Terraform: add `/likes/push` (POST) and `/likes/by-user` (GET) routes to API Gateway, wire to new lambdas. Track as a sub-task issue.

### xomify-ios (SwiftUI)

| File / Component | Change | Why |
|------------------|--------|-----|
| `Xomify-iOS/Models/SocialModels.swift:596` (`FriendProfile`) | Add `likesCount: Int?`, `likesUpdatedAt: String?` | Carry new backend fields |
| `Xomify-iOS/Services/XomifyService.swift` | Add `pushUserLikes(email:total:tracks:)`, `getLikesByUser(email:targetEmail:limit:offset:)`. Use verb-disambiguated paths (`/likes/push`, `/likes/by-user`) per the comment at line 471 | New backend API calls |
| `Xomify-iOS/Models/SocialModels.swift` (response types) | Add `LikesPushResponse`, `LikesByUserResponse` Codables | Decode new endpoints |
| App cold-open hook (likely `Xomify_iOSApp.swift` or `MainShell.task` — confirm during execute) | After auth resolves, fire-and-forget call to `pushUserLikes` with top-200 saved tracks | Backend gets data without blocking UI |
| `Xomify-iOS/ViewModels/UserProfileViewModel.swift:243` (`loadOtherHeader`) | After existing assignments, set `likesCount = profile.likesCount` | Surface the new field to the view |
| `Xomify-iOS/Views/Profile/ProfileHeaderView.swift:130` | Replace `if viewModel.context.isSelf, let likesCount = ...` with `if let likesCount = viewModel.likesCount` so the chip renders for both self and friend when data is available | Un-gate the chip |
| `Xomify-iOS/ViewModels/Profile/LikesViewModel.swift` | Parameterise with `enum LikesSource { case spotifyDirect; case backend(targetEmail: String) }`. `.spotifyDirect` keeps today's path for self; `.backend` calls `getLikesByUser`. Single VM, one branch on source | Avoid duplicating fetch/paging logic across two VMs |
| `Xomify-iOS/Views/Profile/LikesView.swift` | Accept optional `targetEmail: String?` init param; route to `LikesViewModel(source: targetEmail.map { .backend(targetEmail: $0) } ?? .spotifyDirect)` | Same view, different data source |
| Sidebar/destination router (wherever `.likes` is resolved) | When opening from a friend profile, pass `targetEmail = friendProfile.email` | Friend chip drill-down hits backend |
| `Xomify-iOS/Views/Settings/...` | Add toggle: "Show my likes to friends" bound to backend `likes_public` field (new endpoint or extend existing settings PATCH) | Privacy opt-out |
| `Xomify-iOS/XomifyTests/...` | Unit tests for new VM source branching + service methods (URL construction, decoding) | Coverage |

**Choice: parameterised VM, NOT sibling FriendLikesView.**
The fetch + paging + skeleton logic is identical; only the data source differs. Branching at the source level keeps the view tree, navigation, and tests unified. Risk is small — single `switch` in the load function.

## Implementation Steps

### Phase 1 — Backend schema + migration (xomify-backend PR #169) ✅ MERGED
- [x] Branch `feature/social-library-likes-phase-1-schema-helpers` off `master` in `xomify-backend`.
- [x] Add `likes_count`, `likes_updated_at`, `likes_public` to `users` table model + DAL helpers (DynamoDB is schemaless — just write the new attributes; default `likes_public=true` on read miss).
- [x] Create `user_likes` DynamoDB table definition (Terraform stub or document for infra repo). Add a feature-flagged code path that no-ops if the table doesn't exist yet.
- [x] Unit tests for new DAL helpers (mock DynamoDB) — 19 tests.
- [x] PR review + merge.

### Phase 2 — Backend `/likes/push` lambda (xomify-backend PR #170) ✅ MERGED
- [x] New `lambdas/likes_push/` lambda. Body: `{email, total, tracks: [{trackId, addedAt, name, artist, albumArt}]}`.
- [x] Validate payload (cap `tracks` length at 200 server-side; reject >).
- [x] Dedupe: if `total == existing likes_count` AND first track's `addedAt` matches cached `likes_updated_at`, skip the items write (still refresh timestamp). Simpler than the original 6h time-window — equivalent behaviour for "nothing changed since last sync."
- [x] Honor `likes_public=false`: still accept the push (we cache for the user's own use), just don't expose downstream.
- [ ] Emit CloudWatch metric on push count + dedupe hits — deferred (no metrics infrastructure in repo today; structured log lines cover the same observability need).
- [x] pytest: happy path, dedupe path, oversize payload (capped not rejected), malformed payload rejected, cross-user push rejected — 12 tests.
- [x] Coordinate API GW route addition with infra (documented in PR body).
- [x] PR review + merge.

### Phase 3 — Backend `/likes/by-user` lambda (xomify-backend PR #171) ✅ MERGED
- [x] New `lambdas/likes_by_user/` lambda. Query: `email` (caller, via authorizer fallback), `targetEmail`, `limit` (default 50, max 200 — bumped from 100 to match push cap), `offset`.
- [x] Friendship check: caller must be `email == targetEmail` OR an accepted friend of `targetEmail`. New `are_users_friends` helper in `friendships_dynamo.py` (single GetItem, accepted-status check).
- [x] Opt-out check: if `targetEmail`'s `likes_public == false` AND caller isn't self → 401 (AuthorizationError; effectively 403-equivalent surface).
- [x] Paginated read of `user_likes` by `email` PK, sorted desc by `addedAt`. Return `{tracks, total, hasMore, likesPublic}` (added `likesPublic` so iOS can sync the toggle without an extra round-trip).
- [x] pytest: friendship enforced, opt-out enforced, pagination boundary, self-read bypasses friendship check — 8 lambda tests + 6 helper tests.
- [x] PR review + merge.

### Phase 4 — Backend `friends_profile` enrichment + `users_set_likes_public` (xomify-backend PR #172) ✅ MERGED
- [x] Read `likes_count`, `likes_updated_at`, `likes_public` from target user record.
- [x] Include `likesCount` in response **only when** `likes_public == true` OR caller is target. (Field omitted otherwise — iOS hides chip when absent.)
- [x] New `lambdas/users_set_likes_public/` lambda — POST `/users/likes-public` body `{email, value: bool}`. Auth: requestor == email.
- [x] pytest: friends_profile present-when-public, absent-when-private, present-for-self, lookup-failure-doesn't-500. users_set_likes_public happy/cross-user/missing/non-bool/stringy-bool — 11 new tests.
- [x] PR review + merge. **Backend chain complete.**

### Phase 5 — iOS service methods + push hook (xomify-ios PR #97) ✅ MERGED
- [x] Branch `feature/social-library-likes-phase-5-service` off `master`. Bumped version to 1.13.0.
- [x] Add `pushUserLikes(email:total:tracks:)`, `getLikesByUser(...)`, `setLikesPublic(...)` to `XomifyService`. Verb-disambiguated paths: `/likes/push`, `/likes/by-user`, `/users/likes-public`.
- [x] Add `LikesPushResponse` / `LikesByUserResponse` / `LikesPushTrack` / `LikesByUserTrack` Codables in `SocialModels.swift`.
- [x] Cold-open hook confirmed: `MainShell.task`. `LikesPushCoordinator` actor added; fires once per process lifetime via `Task.detached`.
- [x] Coordinator paginates `/me/tracks` up to 200 tracks (4 pages × 50), then calls `pushUserLikes`. Never blocks UI.
- [x] `XomifyServiceProtocol` and `MockXomifyServiceProtocol` updated with new method stubs.
- [x] xcodebuild green; PR merged.

### Phase 6 — iOS un-gate chip + read `likesCount` (xomify-ios PR #98) ✅ MERGED
- [x] Bumped version to 1.14.0.
- [x] Added `likesCount: Int?` and `likesUpdatedAt: String?` to `FriendProfile`.
- [x] In `loadOtherHeader`, set `likesCount = profile.likesCount`.
- [x] In `ProfileHeaderView`, removed `viewModel.context.isSelf` gate — chip renders for both self and other when `likesCount != nil`. Chip auto-hides when nil.
- [x] Friend profile chip routes to `.likes` as placeholder (Phase 7 wires `.friendLikes`).
- [x] `MockXomifyServiceProtocol.getFriendProfileResponse` updated with new fields.
- [x] xcodebuild green; PR merged.

### Phase 7 — iOS friend-scoped LikesView (xomify-ios PR #99) ✅ MERGED
- [x] Bumped version to 1.15.0.
- [x] Refactored `LikesViewModel` to take `source: LikesSource` enum (`.spotifyDirect | .backend(callerEmail:targetEmail:)`). `.spotifyDirect` preserves existing Spotify path; `.backend` calls `getLikesByUser`. Unified display via `LikesTrackDisplayItem`.
- [x] `LikesView` accepts `targetEmail: String?` init param; default nil for back-compat.
- [x] Added `friendLikes(email: String)` case to `SidebarDestination`; routed in `MainShell.destinationRoot`.
- [x] `ProfileHeaderView`: `.other` chip tap navigates to `.friendLikes(email: profileEmail)`; `.me` navigates to `.likes`.
- [x] Settings: added Privacy section with "Show my likes to friends" toggle (`likesPublic` → `setLikesPublic`).
- [x] `ProfileLikesViewModelTests` updated to use `LikesViewModel(source: .spotifyDirect)` + `vm.items`; new `test_backendSource_populatesItemsFromBackend`.
- [x] xcodebuild green; PR merged.

## Out of Scope
- Recently-played social surface (separate plan).
- "Who else liked this track" reverse lookup.
- Real-time push / websocket sync.
- Watch / widget integration.
- Backfill job for existing users (we accept that early adopters' counts populate organically as they re-open the app).
- API Gateway Terraform changes (separate `xomify-infrastructure` sub-task).

## Risks / Tradeoffs

- **Sync write storm**: 1K users opening the app simultaneously = 1K writes to `user_likes`. Mitigation: dedupe guard in `/likes/push` skips items write when `total` unchanged within 6h. Each user effectively pushes ~once per day under normal usage.
- **Friendship-check latency on `/likes/by-user`**: every paginated request re-runs the friendship check. Mitigation: cache friendship in lambda warm-instance memory keyed by `(caller, target)` for 60s. Acceptable staleness — a freshly-removed friend can read one more page.
- **Spotify rate limits**: capping initial sync at top-200 (4 calls @ 50/page) keeps us well under the per-user budget. Power users with 10K likes won't get full sync — acceptable for v1; Spotify itself only shows recents in most surfaces.
- **Privacy**: shipping with `likes_public = true` default means existing users have likes exposed on next deploy. Mitigation: opt-out toggle in settings ships in PR #3, and the v1 launch comms call this out. Alternative (default OFF) was considered but kills v1 utility — every chip would be empty until users discover the toggle.
- **Stale counts after Spotify unlikes**: if a user unlikes a track outside the app, our count is stale until next cold open. Acceptable — recency window is hours, not days, for active users.
- **`user_likes` table size growth**: 200 items × 100K users = 20M items. DynamoDB handles this trivially; cost is the concern. Monitor; consider TTL on items beyond top-200 if cost becomes meaningful.

## Open Questions

- [ ] **Cold-open hook location**: confirm the exact file/function during Phase 5 (likely `Xomify_iOSApp.swift` `.task` or `MainShell` first-load) — flagged because Glob/Grep tooling unavailable during planning.
- [ ] **Settings PATCH for `likes_public`**: extend an existing settings endpoint or add a tiny new lambda? Default to extending if one exists; otherwise new lambda `lambdas/user_settings_patch/`.
- [ ] **Pagination depth cap on `/likes/by-user`**: 200 (matches push cap), 1000, or unlimited? Recommend 200 for v1 to match what we actually persist; revisit if push cap raises.
- [ ] **`likesUpdatedAt` UI surfacing**: do we render "updated 2h ago" anywhere, or just consume internally? Recommend internal-only for v1; revisit if users complain of staleness.
- [ ] **Schema confirmation**: Option A is recommended above — Dom to ack before flipping to Ready.

## Skills / Agents to Use

- **ios-standards** (skill): for SwiftUI VM refactor in Phase 7 — confirm `@Observable`, async/await, strict concurrency conventions.
- **python-lambda-standards** (skill, if it exists in xomify-backend): for new lambda boilerplate, structured logging, error envelope.
- **test-writer** (agent): generate pytest for backend phases 2/3/4 and XCTest for iOS phases 5/6/7.
- **pr-writer** (agent): each phase's PR description should reference this plan and the phase number.
