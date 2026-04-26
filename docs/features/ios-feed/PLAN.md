# Plan: Xomify Social Feed — ios-feed

**Epic**: [xomify-social-feed](../xomify-social-feed/PLAN.md)
**Sub-feature ID**: 5 (`ios-feed`)
**Issue**: #31
**Status**: Ready
**Created**: 2026-04-22
**Last updated**: 2026-04-23
**Scope size**: L
**Repo(s) touched**: `xomify-ios`
**Depends on**: 2 (`ios-nav-shell`, merged), 3 (`backend-shares`, deployed)

---

## Summary

Ship the Feed tab end-to-end in `MainShell`: a fan-out-on-read feed of friend shares with horizontal filter chips (`All` / `Friends only` / per-group), inline Queue-to-Spotify and Rate actions on each card, a composer sheet behind a FAB, and a last-N-items offline cache so the feed renders instantly on cold launch. Empty state ships dual-CTA routing to Friends-invite and Groups-create. Reactions UI renders read-only behind a compile-time feature flag until `backend-interactions-and-notifications` (sibling sub-feature 4) ships the `shares_react` / `shares_interaction` endpoints.

Success = Dom and four dogfood friends open the Feed tab, see each other's shares in reverse-chrono, filter by group, one-tap queue a track on Spotify, one-tap rate (writing through to `ratings_track`), scroll to fetch the next page, pull to refresh, and drop a new share via the FAB composer.

## One-liner (from epic)

> Feed tab: feed list, share card, queue/rate actions, filter chips from groups, composer sheet + FAB, offline cache. Empty state has dual CTA ("Invite a friend" + "Post your first share").

## Approach

Follow the epic plan verbatim — MVVM with `@Observable` view models, views never touch `XomifyService` directly, `@MainActor` on all view models that mutate published state. New UI lives under `Xomify-iOS/Views/Feed/` and new view models under `Xomify-iOS/ViewModels/Feed/`. The existing shell (`MainShell.swift`) already reserves the Feed tab slot via `FeedPlaceholderView` — this sub-feature replaces that placeholder with the real `FeedView`.

Two shape mismatches surfaced during exploration and must be reconciled early (see Step 1):

1. **Model drift**: existing `Share` in `Models/SocialModels.swift` uses `{type, payload, interactionCounts, email}`. The epic + deployed `shares_feed` / `shares_create` use the track-denormalized shape `{shareId, sharedBy, sharedAt, trackId, trackUri, trackName, artistName, albumName, albumArtUrl, caption, moodTag, genreTags, queuedCount, ratedCount, viewerHasQueued, viewerRating, sharerRating}`. The current iOS `Share` model and `XomifyService.createShare` / `getFeed` signatures are **out of sync** with the deployed backend. Reconcile by rewriting the `Share` struct to match the backend atom and rewriting the three existing `XomifyService` share methods.
2. **Queue endpoint missing**: `SpotifyService` has no `addToQueue` method. Queue-to-Spotify is the flagship action on every feed card — add `queueTrack(uri:)` wrapping `POST /me/player/queue?uri={uri}`.

Reactions ship read-only behind a compile-time flag (`FeatureFlags.reactionsEnabled = false`) until `backend-interactions-and-notifications` merges. When flag is off, cards render the existing `queuedCount` / `ratedCount` chips but no reaction buttons. The `reactToShare` method stays in `XomifyService` (already present, wired to a TBD endpoint) but is not called from the feed UI in this sub-feature.

Offline cache uses a simple JSON blob in `FileManager.default.urls(for: .cachesDirectory)` — last 50 feed items keyed by filter (`all|friends|group:<id>`). SwiftData deferred to avoid adding a persistence dependency for what is fundamentally a disposable read cache. Cache is read-through on view appear, written after every successful `getFeed` call, and invalidated/overwritten on every successful refresh for the matching filter key.

## Critical decisions inherited from epic (do not re-litigate)

