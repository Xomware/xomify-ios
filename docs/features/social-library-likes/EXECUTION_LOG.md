# Execution Log: Social Library — Friend-Visible Likes

## 2026-04-26 — Backend Phases 1-4 (xomify-backend)

All four backend PRs landed in a single autonomous session, each as its
own branch off `master` so they merge independently.

### PR #169 — `feat: user_likes schema + counters + helpers` ✅ MERGED
- Branch: `feature/social-library-likes-phase-1-schema-helpers`
- Added constants `USER_LIKES_TABLE_NAME` + `USER_LIKES_EMAIL_ADDED_INDEX`.
- New helper module `lambdas/common/user_likes_dynamo.py`:
  - `set_user_likes_count(email, count, updated_at?)`
  - `get_likes_settings(email)` — returns `{likes_count, likes_updated_at, likes_public}` with safe defaults.
  - `set_likes_public(email, value)`
  - `upsert_user_likes(email, tracks)` — batch-write, capped at 200.
  - `query_user_likes(email, limit, offset)` — newest-first, returns `{tracks, total, hasMore}`.
- Helpers gracefully no-op (write) / return empty (read) when `USER_LIKES_TABLE_NAME` is unset, so phase-1 ships before infra provisions the table.
- 19 unit tests added (`tests/test_user_likes_dynamo.py`).
- One small rebase to resolve a constants-file conflict with the parallel `TOP_ITEMS_CACHE_TABLE_NAME` constant from another in-flight PR — kept both.

### PR #170 — `feat: /likes/push lambda + route` ✅ MERGED
- Branch: `feature/social-library-likes-phase-2-likes-push`
- New `lambdas/likes_push/` (POST `/likes/push`).
- Body: `{email, total, tracks: [{trackId, addedAt, name?, artist?, albumArt?}]}`.
- Auth: `body.email` MUST equal resolved caller (cross-user push -> 401).
- Track cap: 200 enforced server-side as defense in depth.
- Throttle: skip items batch-write when `total == cached_count` AND first track's `addedAt == cached_updated_at`. Timestamp still refreshed.
- Response: `{throttled, written, likesCount, likesUpdatedAt}`.
- 12 unit tests added (`tests/test_likes_push.py`).

### PR #171 — `feat: /likes/by-user lambda + route` ✅ MERGED
- Branch: `feature/social-library-likes-phase-3-likes-by-user`
- New `lambdas/likes_by_user/` (GET `/likes/by-user`).
- Query: `targetEmail` (required), `limit` (default 50, max 200), `offset` (default 0). Caller email via authorizer-context fallback.
- Auth gate order: self-access bypasses everything; otherwise friendship-required, then privacy-required.
- New helper `are_users_friends(email, other_email)` in `friendships_dynamo.py` — single GetItem, accepted-status check.
- Response includes `likesPublic` so iOS can sync the toggle in a single round-trip.
- 14 unit tests added (8 lambda + 6 helper) — `tests/test_likes_by_user.py`, `tests/test_friendships_dynamo_are_friends.py`.

### PR #172 — `feat: friends_profile likesCount + users_set_likes_public lambda` ✅ MERGED
- Branch: `feature/social-library-likes-phase-4-enrich-and-public-toggle`
- `friends_profile/handler.py` now includes `likesCount` in the response when target has `likes_public=true` OR caller==target. Lookup failures degrade to absent field (no 500).
- New `lambdas/users_set_likes_public/` (POST `/users/likes-public`). Body: `{email, value: bool}`. Cross-user toggle -> 401. Strict bool coercion (accepts JSON `true/false` or stringy `"true"/"false"`).
- Response: `{email, likesPublic}`.
- 11 new unit tests (4 friends_profile, 7 users_set_likes_public).

### Test Health
- Baseline before phase 1: 314 passing.
- After all four phases: 395 passing — 81 new tests, 0 regressions.

### Infra follow-up — TODO in `xomify-infrastructure`
Each backend PR's body documents the exact env-var / route / IAM
additions needed. Summary:

1. **New DynamoDB table** `xomify-user-likes`:
   - PK `email` (S), SK `addedAtTrackId` (S)
   - GSI `email-addedAt-index` — PK `email` (S), SK `addedAt` (S), PROJECTION_ALL
   - KMS-encrypted, PAY_PER_REQUEST (mirror `xomify-shares`)

2. **API Gateway routes** (POST/GET on the existing API):
   - `POST /likes/push` -> new lambda `xomify-likes-push`
   - `GET /likes/by-user` -> new lambda `xomify-likes-by-user`
   - `POST /users/likes-public` -> new lambda `xomify-users-set-likes-public`

3. **Lambda env vars** (every new lambda + the existing `friends_profile`):
   - `USERS_TABLE_NAME`
   - `USER_LIKES_TABLE_NAME`
   - `USER_LIKES_EMAIL_ADDED_INDEX` (default `email-addedAt-index`)
   - `FRIENDSHIPS_TABLE_NAME` (likes_by_user only)
   - `AWS_DEFAULT_REGION`

