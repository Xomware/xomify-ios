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