- **Share atom shape + composer constraints**: caption ≤140, `moodTag` single enum, `genreTags` ≤3. See epic Scope.
- **Groups as filter chips only** (not shared queues). See epic decision #7.
- **Feed reads from `shares_feed`** with optional `groupId`; response enriched with `queuedCount` / `ratedCount` / `viewerHasQueued` / `viewerRating` / `sharerRating`.
- **Ratings write-through**: rating from the feed goes through `shares_interaction` (once #4 ships). Interim: call existing `publishRating` directly until `shares_interaction` is live — same `track_ratings` table, same canonical behaviour.
- **MVVM constraint**: views never touch `XomifyService` directly.
- **Empty-state dual CTA**: "Invite a friend" (primary, deep-link to Friends screen invite flow) + "Create a group" (secondary, deep-link to Groups screen). Per task spec — note this **differs** from the epic plan, which says "Post your first share" secondary. Task spec wins; flag in Open Questions.

## Affected Files / Components

| File / Component | Change | Why |
|------------------|--------|-----|
| `Xomify-iOS/Models/SocialModels.swift` | modify | Rewrite `Share` to match deployed backend atom (`shareId`, `sharedBy`, `sharedAt`, track denorm fields, enrichment fields). Add `FeedResponse.nextBefore`. Add `CreateShareRequest`, `MoodTag` enum, `GroupFilter`, `CachedFeed` wrapper. |
| `Xomify-iOS/Services/XomifyService.swift` | modify | Rewrite `createShare` signature to match deployed `shares_create` (track-denormalized, no `type`/`payload`). Rewrite `getFeed` to accept `groupId`, `limit`, `before`. Add `deleteShare(email:shareId:sharedAt:)`. Keep `reactToShare` as-is (unused by this sub-feature). |
| `Xomify-iOS/Services/SpotifyService.swift` | modify | Add `queueTrack(uri:)` wrapping `POST /me/player/queue?uri=<uri>`. Handle 401 (token refresh already wired in `NetworkService`), 403 (Premium required), 404 (no active device). |
| `Xomify-iOS/Services/FeedCacheService.swift` (new) | create | JSON-on-disk cache for last 50 shares per filter key. Read-through on cold launch, write after every successful fetch. Actor-isolated. |
| `Xomify-iOS/Services/FeatureFlags.swift` (new) | create | Single struct with `static let reactionsEnabled: Bool = false`. Used by `ShareCardView` to gate reaction UI. |
| `Xomify-iOS/ViewModels/Feed/FeedViewModel.swift` (new) | create | `@Observable` `@MainActor` VM: loads feed, handles pull-to-refresh, infinite scroll (`nextBefore`), filter chip switching, cache bootstrap. |
| `Xomify-iOS/ViewModels/Feed/ShareCardViewModel.swift` (new) | create | Per-card VM: owns queue action (calls `SpotifyService.queueTrack`), rate action (calls `publishRating` now, `shares_interaction` once #4 lands), local optimistic state. |
| `Xomify-iOS/ViewModels/Feed/ShareComposerViewModel.swift` (new) | create | Composer VM: Spotify track search (reuses `SpotifyService.searchTracks`), caption validation (≤140), mood picker (`MoodTag` enum), genre tags (≤3), audience picker (All / Friends only / group), submit → `XomifyService.createShare`. |
| `Xomify-iOS/Views/Feed/FeedView.swift` (new) | create | Root view for Feed tab: header filter chips + `ScrollView { LazyVStack }` of share cards + FAB overlay + empty-state. `.refreshable` + sentinel-based infinite scroll. |
| `Xomify-iOS/Views/Feed/ShareCardView.swift` (new) | create | Single feed card: album art, track/artist, sharer avatar+email, caption, mood/genre pills, relative time, Queue button, Rate button (1–5 stars sheet), "queued by N" chip, sharer's rating inline. |
| `Xomify-iOS/Views/Feed/FilterChipsView.swift` (new) | create | Horizontal `ScrollView` of chips: `All` / `Friends only` / per-group. Fetches group list via `XomifyService.listGroups` on first appear; binds selection to `FeedViewModel`. |
| `Xomify-iOS/Views/Feed/ShareComposerView.swift` (new) | create | Sheet — Spotify search → pick track → caption + mood + genres + audience → Post. Presented from FAB. |
| `Xomify-iOS/Views/Feed/ComposerFAB.swift` (new) | create | Floating action button, bottom-trailing, 56×56 with xomifyGradient fill, triggers composer sheet. |
| `Xomify-iOS/Views/Feed/FeedEmptyStateView.swift` (new) | create | Dual-CTA empty state: "Invite a friend" primary → deep link to Friends screen invite flow; "Create a group" secondary → deep link to Groups screen. |
| `Xomify-iOS/Views/Shell/MainShell.swift` | modify | Replace `FeedPlaceholderView()` with `FeedView()` in the Feed tab slot. Wrap in `NavigationStack` to match other tabs. |
| `Xomify-iOS/Views/Shell/FeedPlaceholderView.swift` | delete | Replaced by real `FeedView`. |
| `Xomify-iOS/Navigation/NavigationStore.swift` | modify | Add `var composerSheetPresented: Bool = false` + `var pendingDeepLink: DrawerDestination?`. Empty-state taps set `pendingDeepLink` → `MainShell` observes and opens drawer to Friends / Groups. |
| `Xomify-iOS/XomifyTests/FeedViewModelTests.swift` (new) | create | XCTest: loading state, filter switch clears + reloads, pagination accumulates, pull-to-refresh replaces, cache bootstrap, error surfacing. |
| `Xomify-iOS/XomifyTests/ShareCardViewModelTests.swift` (new) | create | Queue success/403/404 paths; rate optimistic update; rollback on failure. |
| `Xomify-iOS/XomifyTests/ShareComposerViewModelTests.swift` (new) | create | Caption length guard, mood enum round-trip, ≤3 genre tags, audience mapping to groupId/null. |
| `Xomify-iOS/XomifyTests/FeedCacheServiceTests.swift` (new) | create | Write→read round-trip, filter-key isolation, corrupt-file recovery. |

## Implementation Steps

Ordered strictly by dependency. No step assumes the next has happened.

**Phase A — Foundations (no UI yet)**

- [ ] Step 1 — Reconcile `Share` model with deployed backend. Rewrite `Share` in `Models/SocialModels.swift` to match `shares_feed` response: `shareId`, `sharedBy` (renamed from `email`), `sharedAt` (renamed from `createdAt`), `trackId`, `trackUri`, `trackName`, `artistName`, `albumName`, `albumArtUrl`, optional `caption`, optional `moodTag: MoodTag?`, optional `genreTags: [String]?`, enrichment: `queuedCount: Int`, `ratedCount: Int`, `viewerHasQueued: Bool`, `viewerRating: Int?`, `sharerRating: Int?`. Add `MoodTag` enum (Codable raw-string). Rewrite `FeedResponse` to `{ shares: [Share], nextBefore: String? }`. Add `CreateShareRequest` struct. Delete `ShareType` + `ReactionAction` + polymorphic `payload` — not used by deployed backend. Keep `JSONValue` (still used by `FriendProfile`).
- [ ] Step 2 — Rewrite `XomifyService.createShare` signature to accept denormalized track fields + optional caption/mood/genres, matching deployed `shares_create`. Rewrite `getFeed` to accept `email`, optional `groupId`, optional `limit` (default 50), optional `before`. Add `deleteShare(email:shareId:sharedAt:)` for future share-owner deletion. Leave `reactToShare` in place but unused (flagged). Update any call sites — search for existing `createShare` / `getFeed` / `reactToShare` usages and confirm none ship outside this branch. If any exist (unlikely, feed UI does not yet exist), adapt them.
- [ ] Step 3 — Add `SpotifyService.queueTrack(uri:)` calling `POST /me/player/queue?uri={uri}` via `network.spotifyPost` (or a new `spotifyPostNoBody` helper if `spotifyPost` requires a body — read `NetworkService` first). Define `SpotifyServiceError.noActiveDevice` and `.premiumRequired` for 404 / 403 responses so the view layer can surface actionable messages. Unit-test at the service level with a mocked `NetworkService`.
- [ ] Step 4 — Create `FeatureFlags.swift` with `reactionsEnabled = false`. Single source of truth — sub-feature 4 flips this to `true` when shipping.
- [ ] Step 5 — Create `FeedCacheService.swift`. Actor-isolated. API: `func load(filterKey: String) async -> [Share]?`, `func save(_ shares: [Share], forKey filterKey: String) async`. Store as `feed-cache-<sha256(filterKey)>.json` in `.cachesDirectory`. Cap writes at 50 shares. Swallow decode errors (return nil on corrupt file; next successful fetch will overwrite).

**Phase B — ViewModels**

- [ ] Step 6 — Build `FeedViewModel`. `@Observable @MainActor`. Properties: `shares: [Share] = []`, `isLoading: Bool = false`, `isRefreshing: Bool = false`, `errorMessage: String? = nil`, `selectedFilter: FeedFilter = .all`, `groups: [XomifyGroup] = []`, `nextBefore: String? = nil`, `hasMorePages: Bool = true`. Methods: `bootstrap() async` (reads cache into `shares`, then calls `refresh()`), `refresh() async`, `loadMore() async` (guarded by `hasMorePages` + `isLoading`), `switchFilter(_ filter: FeedFilter) async` (clears shares, resets cursor, re-fetches + re-caches under new filter key), `loadGroupsForChips() async`. `FeedFilter` enum: `.all`, `.friends`, `.group(XomifyGroup)`. `filterKey` computed from filter for cache.
- [ ] Step 7 — Build `ShareCardViewModel`. `@Observable @MainActor`. Owns optimistic state: `isQueuing: Bool`, `queuedLocally: Bool`, `queueError: String?`, `myRating: Int?`, `isRating: Bool`. Methods: `queue() async` (calls `SpotifyService.queueTrack`, flips `queuedLocally` optimistically, rolls back on error, surfaces `queueError`), `rate(_ stars: Int) async` (calls `XomifyService.publishRating` with denormalized track fields from the share; TODO comment: swap to `shares_interaction` post-sub-feature-4).
- [ ] Step 8 — Build `ShareComposerViewModel`. `@Observable @MainActor`. Search state: `searchQuery: String`, `searchResults: [SpotifyTrack]`, `selectedTrack: SpotifyTrack?`. Form state: `caption: String` (validator: `.count <= 140`), `selectedMood: MoodTag?`, `selectedGenres: [String]` (cap 3), `selectedAudience: ComposerAudience` (`.all`, `.friendsOnly`, `.group(XomifyGroup)`), `isSubmitting: Bool`, `submitError: String?`. Methods: `search() async` (debounced 300ms, reuses `SpotifyService.searchTracks`), `toggleGenre(_ tag: String)`, `submit() async -> Bool`. Note: backend `shares_create` does not currently accept audience scoping — audience picker selection does not change the request payload in v1 (audience is enforced at read time via the friend-graph + group filter). Flag in Open Questions.

**Phase C — Views**

- [ ] Step 9 — Build `FilterChipsView`. Horizontal `ScrollView(.horizontal, showsIndicators: false)` of chips bound to `FeedViewModel.selectedFilter`. Chip styling: 32pt tall pill, xomifyCard background, xomifyGreen when selected. Loads groups on first appear.
- [ ] Step 10 — Build `ShareCardView`. Layout: horizontal album art (64×64, rounded), VStack `trackName` / `artistName` / `albumName`, sharer row (avatar + email + relative time), optional caption, optional mood/genre pills. Footer row: Queue button (`queue` SF symbol), Rate button (opens 1–5-star picker sheet), "queued by N friends" chip (hidden if 0), sharer's rating inline (small star + number). When `FeatureFlags.reactionsEnabled == false`, no reaction UI. 44pt minimum tap targets.
- [ ] Step 11 — Build `ShareComposerView`. Sheet presented via `.sheet(isPresented:)` driven by `NavigationStore.composerSheetPresented`. Layout: search field → result list → once selected, collapsible preview + caption TextEditor + mood segmented picker + genre chip multi-select + audience picker + Post button. Disables Post until a track is selected. Dismiss on success.
- [ ] Step 12 — Build `ComposerFAB`. `Circle().fill(xomifyGradient).frame(width: 56, height: 56)` with plus SF symbol, `.shadow`. Positioned bottom-trailing via `.overlay(alignment: .bottomTrailing)` on `FeedView`. Tap toggles `NavigationStore.composerSheetPresented`.
- [ ] Step 13 — Build `FeedEmptyStateView`. Shown when `shares.isEmpty && !isLoading`. Primary CTA: "Invite a friend" → sets `NavigationStore.pendingDeepLink = .friends` + `openDrawer()`. Secondary CTA: "Create a group" → sets `pendingDeepLink = .groups` + `openDrawer()`. Both CTAs use xomifyGradient fills with clear primary/secondary emphasis (filled vs outlined).
- [ ] Step 14 — Build `FeedView`. Root of Feed tab. `ScrollView` wrapping `LazyVStack(spacing: 12)` of `ShareCardView`s. Header: `FilterChipsView`. Trailing sentinel view triggers `viewModel.loadMore()` via `.onAppear`. `.refreshable { await viewModel.refresh() }`. `.overlay(alignment: .bottomTrailing) { ComposerFAB() }`. Empty state when `shares.isEmpty && !isLoading`. Error banner when `errorMessage != nil`. `.task { await viewModel.bootstrap(); await viewModel.loadGroupsForChips() }`.

**Phase D — Wire-up + deep links**

- [ ] Step 15 — Modify `NavigationStore`: add `var composerSheetPresented: Bool = false`, `var pendingDeepLink: DrawerDestination? = nil`. Add method `consumePendingDeepLink()` that reads + clears `pendingDeepLink` and pushes onto `drawerPath`.
- [ ] Step 16 — Modify `MainShell.swift`: replace `FeedPlaceholderView()` with `NavigationStack { FeedView() }`. Add `.onChange(of: navStore.pendingDeepLink)` to open drawer + consume on next runloop. Delete `FeedPlaceholderView.swift`.
- [ ] Step 17 — Wire composer FAB: `FeedView` observes `navStore.composerSheetPresented` and presents `ShareComposerView` in `.sheet`. On successful submit, close sheet + call `viewModel.refresh()`.

**Phase E — Tests**

- [ ] Step 18 — Write `FeedViewModelTests`: mock `XomifyService` via protocol (extract `XomifyServiceProtocol` if not already present — check before doing so) or via dependency-injected closure. Cover: initial load success, empty response, error state, filter switch resets + refetches, `loadMore` appends + updates `nextBefore`, `loadMore` no-op when `hasMorePages == false`, cache bootstrap renders before network resolves.
- [ ] Step 19 — Write `ShareCardViewModelTests`: queue success flips `queuedLocally`; queue failure rolls back + surfaces error; rate success updates `myRating`; rate failure rolls back.
- [ ] Step 20 — Write `ShareComposerViewModelTests`: caption >140 blocks submit; >3 genre tags blocks submit; mood enum round-trips through Codable; audience selection maps correctly (even though v1 payload ignores audience — test captures current behaviour + the TODO).
- [ ] Step 21 — Write `FeedCacheServiceTests`: round-trip, filter-key isolation (cached `.all` doesn't bleed into `.group(x)`), corrupt-file recovery (write bad JSON → read returns nil).
- [ ] Step 22 — Manual dogfood smoke: build for simulator with `xcodebuild -scheme Xomify-iOS -sdk iphonesimulator build`. Sign in, land on Feed tab, create a share, queue, rate, filter by a group, pull-to-refresh, scroll to page 2, cold-launch and verify cache render.

## Out of Scope

- APNs permissions / push-open deep links — sub-feature 9 (`ios-notifications`).
- Groups management UI (create / add-member / remove) — sub-feature 6 (`ios-groups-management`). This sub-feature only consumes `listGroups` for filter chips.
- Friends invite share-sheet + deep-link landing page — sub-feature 7 (`ios-friends-management`). Empty-state CTA in this sub-feature only sets the navigation intent.
- `shares_interaction` and `shares_react` endpoints — sub-feature 4 (`backend-interactions-and-notifications`). Reactions UI gated behind `FeatureFlags.reactionsEnabled`. Rating action uses existing `publishRating` until #4 ships.
- `shares_delete` — handler signature is added to `XomifyService` but no UI exposure in v1 (share author deletion can ship in a follow-up once a profile-level "my shares" list exists — drawer-residents sub-feature).
- Angular parity — sub-feature 10.
- SwiftData migration for the feed cache — disposable JSON is sufficient for v1.
- Search icon / full-text search — dropped from v1 per epic Locked Answers.
- Audience scoping at write time (backend doesn't accept it in v1).

## Risks / Tradeoffs

- **Model drift**: deployed backend and current iOS `Share` struct disagree on field names and shape. Mitigation: Step 1 rewrites the model before any UI exists, so the blast radius is the three `XomifyService` share methods (verified). If an uncommitted branch is building against the old shape, this PR will break it — flag during code review.
- **Spotify queue endpoint needs Premium + active device**: `POST /me/player/queue` returns 403 for free accounts and 404 when no device is active. Mitigation: surface actionable error messages on the card ("Open Spotify and play something first" for 404; "Spotify Premium required" for 403). Accepted degradation.
- **Offline cache staleness**: cached `queuedCount` / `viewerHasQueued` lie if the user queued from another device. Mitigation: cache is only used for first paint; every `viewDidAppear` triggers a background refresh that overwrites the cache. Accepted tradeoff.
- **Pagination cursor edge cases**: `nextBefore` is the `sharedAt` of the last returned share. If two shares share a timestamp to the second, the second page may drop the duplicate. Backend uses `sharedAt#shareId` SK, so lexicographic ordering is stable — but the handler returns only `sharedAt` as cursor per the code. Flag: confirm handler returns a cursor stable across duplicates. If not, propose tightening to `sharedAt#shareId` in `backend-shares` follow-up.
- **Reactions UI gated but `reactToShare` still in `XomifyService`**: dead code risk. Mitigation: keep it (the method shape is cheap and sub-feature 4 needs it in a week). Add a `// TODO(sub-feature-4)` comment.
- **Composer audience picker is cosmetic in v1**: backend doesn't scope by audience at write time. Showing the picker sets UX expectations we can't fulfil. Mitigation: either hide the picker in v1 OR show with an info tooltip ("Audience affects who sees this in their feed — everyone you selected has access today"). See Open Questions.
- **Empty-state CTA divergence from epic**: epic says "Post your first share" as secondary; task spec says "Create a group". Following task spec. Low risk — both are valid onboarding paths.
- **Protocol extraction for testability**: `XomifyService` is a concrete `actor` singleton. Mocking in XCTest requires extracting a `XomifyServiceProtocol`. This is extra surface area but the test strategy needs it — flag up front rather than discover mid-test.
- **No ripgrep during planning**: local `rg` binary was unavailable during exploration. Plan is grounded in direct file reads of `XomifyService.swift`, `SocialModels.swift`, `MainShell.swift`, `NavigationStore.swift`, and both backend handlers. A fresh `grep` pass during execution may surface additional call sites for `createShare` / `getFeed` / `reactToShare` — see Step 2.

## Open Questions

- [ ] **Empty-state secondary CTA**: task spec says "Create a group"; epic plan says "Post your first share (secondary → opens composer)". Which ships? Default to task spec ("Create a group") and file a follow-up if epic needs updating.
- [ ] **Composer audience picker in v1**: ship the picker (cosmetic) or hide it? Default: ship with an info tooltip, so friends don't need to re-learn the UI when real scoping lands.
- [ ] **Cursor stability**: confirm `shares_feed` `nextBefore` is unique per share, not just per second. If not, add `#shareId` tiebreaker in `backend-shares` follow-up — not blocking this sub-feature.
- [ ] **Protocol extraction for `XomifyService`**: should this sub-feature introduce `XomifyServiceProtocol` (the clean path) or use a closure-based seam (lighter, uglier)? Default: extract the protocol — it unblocks all future iOS VM tests.
- [ ] **Reactions model sync**: current `ReactionAction` enum is slated for deletion in Step 1. If `backend-interactions-and-notifications` already has a shape locked in, re-add it with the final shape in sub-feature 4 rather than now.
- [ ] **Spotify queue behaviour offline-first**: if `queueTrack` fails with 404 (no active device), should we fall back to opening the track in Spotify via `UIApplication.open(URL(string: trackUri))`? Nice-to-have; deferrable.

## Skills / Agents to Use

- **ios-engineer agent**: primary implementation. Must respect MVVM — views never touch `XomifyService` directly.
- **test-writer agent**: XCTest coverage (VM + service-layer mocks). Pair with ios-engineer for Steps 18–21.
- **code-reviewer agent**: run on PR before merge. Focus review on Step 1 model rewrite + Step 2 service signature changes for call-site breakage.
- **docs-writer agent**: not needed — this plan doc stands alone.