4. **IAM**:
   - `likes_push`: read+write on `users` and `user-likes` (incl. GSI)
   - `likes_by_user`: read on `users`, `friendships`, `user-likes` (incl. GSI)
   - `users_set_likes_public`: write on `users`
   - `friends_profile` (existing role): add read on `user-likes` if/when we
     read items from there (today only `users` table is touched for `get_likes_settings`)

### Next: iOS phases 5-7
Backend chain is unblocked. Per the plan, iOS work splits into three PRs:
- Phase 5: service methods + cold-open push hook.
- Phase 6: un-gate the Likes chip + read `likesCount` from `FriendProfile`.
- Phase 7: friend-scoped `LikesView` + settings toggle.

---

## 2026-04-27 — iOS Phases 5-7 (xomify-ios)

### PR #97 — Phase 5: service methods, push coordinator, cold-open hook ✅ MERGED
- **Branch**: `feature/social-library-likes-phase-5-service` off master
- **Version**: 1.12.0 → 1.13.0 (feat bump)
- **Files changed**:
  - `Xomify-iOS/Models/SocialModels.swift` — Added `LikesPushTrack`, `LikesPushRequest`, `LikesPushResponse`, `LikesByUserTrack`, `LikesByUserResponse`
  - `Xomify-iOS/Services/XomifyService.swift` — Added `pushUserLikes`, `getLikesByUser`, `setLikesPublic`
  - `Xomify-iOS/Services/XomifyServiceProtocol.swift` — Extended protocol with the three new methods
  - `Xomify-iOS/Services/LikesPushCoordinator.swift` — New actor; fires once per process lifetime; paginates `/me/tracks` up to 200 (4 × 50 pages), calls `pushUserLikes` fire-and-forget
  - `Xomify-iOS/Views/Shell/MainShell.swift` — Added `LikesPushCoordinator.shared.triggerIfNeeded()` in `.task` after `fetchAvatar()`
  - `Xomify-iOSTests/MockXomifyServiceProtocol.swift` — Added recording stubs for all three new methods
- **Decision**: Cold-open hook confirmed as `MainShell.task`; coordinator is an actor to guarantee the single-fire guard is thread-safe.

### PR #98 — Phase 6: likesCount on FriendProfile, un-gate Likes chip ✅ MERGED
- **Branch**: `feature/social-library-likes-phase-6-chip` off master (after phase 5 merged)
- **Version**: 1.13.0 → 1.14.0 (feat bump)
- **Files changed**:
  - `Xomify-iOS/Models/SocialModels.swift` — Added `likesCount: Int?` and `likesUpdatedAt: String?` to `FriendProfile`
  - `Xomify-iOS/ViewModels/UserProfileViewModel.swift` — Set `likesCount = profile.likesCount` in `loadOtherHeader`
  - `Xomify-iOS/Views/Profile/ProfileHeaderView.swift` — Removed `viewModel.context.isSelf` gate from Likes chip; chip routes to `.likes` as Phase 7 placeholder
  - `Xomify-iOSTests/MockXomifyServiceProtocol.swift` — Updated `FriendProfile` default with new optional fields

### PR #99 — Phase 7: friend-scoped LikesView, LikesSource, privacy toggle ✅ MERGED
- **Branch**: `feature/social-library-likes-phase-7-friend-likes` off master (after phase 6 merged)
- **Version**: 1.14.0 → 1.15.0 (feat bump)
- **Files changed**:
  - `Xomify-iOS/ViewModels/Library/LikesViewModel.swift` — Refactored: added `LikesSource` enum, `LikesTrackDisplayItem` unified display model; `items`/`spotifyTracks` replace `tracks`; two `fetchPage` branches; lazy caller-email resolution for backend path
  - `Xomify-iOS/Views/Library/LikesView.swift` — Accepts `targetEmail: String?`; renders from `vm.items`; `TrackActionsMenu` gated to Spotify path; friend-path empty state copy adjusted
  - `Xomify-iOS/Navigation/NavigationStore.swift` — Added `friendLikes(email: String)` case to `SidebarDestination`
  - `Xomify-iOS/Views/Shell/MainShell.swift` — Added `case .friendLikes(let email): LikesView(targetEmail: email)` route
  - `Xomify-iOS/Views/Profile/ProfileHeaderView.swift` — Chip tap on `.other` navigates to `.friendLikes(email: profileEmail)`; `.me` navigates to `.likes`
  - `Xomify-iOS/ViewModels/SettingsViewModel.swift` — Added `likesPublic: Bool` + `isUpdatingLikesPublic`; `syncLikesPublic()` calls `setLikesPublic` on toggle
  - `Xomify-iOS/Views/Shell/Destinations/SettingsView.swift` — Added "Privacy" section with "Show my likes to friends" toggle
  - `Xomify-iOSTests/ProfileLikesViewModelTests.swift` — Updated for new VM API (`vm.items`); added `test_backendSource_populatesItemsFromBackend`

### Infra dependency
New endpoints (`/likes/push`, `/likes/by-user`, `/users/likes-public`) return 404 until `xomify-infrastructure` provisions the API GW routes. Errors are caught in `LikesPushCoordinator` and `LikesViewModel` with warning prints — nothing surfaces to the UI.

### Build health
- All three phases: `xcodebuild -scheme Xomify-iOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build` → BUILD SUCCEEDED
- No new compiler warnings introduced
