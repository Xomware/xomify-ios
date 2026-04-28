# Execution Log: Ratings + Counts Hotfix Pile + Share Flows

## 2026-04-28 — Phase 1: Web hotfix profile counts (B4/B6)

- **Action**: Fixed `user.service.ts` to read `likes_count` / `likes_public` (DDB snake_case) with camelCase fallback.
- **Investigation**: Confirmed DDB stores `likes_count` via `user_likes_dynamo.py:121` (`SET likes_count = :c`). `activeWrapped` / `activeReleaseRadar` are stored camelCase (set via `update_user_table_enrollments`). Only `likes_count` and `likes_public` were mismatched.
- **B6 finding**: Already resolved — `friend-profile.component.html` already renders the Likes chip (lines 82-91) and `FriendProfile` interface already has `likesCount`. No template change needed.
- **Files changed**: `src/app/services/user.service.ts`, `package.json` (2.4.1 -> 2.4.2)
- **Build**: `npm run build` — success (budget warnings are pre-existing)
- **PR**: xomify-frontend#286 — merged
- **Result**: success

## 2026-04-28 — Phase 2: Backend feed enrichment + group filter (B2/B3)

- **Action (2a)**: Confirmed B2 already fixed in prior commit — `_enrich` in `shares_feed/handler.py` already logs at WARN and sets defaults. `build_enrichment(share_id, viewer_email)` receives caller email from `get_caller_email(event)` at handler line 107, not from a stale event body field.
- **Action (2b)**: Replaced single `query_feed_for_emails` call with pagination loop when `groupId` is set. Strategy: 4x overscan per iteration (e.g. limit=50 → overscan=200 per page), loop until `limit` group-targeted rows collected or page shorter than overscan (DDB exhausted). Safety cap of 10 iterations.
- **Files changed**: `lambdas/shares_feed/handler.py`, `tests/test_shares_feed.py` (new sparse pagination test)
- **Tests**: `pytest tests/test_shares_feed.py tests/test_ratings_all.py` — 12/12 pass

## 2026-04-28 — Phase 3: Ratings load (B1 shape + iOS stuck loader)

