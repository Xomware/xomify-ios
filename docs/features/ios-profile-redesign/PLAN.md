# Plan: iOS Profile Redesign — Tabbed Profile

**Status**: Done
**Created**: 2026-04-23
**Last updated**: 2026-04-24 (shipped via PRs #38 + #39; Phase 8 collapsing header deferred)

## Summary
Turn `ProfileView` from a settings page into a social profile with an Instagram-style header plus a segmented `Shares / Ratings / Taste` tab strip. The same view renders both the logged-in user (`.me`) and any other user (`.other(email)`), replacing the legacy `FriendProfileView`. Success = a user can open their own profile OR tap a friend/feed-avatar and see that person's shares, ratings, and taste with reused view models and a single `UserProfileViewModel` fan-out.

See brainstorm: `/Users/dom/Code/xomify-ios/docs/features/ios-profile-redesign/BRAINSTORM.md` (Option 1 chosen).

## Approach
Follow Option 1 from the brainstorm verbatim:

- One `ProfileView` (renamed conceptually to a social profile; keep the file name `ProfileView.swift` to minimize callsite churn) takes a `ProfileContext` enum: `.me` or `.other(email: String)`.
- A new thin `UserProfileViewModel` owns the `ProfileContext`, the selected tab, and lazily instantiates the three child view models (`SharesByUserViewModel`, `RatingsViewModel`, `TopItemsViewModel`). It does NOT duplicate their state.
- Header (avatar, display name, stat row, action button) + collapsing-on-scroll behavior.
- Segmented `Picker` switches between tabs. Each tab manages its own paging / refresh state.
- The `ios-nav-ia-cleanup` execution is assumed to have already extracted settings into `SettingsView` / `SettingsViewModel` and stripped `ProfileViewModel` down to identity + Quick Stats. This plan builds on top of that — no settings logic lands here.
- Taste tab uses a user-driven term-range `Picker` (`shortTerm` / `mediumTerm` / `longTerm`). No auto-rotation (brainstorm section "Tradeoffs" and "Next" explicitly call accessibility and reject auto-rotation).
- Deprecate `FriendProfileView` / `FriendProfileViewModel` and redirect the two known callsites (friend list row tap, feed-card avatar tap).

## Affected Files / Components

| File / Component | Change | Why |
|-----------------|--------|-----|
| `Xomify/Xomify/Models/ProfileContext.swift` *(new)* | Add `enum ProfileContext { case me; case other(email: String) }` with `email`, `isSelf`, and `displayEmail` helpers | Single source of truth for self-vs-other branching |
| `Xomify/Xomify/Services/XomifyService.swift` | Add `func getSharesByUser(email: String, before: Date?, limit: Int) async throws -> FeedResponse` (or `SharesByUserResponse` if shape diverges) hitting `GET /shares/user?email=...&before=...&limit=...` | Brainstorm gap #1 — only net-new service call |
| `Xomify/Xomify/Models/SharesByUserResponse.swift` *(new, only if shape differs from `FeedResponse`)* | Typed decoder for `/shares/user` response | Decode the backend payload cleanly |
| `Xomify/Xomify/ViewModels/SharesByUserViewModel.swift` *(new)* | Paginated list VM keyed off `sharedAt`; mirrors `FeedViewModel` pagination pattern; exposes `[Share]`, `isLoading`, `hasMore`, `loadMore()`, `refresh()` | Shares tab data source for both self and other |
| `Xomify/Xomify/ViewModels/UserProfileViewModel.swift` *(new)* | Owns `context: ProfileContext`, `selectedTab: ProfileTab`, lazy child VMs. Loads header (`SpotifyService.getCurrentUser` for `.me`; `friendsService.getProfile(email:)` for `.other`). Exposes `shareCount`, `ratingCount`, `friendCount`, action-button state | Fan-out controller for the new profile surface |
| `Xomify/Xomify/Views/Profile/ProfileView.swift` | Rewrite to take a `ProfileContext` initializer, render header + segmented tabs + tab content. Keep file name to avoid churn in the sidebar router | Main UI surface for both self and other users |
| `Xomify/Xomify/Views/Profile/ProfileHeaderView.swift` *(new)* | Avatar, display name, stats row (Shares / Ratings / Friends), action button. Self → gear + "Edit" (no-op v1); other → Add/Remove Friend from `Friend` model state | Reusable header, decoupled from tab state |
| `Xomify/Xomify/Views/Profile/Tabs/ProfileSharesTab.swift` *(new)* | List of `ShareCard`s driven by `SharesByUserViewModel`; reuses `ShareCardViewModel` per row for queue/rate parity with Feed | Shares tab UI |
| `Xomify/Xomify/Views/Profile/Tabs/ProfileRatingsTab.swift` *(new)* | Wraps existing `RatingsViewModel` parameterized by `context.email`; hides delete on `.other` | Ratings tab UI |
| `Xomify/Xomify/Views/Profile/Tabs/ProfileTasteTab.swift` *(new)* | Vertical stack of Top Tracks / Top Artists / Top Genres with a single term-range `Picker` at top. Self uses `TopItemsViewModel` (rich tiles). Other uses `FriendProfile.topSongs/topArtists/topGenres` degraded rendering | Taste tab UI with graceful fallback |
| `Xomify/Xomify/Views/Profile/ProfileTabPicker.swift` *(new)* | Segmented control with `.shares / .ratings / .taste` | Keep tab chrome isolated from view models |
| `Xomify/Xomify/Views/Profile/EmptyStates/*.swift` *(new)* | Per-tab empty-state views (no shares / no ratings / no taste data) with context-aware copy | Polish, also covers first-run + other-user-with-nothing |
| `Xomify/Xomify/Views/Friends/FriendProfileView.swift` | **Delete** | Subsumed by `ProfileView(context: .other(email))` |
| `Xomify/Xomify/ViewModels/FriendProfileViewModel.swift` | **Delete** | Same |
| `Xomify/Xomify/Views/Friends/FriendsListView.swift` *(or wherever friend-row tap is wired)* | Replace `FriendProfileView(email:)` nav destination with `ProfileView(context: .other(email: ...))` | Callsite migration |
| `Xomify/Xomify/Views/Feed/ShareCard.swift` *(or wherever the avatar tap is wired in `ShareCardViewModel`)* | Replace `FriendProfileView` navigation with `ProfileView(context: .other(email: share.userEmail))` | Callsite migration |
| `Xomify/Xomify/App/Router/*` (wherever `ProfileView()` is constructed by the sidebar) | Update to `ProfileView(context: .me)` | Keep sidebar entry working post-signature change |
| `Xomify/XomFitTests/...` → `Xomify/XomifyTests/UserProfileViewModelTests.swift` *(new)* | Unit tests for `UserProfileViewModel` branching (self vs other), `SharesByUserViewModel` pagination happy path + empty + error | Coverage for the fan-out logic and new pagination |

## Implementation Steps

### Phase 0 — Prerequisites & confirmations
- [ ] Confirm `ios-nav-ia-cleanup` has landed on the working branch: `ProfileView` is identity + Quick Stats only, `loadXomifyStatus` removed, `SettingsView` owns enrollment toggles / account / logout. If not merged, rebase on top of it before starting Phase 1.
- [x] Backend contract resolved 2026-04-23 — `xomify-backend/docs/ios-profile-redesign-contract.md`. `/shares/user` and `/ratings/all` are live; `/friends/profile` needs `shareCount` added (out-of-band backend ticket, ~30 min).
- [ ] Decide default tab: plan assumes **Shares** for both self and other (brainstorm Open Questions). Lock this decision before Phase 4.

### Phase 1 — Data layer: `ProfileContext` + `getSharesByUser`
- [ ] Add `Xomify/Xomify/Models/ProfileContext.swift` with the enum and helpers (`email`, `isSelf`).
- [ ] Add `XomifyService.getSharesByUser(email:targetEmail:before:limit:)` — URL builder must send BOTH `email` (caller) and `targetEmail` (author). Cursor field in response is `nextBefore`, not `nextCursor`. Add a `SharesByUserResponse` struct with `shares: [Share]` and `nextBefore: String?`.
- [ ] Add `SharesByUserViewModel` following `FeedViewModel`'s pagination shape (initial load, `loadMore`, `refresh`, empty / error surfaces).
- [ ] Unit test: happy path page 1 + page 2, empty response, 4xx error, 5xx error.

### Phase 2 — Header + shell
- [ ] Add `UserProfileViewModel` with `context`, `selectedTab`, header fields (`displayName`, `avatarURL`, `shareCount`, `ratingCount`, `friendCount`), and lazy child VM accessors.
- [ ] Header loading branches:
  - `.me` → reuse existing `SpotifyService.getCurrentUser` path already in the slimmed `ProfileViewModel`; migrate that logic into `UserProfileViewModel` and delete the now-empty `ProfileViewModel` (or keep as typealias if callsites are broad).
  - `.other(email)` → call the existing friends-profile endpoint used by `FriendProfileViewModel` today to populate display name / avatar / friend count.
- [ ] Build `ProfileHeaderView` with avatar, display name, stats row, action button. Self action button = `Edit` (placeholder no-op) + gear icon opening the Settings sheet from `ios-nav-ia-cleanup`. Other action button = Add / Remove / Pending wired to existing `Friend` state mutation.
- [ ] Build `ProfileTabPicker` segmented control.
- [ ] Rewrite `ProfileView.swift` to accept `ProfileContext` and render header + picker + tab content area (placeholder). Default `selectedTab = .shares`.

### Phase 3 — Shares tab
- [ ] Build `ProfileSharesTab` consuming `SharesByUserViewModel(email: context.email)`.
- [ ] Render each share with the existing `ShareCard` + `ShareCardViewModel` so queue/rate behave identically to Feed.
- [ ] Empty state: `.me` → "Drop your first track" with composer deep link. `.other` → "{name} hasn't shared anything yet."
- [ ] Pull-to-refresh + infinite scroll.

### Phase 4 — Ratings tab
- [ ] Build `ProfileRatingsTab` that instantiates `RatingsViewModel(email: context.email)` (parameterize the VM if it isn't already — brainstorm indicates `/ratings/all?email=` accepts any email, but confirm the VM has an email init).
- [ ] Reuse existing grouped-by-star rendering (`RatingsViewModel.grouped`).
- [ ] Hide delete action on `.other`. Keep delete on `.me`.
- [ ] Empty state per context.

### Phase 5 — Taste tab
- [ ] Build `ProfileTasteTab` with a single term-range `Picker` (`shortTerm` / `mediumTerm` / `longTerm`).
- [ ] `.me` branch: drive Top Tracks / Top Artists / Top Genres sections from `TopItemsViewModel`, re-fetching on term change. Keep rich album art tiles.
- [ ] `.other` branch: read from the `FriendProfile` payload already loaded by `UserProfileViewModel`. The payload always returns all three term buckets (`short_term` / `medium_term` / `long_term`) populated with raw Spotify track/artist objects (album art included). Graceful degradation only needed for:
  - Empty-array buckets (target user without enough listening in that window) — hide the term in the picker or show a "Not enough data" placeholder for that term only.
  - If ALL three buckets are empty arrays (rare — target has no Spotify top-items at all), hide the Taste tab content with a single "No taste data available" state.
  - Missing section (e.g. `topGenres` key absent) — hide the section. Should not happen but defensive.
- [ ] No auto-rotation anywhere. Respect Reduce Motion.

### Phase 6 — Deprecate `FriendProfileView`
- [ ] Migrate the friend-list tap callsite to push `ProfileView(context: .other(email: friend.email))`.
- [ ] Migrate the feed-card avatar tap callsite in `ShareCard` / `ShareCardViewModel` to the same.
- [ ] Delete `FriendProfileView.swift` and `FriendProfileViewModel.swift`.
- [ ] Remove any now-unused helpers (e.g. friend-profile-only preview fixtures).
- [ ] Grep for remaining `FriendProfileView` references; convert or delete.

### Phase 7 — Polish & tests
- [ ] Collapsing header on scroll (iOS 17 `scrollTargetBehavior`) — acceptable to defer if it blocks the ship.
- [ ] Loading skeletons for header (avatar + stats) and each tab.
- [ ] VoiceOver pass on header (stats as individual buttons) and Taste picker.
- [ ] Unit tests: `UserProfileViewModel` branching (`.me` vs `.other`), `SharesByUserViewModel` pagination, `ProfileTasteTab` fallback when `FriendProfile` has only one term bucket.
- [ ] Manual QA matrix below.
- [ ] Screenshot update in `README` / marketing assets if applicable (skip if not in repo).

### Phase 8 — Ship
- [ ] Verify `xcodebuild -scheme Xomify -sdk iphonesimulator build` is clean.
- [ ] Update `.claude/memory/session-log.md` with any gotchas discovered during execution.
- [ ] PR description: link brainstorm + this plan, call out backend dependencies, include before/after screenshots of self + other profile.

## QA Matrix (manual)
- [ ] Self profile: header loads, all three tabs render, term-range switcher works on Taste.
- [ ] Self profile with zero shares: Shares tab empty state shows composer CTA.
- [ ] Other user with full data: header, Shares, Ratings, Taste all populate.
- [ ] Other user with zero shares: Shares tab empty state shows "{name} hasn't shared anything yet."
- [ ] Other user with only `mediumTerm` taste data: Taste tab hides picker, shows footnote.
- [ ] Other user where backend has no `shareCount`: header shows 3 stats instead of 4 (graceful fallback).
- [ ] Feed avatar tap → lands on `ProfileView(context: .other(email))`.
- [ ] Friend list tap → same.
- [ ] `FriendProfileView` no longer compiled into the app (confirmed via grep).

## Definition of Done
- `ProfileContext` + `UserProfileViewModel` + `SharesByUserViewModel` + `XomifyService.getSharesByUser` exist and are unit tested.
- `ProfileView(context:)` renders header + three tabs for both `.me` and `.other(email)`; default tab is `.shares`.
- Shares tab reuses `ShareCard` / `ShareCardViewModel` and paginates correctly.
- Ratings tab reuses `RatingsViewModel` with the `email` parameter and hides delete for other users.
- Taste tab has a user-driven term-range picker; degrades gracefully for `.other` per brainstorm gap #2.
- `FriendProfileView` and `FriendProfileViewModel` are deleted; all callsites route through `ProfileView(context: .other(email:))`.
- `xcodebuild -scheme Xomify -sdk iphonesimulator build` is clean.
- QA matrix above passes on simulator.
- No regressions in Feed (`ShareCardViewModel` behavior unchanged) or Settings (owned by `ios-nav-ia-cleanup`).

## Out of Scope
- Settings migration (owned by `ios-nav-ia-cleanup` — assumed merged).
- Profile URL deep-linking / share-profile affordance.
- "Last active" indicator in the header (requires backend `lastSeenAt`).
- Auto-rotating Taste carousel (explicitly rejected in brainstorm).
- Activity stream / interleaved shares+ratings (Option 3 — not chosen).
- Bento hero layout (Option 2 — not chosen).
- Bio / vibe-tag editing on self profile (no backend storage today).
- `Wrapped` / `Release Radar` entry points — relocated by `ios-nav-ia-cleanup`; Profile no longer owns them.
- Album-art-rich taste for other users (depends on backend payload upgrade — tracked in Backend Dependencies).
- Follow-up "Groups" tab scaffolding.

## Risks / Tradeoffs
- **Backend parity on other-user Ratings**: if `/ratings/all?email=<other>` is auth-gated to the caller, the Ratings tab for `.other` is blocked. Mitigation: Phase 0 confirmation step; if gated, file a backend ticket and hide the Ratings tab for `.other` in v1 (show a "Private" placeholder).
- **Other-user Taste fidelity**: `FriendProfile` today is loose JSON with no album art and potentially single-term data. We degrade gracefully, but the tab will visibly look thinner than self-view Taste. Accepted tradeoff for v1; backend upgrade listed below.
- **`shareCount` absent from `FriendProfile`**: header shows 3 stats instead of 4 for other users until backend adds `shareCount`. Accepted tradeoff.
- **Pagination state across tab switches**: naive implementation could re-fetch on every tab toggle. Mitigation: instantiate child VMs lazily once per `UserProfileViewModel` lifecycle and keep them alive across tab switches.
- **Collapsing header on scroll** is polish work that can slip the ship if fought. Mitigation: Phase 7 step explicitly allows deferring.
- **`FriendProfileView` deletion risk**: miss a callsite and navigation breaks. Mitigation: grep step in Phase 6, plus build verification.
- **Sidebar router coupling**: changing `ProfileView()` → `ProfileView(context: .me)` touches the sidebar destination wiring from `ios-nav-ia-cleanup`. Coordinate if that PR isn't merged.
- **`FriendProfile` payload divergence**: if friends-profile endpoint returns subtly different field names than expected, `.other` header stats could show zero. Mitigation: write `UserProfileViewModel` header tests against a fixture JSON copied from a real response.

## Backend Dependencies

Backend contract resolved 2026-04-23 — see `xomify-backend/docs/ios-profile-redesign-contract.md` for full detail. Summary:

1. **`GET /shares/user`** — **already live**, no backend change needed. Two iOS plan corrections:
   - Query params are `email` (caller) AND `targetEmail` (author) — both required. Swift call site must send both.
   - Cursor field is `nextBefore`, not `nextCursor`. Update `SharesByUserResponse` accordingly.
   - Auth: fully open to any authenticated caller in v1 ("no friendship gate"). Shares tab on `.other` renders unconditionally.

2. **`GET /ratings/all?email=<any>`** — **already works**, not caller-gated. iOS Phase 4 ships on `.other` without backend change.

3. **`GET /friends/profile`** — two items, one blocker one non-blocker:
   - **Blocker (Phase 2 header parity)**: add `shareCount: Int` to the response. Cheapest impl is a `Select=COUNT` query on the existing `email-createdAt-index` GSI. ~30 min of work on the backend side.
   - **Already present (iOS plan was wrong)**: all three term buckets come back for tracks/artists/genres (`short_term` / `medium_term` / `long_term`), and the payload is raw Spotify objects including `album.images[].url`. The Phase 5 fallback should trigger on **empty arrays per bucket**, not on missing buckets; no text-only degradation needed.
   - **Non-blocking perf caveat**: each profile load spins up a live Spotify session for the target (~6 API calls). Fine for v1; cache with 24h TTL when `.other` becomes a high-traffic tab.

4. **`lastSeenAt`** — deferred. Not v1.

## Open Questions
- [ ] Default tab for self and other — plan assumes `Shares` for both; confirm before Phase 4.
- [ ] Should the self-profile action button ("Edit Profile") open the Settings sheet (gear is already in the header) or a dedicated future Edit sheet? v1 leans no-op placeholder; confirm.
- [ ] On `.other` profile when the viewer is NOT a friend, should the Shares tab be hidden / gated? Depends on backend answer #1 auth rule.
- [ ] If `/ratings/all` is gated, do we hide the Ratings tab for `.other` or show "Private" placeholder? Lean placeholder; confirm.

## Skills / Agents to Use
- **ios-swift-engineer agent**: primary executor for Swift / SwiftUI file creation, view model wiring, and callsite migration.
- **ios-ui-polish skill** (if defined): Phase 7 header-collapse + loading skeletons.
- **test-writer agent**: Phase 1 and Phase 7 unit tests (`UserProfileViewModel`, `SharesByUserViewModel`, taste-fallback logic).
- **backend-liaison / manual**: Phase 0 confirmations against `xomify-backend` (human coordination, no agent needed).
