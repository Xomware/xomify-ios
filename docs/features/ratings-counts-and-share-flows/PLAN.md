# Ratings + Counts Hotfix Pile + Share Flows

**Status:** In Progress
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

## Phase 4 — Rate-on-share

**Goal:** When the user shares a song, let them rate it inline (1-5 stars). The rating is saved alongside the share via the existing `/ratings/publish` endpoint, atomically with the share.

### Backend
- `lambdas/shares_publish/handler.py` — accept optional `rating: number (1-5)` in the body. If present, after writing the share row, also call `track_ratings_dynamo.upsert(email, trackId, rating)`. If the rating call fails, log a WARN but still return success for the share (rating is best-effort).

### iOS
- `Views/Shares/CreateShareView.swift` (or wherever the composer lives) — add a 5-star input (use existing star widget). Optional, defaults to "no rating".
- `ViewModels/CreateShareViewModel.swift` — include `rating: Int?` in the publish payload.
- Update `XomifyServiceProtocol` + mock.

### Web
- `xomify-frontend/src/app/components/share-composer/` (or equivalent) — same star input.
- `share-feed.service.ts` — pass `rating` through.

**Branch (each repo):** `feature/rate-on-share`
**Versions:** ios minor, web minor

---

## Phase 5 — iOS Share Extension (Spotify → Xomify)

**Goal:** When the user taps Share on a track inside the Spotify iOS app, "Xomify" appears in the share sheet. Tapping it opens our app pre-loaded into the Create Share flow with that track populated.

### iOS
1. Add a new target: `Xomify Share Extension` (Action Extension OR Share Extension — Share Extension is the conventional choice for "share to app" flows).
2. `NSExtensionAttributes`: register for `public.url` and Spotify's known UTI types. Filter by `NSExtensionActivationRule` predicate so it only appears for `open.spotify.com/track/*` and `spotify:track:*` URLs.
3. The extension UI:
   - Read the incoming URL from `NSExtensionContext.inputItems`.
   - Show a minimal preview (track ID + a "Continue in Xomify" button).
   - Tap → open a deep link `xomify://share?trackId=<id>` and dismiss the extension.
4. Main app: register the URL scheme, handle `xomify://share?trackId=<id>` via `onOpenURL`. Resolve track via Spotify, route to `CreateShareView` with the track preloaded.
5. Add Info.plist `LSApplicationQueriesSchemes` if needed for round-trip.

**Branch:** `feature/spotify-share-extension`
**Version:** ios minor

### Web
- Web equivalent: register a deep-link route `/share?trackId=<id>` that auto-opens the share composer with the track. (Doesn't need a "share extension" since iOS does that part.) Useful for desktop users sharing from Spotify Web.

---

## Conventions

- Branch names: hotfix paths use `hotfix/<slug>`; features use `feature/<slug>`. No issue numbers.
- Commits: terse, no Co-Authored-By, no `#N` issue tag.
- Web: bump via `npm run version:patch|minor`; build via `npm run build`.
- iOS: bump via `./scripts/bump-version.sh feat`; build via `xcodebuild -scheme Xomify-iOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`.
- Backend: lambdas are continuous deploy on merge to master. PR titles `feat:`, `fix:`, `hotfix:`.
- Auto-merge each PR with `gh pr merge <num> --auto --squash`.
- Stale type checker / SourceKit warnings: ignore — `npm run build` / `xcodebuild` are sources of truth.

## Suggested execution order
1. Phase 1 (web hotfix) — small, ships fast.
2. Phase 2a (B2 enrichment) and 2b (B3 group) — backend hotfix bundle.
3. Phase 3 (B1 ratings) — needs curl probe first; iterate.
4. Phase 4 (rate-on-share) — requires backend change merged first, then iOS + web in parallel.
5. Phase 5 (Share Extension) — iOS-only, can run parallel to Phase 4 web work.