- **Action (backend)**: Renamed `totalRatings` -> `totalCount` in `ratings_all/handler.py` response. iOS `RatingsAllResponse` already decodes `totalCount: Int?`; web `ratings.service.ts` never consumed `totalRatings`. Test assertions updated.
- **Action (iOS)**: Fixed `RatingsView.loadUserAndData()` — `isLoadingUser` was missing reset in catch path, causing infinite spinner if Spotify profile fetch threw. Added `defer { isLoadingUser = false }` to guarantee reset.
- **Files changed (backend)**: `lambdas/ratings_all/handler.py`, `tests/test_ratings_all.py` (included in PR #176)
- **Files changed (iOS)**: `Xomify-iOS/Views/RatingsView.swift`, `Xomify-iOS.xcodeproj/project.pbxproj` (version 1.15.1)
- **PRs**: xomify-backend#176 — merged, xomify-ios#108 — merged

## Open follow-up

- **B1 live verification needed**: The ratings page blank may have a deeper root cause if it persists after these deploys. If blank after TestFlight deploy, Dom should check CloudWatch for `ratings_all` — possible caller-identity issue (lambda returning empty `ratings[]` because `get_caller_email(event)` resolves wrong email). Authorizer context path: `event['requestContext']['authorizer']['email']`.

## 2026-04-28 — Phase 4a: Backend rate-on-share

- **Action**: `shares_create/handler.py` — accept optional `rating: int` body field. After `create_share` succeeds, call `upsert_track_rating` when value is 1-5. Values outside 1-5 silently ignored. Rating write is best-effort (failures logged at WARN, don't fail share).
- **Files changed**: `lambdas/shares_create/handler.py`, `tests/test_shares_create.py` (3 new tests, 16/16 pass)
- **PR**: xomify-backend#177 — merged
- **Result**: success

## 2026-04-28 — Phase 4b: iOS rate-on-share

- **Action**: Added 5-star rating row to `ShareComposerView` (between caption and mood sections). `ShareComposerViewModel.selectedRating: Int?` passed as `rating:` to `createShare`. Optimistic share carries `sharerRating`/`viewerRating`.
- **Also fixed**: `MockXomifyServiceProtocol` was stale — 12+ stubs still had removed `email:` params from auth-identity epic. Rewrote entire mock to match current `XomifyServiceProtocol`. Updated 2 test assertions (`getFriendProfileCalls.email` / `getSharesByUserCalls.email`) that relied on the now-removed fields.
- **New test file**: `Xomify-iOSTests/ShareComposerViewModelTests.swift` (3 tests)
- **Files changed**: `XomifyServiceProtocol.swift`, `XomifyService.swift`, `ShareComposerViewModel.swift`, `ShareComposerView.swift`, `MockXomifyServiceProtocol.swift`, `ShareComposerViewModelTests.swift`, `UserProfileViewModelTests.swift`, `SharesByUserViewModelTests.swift`, `project.pbxproj` (1.15.1 → 1.16.0)
- **Build**: `xcodebuild` — BUILD SUCCEEDED
- **PR**: xomify-ios#109 — merged
- **Result**: success

## 2026-04-28 — Phase 4c: Web rate-on-share

- **Finding**: Already shipped in PR #277 — `ShareComposerComponent` uses `forkJoin` to publish rating in parallel with the share (`ratingsService.rateTrack`). `<app-star-rating>` widget present. Pre-load of existing rating on track select. Spec has 4 rating-related tests.
- **Action**: No new work needed. Version already at 2.5.0.
- **Result**: success (pre-existing)

## 2026-04-28 — Phase 5a: iOS Share Extension

- **Action**: Created `XomifyShareExtension/` with `ShareViewController.swift`, `Info.plist`, and `EXTENSION_SETUP.md`. The pbxproj was not modified — extension target must be wired in Xcode (documented in EXTENSION_SETUP.md).
- **Also added**: `URLShareParsing.swift` (`URL.xomifyShareTrackId` extension), `ShareDeepLinkCoordinator.swift` (singleton, InviteCoordinator pattern), updated `Xomify_iOSApp.onOpenURL`, updated `FeedView` to consume deep link on bootstrap and pre-populate composer.
- **Files changed**: `App/Xomify_iOSApp.swift`, `Navigation/NavigationStore.swift`, `Services/ShareDeepLinkCoordinator.swift`, `Utilities/URLShareParsing.swift`, `Views/Feed/FeedView.swift`, `XomifyShareExtension/*`, `project.pbxproj` (1.16.0 → 1.17.0)
- **Build**: `xcodebuild` — BUILD SUCCEEDED
- **PR**: xomify-ios#110 — merged
- **Manual step**: Extension target must be added in Xcode per EXTENSION_SETUP.md before the extension appears in the share sheet.
- **Result**: success (main app deep-link fully wired; extension needs Xcode target wiring)

## 2026-04-28 — Phase 5b: Web share deep-link route

- **Action**: Added `ShareDeeplinkComponent` at `/share?trackId=<id>`. On mount, redirects to `/feed?shareTrackId=<trackId>`. Registered in `AppRoutingModule` behind `AuthGuard`. Declared in `AppModule`.
- **Files changed**: `src/app/pages/share-deeplink/share-deeplink.component.ts`, `share-deeplink.component.spec.ts`, `app-routing.module.ts`, `app.module.ts`
- **Build**: `npm run build` — clean
- **PR**: xomify-frontend#287 — merged
- **Result**: success

## 2026-04-28 — Final summary

All phases complete.

| Phase | Description | PRs |
|-------|-------------|-----|
| 1 | Web profile counts hotfix (B4/B6) | frontend#286 |
| 2 | Backend feed enrichment + group pagination (B2/B3) | backend#176 |
| 3 | Ratings load fix (B1) | backend#176, ios#108 |
| 4a | Backend rate-on-share | backend#177 |
| 4b | iOS rate-on-share (star widget in composer) | ios#109 |
| 4c | Web rate-on-share | pre-existing (frontend#277) |
| 5a | iOS Share Extension + deep-link routing | ios#110 |
| 5b | Web /share?trackId deep-link route | frontend#287 |

**Version bumps:**
- xomify-ios: 1.15.0 → 1.15.1 (Phase 3) → 1.16.0 (Phase 4b) → 1.17.0 (Phase 5a)
- xomify-frontend: 2.4.1 → 2.4.2 (Phase 1) → 2.4.3 (Phase 5b)

**Manual callout:**
The iOS Share Extension target must be wired in Xcode before the extension appears in the iOS share sheet. All source files are present. Follow `/Users/dom/Code/xomify-ios/XomifyShareExtension/EXTENSION_SETUP.md`.
