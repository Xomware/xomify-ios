# Ratings + Counts Hotfix Pile + Share Flows

**Status:** Done
**Last updated:** 2026-04-28
**Repos:** xomify-backend, xomify-frontend, xomify-ios
**Strategy:** Hotfixes first (parallel where independent), then two features (rate-on-share, iOS Share Extension).

---

## Diagnosed bugs

From triage report (debugger agent):

| # | Bug | Root cause | Repo |
|---|-----|-----------|------|
| B1 | Ratings page blank (iOS + web) | `ratings_all` returns `{totalRatings, ratings}`; clients tolerate that, so this is most likely a runtime auth or deploy issue. Curl shows `/ratings/all` returns 403 (authorizer wired). Need to confirm by hitting it with a real JWT. **Most likely: client decode silently failing on a shape mismatch, or the lambda is missing the JWT context propagation.** | backend / clients |
| B2 | Ratings disappeared from feed | `shares_feed/handler.py:77-100` — `_enrich` swallows errors silently. If enrichment lookup fails (e.g. ratings sub-call), `viewerRating` defaults to nil. Data is **NOT lost** in DDB. | backend |
| B3 | Web group feed empty | `shares_feed/handler.py:133-146` — DDB query uses `limit` BEFORE filtering by `groupId`; result can be empty even when matches exist. Need to filter at query time or paginate post-filter. | backend |
| B4 | Likes count 0 on web profile | `xomify-frontend/src/app/services/user.service.ts:75` — reads `xomifyData?.likesCount` but DDB returns `likes_count`. | web |
| B5 | Ratings count 0 on web profile | Symptom of B1 — fixes when B1 fixes. | n/a |
| B6 | Likes count missing on friend profile (web) | `xomify-frontend/src/app/pages/friend-profile/friend-profile.component.ts` — backend returns `likesCount` (PR #172), web has the model field, but the component never reads/renders it. | web |

Data verdict: **ratings are NOT gone from DDB** — purely a read-path issue.

---

## Phase 1 — Web hotfix: counts (B4 + B6) ✅

**Repo:** xomify-frontend
**Branch:** `hotfix/profile-counts`
**Version:** patch
**PR:** #286 — merged

- [x] `src/app/services/user.service.ts:75` — read `likes_count` (snake_case) with camelCase fallback; same for `likes_public`. DDB stores both snake_case (confirmed from `user_likes_dynamo.py`).
- [x] B6 was already resolved — `friend-profile.component.html` already renders the Likes chip at lines 82-91 and `FriendProfile` interface already has `likesCount`.
- [x] Build verify, PR, auto-merge.

---

## Phase 2 — Backend hotfix: feed enrichment (B2) + group filter (B3) ✅

**Repo:** xomify-backend
**Branch:** `hotfix/feed-enrichment-and-group-filter`
**Version:** none (lambdas are continuous deploy)
**PR:** #176 — merged

**2a. Feed enrichment (B2):**
- [x] B2 was already resolved in a prior commit — `_enrich` already logs at WARN and sets defaults on exception. `build_enrichment` receives `viewer_email` from `get_caller_email(event)` correctly.

**2b. Group feed (B3):**
- [x] `lambdas/shares_feed/handler.py` — implemented pagination loop when `groupId` is set: 4x overscan per iteration, loops until `limit` group-matching rows collected or DDB exhausted (max 10 iterations safety cap).
- [x] Test `test_shares_feed_group_pagination_returns_limit_when_sparse` added — proves 2 iterations collect 2 group matches across sparse pages. All 9 shares_feed tests pass.

---

## Phase 3 — Backend / clients: ratings load (B1) ✅

**Repo:** xomify-backend + xomify-ios
**PR (backend):** included in #176
**PR (iOS):** #108 — merged

- [x] `ratings_all/handler.py`: renamed `totalRatings` -> `totalCount` — matches every other list-shape endpoint. iOS `RatingsAllResponse` already decodes `totalCount`; web `ratings.service.ts` never read `totalRatings` (just `response?.ratings`).
- [x] `test_ratings_all.py` assertions updated to `totalCount`.
- [x] iOS `RatingsView.loadUserAndData()`: `isLoadingUser` was never reset in the catch path — page stuck on infinite spinner if Spotify profile fetch failed. Fixed with `defer { isLoadingUser = false }`.
- Note: curl probe with real JWT not possible from code inspection — Dom should verify live on TestFlight. If ratings still blank after deploy, root cause is likely caller-identity in the lambda (need CloudWatch logs).

---

## Phase 4 — Rate-on-share ✅

**Goal:** When the user shares a song, let them rate it inline (1-5 stars). The rating is saved alongside the share via the existing `/ratings/publish` endpoint, atomically with the share.

### Backend
- [x] `lambdas/shares_create/handler.py` — accept optional `rating: number (1-5)` in the body. If present, after writing the share row, also call `upsert_track_rating`. If the rating call fails, log a WARN but still return success for the share (rating is best-effort).
- [x] 3 new tests in `test_shares_create.py` (16/16 pass).
- **PR:** xomify-backend#177 — merged

### iOS
- [x] `ShareComposerView` — 5-star row between caption and mood. Optional, tap again or "Clear" to unset.
- [x] `ShareComposerViewModel` — `selectedRating: Int?` passed as `rating:` to `createShare`.
- [x] `XomifyServiceProtocol` + `XomifyService` + `MockXomifyServiceProtocol` — updated signature.
- [x] `ShareComposerViewModelTests` — 3 tests prove rating passthrough.
- [x] Version 1.15.1 → 1.16.0.
- **PR:** xomify-ios#109 — merged

### Web
- [x] Already shipped in PR #277 (`share-composer`: `forkJoin` with `ratingsService.rateTrack`, `<app-star-rating>`, pre-load of existing rating). No new work needed.

**Branch (each repo):** `feature/rate-on-share`

---

## Phase 5 — iOS Share Extension (Spotify → Xomify) ✅

**Goal:** When the user taps Share on a track inside the Spotify iOS app, "Xomify" appears in the share sheet. Tapping it opens our app pre-loaded into the Create Share flow with that track populated.

### iOS — `feature/spotify-share-extension` (PR #110 — merged)
- [x] `XomifyShareExtension/ShareViewController.swift` — reads URL from extension context, parses track id, shows "Continue in Xomify" button, opens `xomify://share?trackId=<id>`.
- [x] `XomifyShareExtension/Info.plist` — `NSExtensionPointIdentifier: com.apple.share-services`, `NSExtensionActivationRule` for `public.url`.
- [x] `XomifyShareExtension/EXTENSION_SETUP.md` — manual Xcode steps (Add Target → replace boilerplate → target membership for URLShareParsing.swift → signing).
- [x] `Xomify-iOS/Utilities/URLShareParsing.swift` — `URL.xomifyShareTrackId` handles all three URL formats.
- [x] `Xomify-iOS/Services/ShareDeepLinkCoordinator.swift` — singleton that stashes pending track ids (InviteCoordinator pattern).
- [x] `Xomify_iOSApp.onOpenURL` — now also routes to `ShareDeepLinkCoordinator`.
- [x] `FeedView.handlePendingShareDeepLink()` — resolves track, pre-populates composer, opens sheet.
- [x] Version 1.16.0 → 1.17.0.
- Note: extension target requires manual Xcode wiring (see EXTENSION_SETUP.md).

### Web — `feature/share-deeplink-route` (PR #287 — merged)
- [x] `ShareDeeplinkComponent` at `/share?trackId=<id>` — reads query param, navigates to `/feed?shareTrackId=<trackId>`.
- [x] 2 spec tests.
- [x] Version 2.4.2 → 2.4.3.

---

## Conventions

- Branch names: hotfix paths use `hotfix/<slug>`; features use `feature/<slug>`. No issue numbers.
- Commits: terse, no Co-Authored-By, no `#N` issue tag.
- Web: bump via `npm run version:patch|minor`; build via `npm run build`.
- iOS: bump via `./scripts/bump-version.sh feat`; build via `xcodebuild -scheme Xomify-iOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`.
- Backend: lambdas are continuous deploy on merge to master. PR titles `feat:`, `fix:`, `hotfix:`.
- Auto-merge each PR with `gh pr merge <num> --auto --squash`.
- Stale type checker / SourceKit warnings: ignore — `npm run build` / `xcodebuild` are sources of truth.
