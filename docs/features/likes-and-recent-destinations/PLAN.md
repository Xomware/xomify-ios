# Plan: Likes & Recently Played — Top-Level Destinations + Friend-Profile Parity

**Status**: In Progress
**Created**: 2026-04-26
**Last updated**: 2026-04-26

## Heads up — third profile-area refactor in two days
Be precise about which existing files **evolve in place** vs which are **created new**. Quick legend:

| Existing file | Action |
|---|---|
| `Xomify-iOS/ViewModels/Profile/ProfileLikesViewModel.swift` | **Evolve in place** → rename file/type to `LikesViewModel`. Move out of `Profile/` into a new `Library/` (or `Likes/`) folder. Do NOT leave a `ProfileLikesViewModel` shim — every call site updates. |
| `Xomify-iOS/Views/Profile/Tabs/ProfileLikesTab.swift` | **Evolve in place** → rename to `LikesView.swift`, move out of `Tabs/`, add `.searchable`. The Likes profile-tab call site is **deleted**, not migrated. |
| `Xomify-iOS/ViewModels/Profile/ProfileRecentViewModel.swift` | **Keep as-is** — still backs the profile sub-tab (limit 10). |
| `Xomify-iOS/Views/Profile/Tabs/ProfileRecentTab.swift` | **Edit in place** — trim to 10, add "See all" footer link. |
| `RecentlyPlayedViewModel.swift` | **NEW** — sibling top-level VM with cursor pagination. |
| `RecentlyPlayedView.swift` | **NEW** — top-level destination view. |

`/execute` should not duplicate `ProfileLikesTab` into `LikesView` — it should rename.

## Summary
Promote **Likes** and **Recently Played** to first-class sidebar destinations with searchable, paginated full-list views. The Profile screen drops the `.likes` sub-tab entirely (Likes lives in the sidebar now), keeps a trimmed 10-row Recent sub-tab with a "See all" CTA, and gains a Likes count chip in the header (self only). At the same time, audit every `.other`-context gate on the four remaining profile tabs and bring friend profiles to parity for read/drill-down behavior — preserving safe self-only writes (delete, edit) while unlocking everything else.

## Goals
1. Sidebar **Likes** and **Recently Played** destinations with full-list views, client-side search, pagination.
2. Profile retains a 10-row Recent sub-tab → "See all" deep links to the new sidebar destination.
3. Profile header gains a Likes count chip (self-only) → tap deep-links to the Likes destination.
4. `.other` profile is read-equivalent to `.me`: friend-profile stat tiles tap, drill-downs work, no behavior is silently disabled.

## Non-Goals
- Web parity (sibling repo handles Angular).
- Spotify auth-scope changes — `user-library-read` and `user-read-recently-played` are already granted.
- Server-side search filters for `/me/tracks` or `/me/player/recently-played` — Spotify endpoints don't support `q=`. Search is client-side over loaded pages only.
- Native playlist detail view (still opens externally on `.other`, same as `.me`).
- Friend-profile **write** parity (rate, delete, edit on a friend's content). Reads only.
- Version bump — `/execute` handles per-phase (current master is v1.7.1).

## Approach
No prior `BRAINSTORM.md` or `RESEARCH.md`; the architecture and gating context in the user's prompt is the spec. Pre-investigation findings:

**Sidebar wiring** — `Xomify-iOS/Navigation/NavigationStore.swift` defines `enum SidebarDestination`. New cases plug into `MainShell.destinationRoot` (the `@ViewBuilder` switch) and `DrawerView` (drawer rows with SF Symbol + label). Confirmed pattern.

**Spotify recently-played pagination** — `SpotifyService.getRecentlyPlayed(limit:)` currently accepts only `limit` and discards the cursor. Spotify's endpoint **does** support `before=<cursor>` returning history older than that timestamp. We extend the service to accept `before: String?` and surface `cursors.before` from `RecentlyPlayedResponse` so the new top-level VM can paginate. Profile sub-tab keeps the no-cursor call.

**Likes total** — `/me/tracks?limit=1` returns `total` in `SavedTracksResponse`. Already wired (`ProfileLikesViewModel` reads `response.total`). For the header chip we either reuse the existing `total` after the first page loads, or do a cheap dedicated `limit=1` call. Pick the dedicated call to avoid coupling header render to the destination VM lifecycle.

**Friend-profile gating audit** (read of `ProfileSharesTab`, `ProfileRatingsTab`, `ProfileTasteTab`, `ProfilePlaylistsTab`, `ProfileHeaderView`, `ShareCardView`):

| Location | Current `.other` behavior | Verdict |
|---|---|---|
| `ProfileHeaderView.statItem` line ~168: `let isTappable = destination != nil && viewModel.context.isSelf` | Friend stat tiles (Friends / Ratings / Posts) are **not tappable**. | **Parity gap — un-gate.** This is almost certainly Dom's "I can't click on their stuff" complaint. Tapping should drill in (Friends → friend's friends list, Ratings → friend's ratings filtered, Posts → friend's posts feed scoped). For v1, keep them tappable but route to the same destinations — scope-by-friend wiring on those destinations is a separate item if not already supported. |
| `ProfileSharesTab` line 49: `onDelete: context.isSelf ? { ... } : nil` | Delete hidden on friend posts. | **Keep gated** — this is a write, not a read. |
| `ProfileSharesTab` `onOpenDetail` | Wired unconditionally. Tap opens `ShareDetailView`. | **Already at parity.** |
| `ProfileRatingsTab` line 166: `if context.isSelf { ... Delete rating ... }` | Delete menu item hidden on friend. "Open in Spotify" stays. | **Keep gated.** |
| `ProfileRatingsTab` shuffle/sample/View-all | Identical for both contexts. | **At parity.** |
| `ProfileTasteTab` | `OtherTasteView` mirrors `SelfTasteSummary` — same 9-stage carousel, sourced from `FriendProfile` payload. **No "See all" CTA on `.other`** because `TopItemsView` is self-scoped. | **Keep gated** — self-scoped Spotify endpoint, no friend equivalent. Document, don't unlock. |
| `ProfilePlaylistsTab` | `.other` uses `preloaded` slim payload, opens externally on tap (same as `.me`). Search works in both. | **At parity.** |
| `ProfileHeaderView` action button (`.other` case) line 217: `Button { /* ... */ }.disabled(true)` | "Message" button placeholder, disabled. | **Defer** — this is unimplemented in both contexts effectively. Out of scope; flag in open questions. |
| `ProfileRatingsTab.viewAllButton` line 96: `navStore.select(.ratings)` | Same on both contexts. | **Behavior bug** — for `.other`, this navigates to **viewer's own** Ratings destination, not the friend's. Same kind of issue applies to header stat-tile drill-downs. Treat as part of the same parity gap and flag as an open question (does `RatingsView` accept a target email, and if not, is it in scope here or deferred?). |

Search UX decision: **filter only the currently-loaded pages** (cheap, immediate). Add a small "Showing X of Y — load more to search older" hint when filter is active and `hasMore` is true. Justified because (a) Likes can be 10K+ tracks and auto-paginating-while-searching murders Spotify quota, (b) the typical use case is "find a song I just liked" which is at the top, (c) `.searchable` UX is responsive enough that explicit "load more" is acceptable.

## Affected Files / Components

| File / Component | Change | Why |
|---|---|---|
| `Xomify-iOS/Navigation/NavigationStore.swift` | Add `.likes` and `.recentlyPlayed` cases to `SidebarDestination`. | Top-level destinations. |
| `Xomify-iOS/Navigation/MainShell.swift` (or wherever `destinationRoot` lives) | Add `case .likes` → `LikesView()`, `case .recentlyPlayed` → `RecentlyPlayedView()`. | Wire root content. |
| `Xomify-iOS/Navigation/DrawerView.swift` (or wherever drawer rows live) | Add two new drawer entries with `heart.fill` and `clock.arrow.circlepath` SF Symbols. | Sidebar UI. |
| `Xomify-iOS/ViewModels/Profile/ProfileLikesViewModel.swift` | **Rename file → `LikesViewModel.swift`**, rename type `ProfileLikesViewModel` → `LikesViewModel`. Move out of `ViewModels/Profile/` to `ViewModels/Library/` (new folder). Add `searchQuery: String` published state and a computed `filteredTracks: [SpotifyTrack]` (case-insensitive `name` + artist names match). | Graduate to top-level destination. |
| `Xomify-iOS/Views/Profile/Tabs/ProfileLikesTab.swift` | **Rename file → `LikesView.swift`**, rename struct, move to `Views/Library/`. Add `.searchable(text:)` wired to `viewModel.searchQuery`. Render `filteredTracks` instead of `tracks`. Add the "Showing X of Y — load more to search older" hint when search is active and `hasMore`. Keep pagination triggers. | Top-level destination view. |
| `Xomify-iOS/ViewModels/UserProfileViewModel.swift` | Drop `.likes` from `ProfileTab` enum (remove case + switch arms in `title` / `systemImage`). Drop `.likes` from `visibleTabs` for both `.me` and `.other`. Remove `_likesVM` storage and `likesViewModel()` accessor. | Likes is no longer a profile sub-tab. |
| `Xomify-iOS/Views/Profile/Tabs/ProfileRecentTab.swift` | Cap rendered tracks at `prefix(10)`. Add a "See all" footer button styled like `ProfileRatingsTab.viewAllButton` that calls `navStore.select(.recentlyPlayed)`. The underlying VM still fetches 25 — limit at the view layer (cheap, avoids re-fetch on navigation back). | Profile sub-tab summary. |
| `Xomify-iOS/Views/Profile/ProfileHeaderView.swift` | (1) Add Likes count chip rendered next to existing stats (separate row OR fourth stat tile — see open question). Self-only — hidden on `.other`. Tap → `navStore.select(.likes)`. (2) **Un-gate `statItem.isTappable`**: remove the `viewModel.context.isSelf` clause. All stat tiles tappable in both contexts. Update accessibility hints. | Likes surface + parity gap fix. |
| `Xomify-iOS/Services/SpotifyService.swift` | Extend `getRecentlyPlayed` signature: `func getRecentlyPlayed(limit: Int = 25, before: String? = nil) async throws -> RecentlyPlayedResponse` (return the full response so callers can read `cursors.before`). Update existing call site in `ProfileRecentViewModel` to map `.items.map { $0.track }` from the new shape. | Pagination support. |
| `Xomify-iOS/Models/RecentlyPlayedResponse.swift` (or wherever it lives) | Verify `cursors.before` is decoded; add if missing. | Cursor pagination. |
| `Xomify-iOS/ViewModels/Library/RecentlyPlayedViewModel.swift` (new) | New `@Observable @MainActor` VM. State: `tracks: [SpotifyPlayHistory]`, `searchQuery`, `filteredTracks`, `cursorBefore: String?`, `isLoading`, `isLoadingMore`, `hasMore`, `errorMessage`. Methods: `loadIfNeeded`, `refresh`, `loadMore`. 50 per page. Mirror the `SpotifyLikesProviding` protocol pattern with a narrow `SpotifyRecentlyPlayedProviding`. | Top-level VM. |
| `Xomify-iOS/Views/Library/RecentlyPlayedView.swift` (new) | New top-level view mirroring `LikesView` structure: header, `.searchable`, infinite scroll, search hint, error/empty/loading states. Use `TrackActionsMenu` for row actions. | Top-level destination view. |
| `Xomify-iOS/Views/Profile/Tabs/ProfileRatingsTab.swift` (parity fix, Phase 5) | `viewAllButton` currently calls `navStore.select(.ratings)` regardless of context. For `.other`, route to a friend-scoped equivalent OR show a different label/disable. Decision in open questions. | Friend-profile parity. |
| `Xomify-iOS/XomifyTests/...` (if test targets exist for these VMs) | Update fixture call-sites for renamed `LikesViewModel`. Add tests for cursor pagination on `RecentlyPlayedViewModel` against a stub `SpotifyRecentlyPlayedProviding`. | Test parity. |

## Implementation Steps

### Phase 1 — Sidebar destinations scaffolded (PR 1)
- [x] Add `case likes` and `case recentlyPlayed` to `SidebarDestination` in `NavigationStore.swift` (alphabetical position OK, drawer order separate).
- [x] Locate `MainShell.destinationRoot` (or equivalent root switch) and add temporary stub views: `LikesView()` and `RecentlyPlayedView()` returning `Text("Likes")` / `Text("Recently Played")` — actual implementations land in Phase 2 / 3.
- [x] Locate `DrawerView` and add two new drawer entries with `heart.fill` (Likes) and `clock.arrow.circlepath` (Recently Played). Order: place adjacent to Music Taste (also a music-data destination). See open question on exact ordering.
- [x] Build green: `xcodebuild -scheme Xomify-iOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`.
- [ ] Manual: open drawer, confirm both entries appear, tap each, confirm stub renders.

### Phase 2 — LikesView (top-level) (PR 2)
- [ ] Rename `ProfileLikesViewModel.swift` → `LikesViewModel.swift`. Rename type. Move to `ViewModels/Library/`.
- [ ] Add `var searchQuery: String = ""` to `LikesViewModel`.
- [ ] Add computed `var filteredTracks: [SpotifyTrack]` — case-insensitive contains on `name` and joined `artistNames`. When `searchQuery.isEmpty`, return `tracks` directly (no copy).
- [ ] Rename `ProfileLikesTab.swift` → `LikesView.swift`. Rename struct. Move to `Views/Library/`.
- [ ] Wrap body in a `NavigationStack` (top-level destinations stand alone, not inside ProfileView's stack).
- [ ] Add `.searchable(text: $viewModel.searchQuery, prompt: "Search liked songs")`.
- [ ] Replace `viewModel.tracks` references with `viewModel.filteredTracks` in the list `ForEach`.
- [ ] Add "Showing X of Y — load more to search older" hint footer when `!searchQuery.isEmpty && viewModel.hasMore`.
- [ ] Keep existing pagination trigger (`onAppear` near end-of-list).
- [ ] Replace stub in `MainShell.destinationRoot` with real `LikesView()`.
- [ ] Update any other `ProfileLikesViewModel` references — there should be one (the lazy accessor in `UserProfileViewModel`) and that gets removed in Phase 4.
- [ ] Build green per command above.
- [ ] Manual: open Likes from drawer, confirm pagination still works, type into search and confirm filter is responsive, tap "load more" hint and confirm older results appear in filtered results.

### Phase 3 — RecentlyPlayedView (top-level) (PR 3)
- [ ] In `SpotifyService.swift`, extend `getRecentlyPlayed`: change signature to `(limit: Int = 25, before: String? = nil) async throws -> RecentlyPlayedResponse`. Build URL with `&before=\(cursor)` when provided. Return the full response, not just `items`.
- [ ] Update `ProfileRecentViewModel` to call the new signature: `let response = try await spotifyService.getRecentlyPlayed(limit: 25, before: nil); recentlyPlayed = response.items.map { $0.track }`. Update `SpotifyRecentProviding` protocol method signature accordingly.
- [ ] Verify `RecentlyPlayedResponse` model decodes `cursors.before` (string-encoded epoch ms). Add the field if missing.
- [ ] Create `Xomify-iOS/ViewModels/Library/RecentlyPlayedViewModel.swift`. Model on `LikesViewModel`: `@Observable @MainActor`, narrow protocol `SpotifyRecentlyPlayedProviding`, page size 50, state for `tracks`, `cursorBefore`, `isLoading`, `isLoadingMore`, `hasMore`, `errorMessage`, `searchQuery`, computed `filteredTracks`.
- [ ] `loadMore` passes `before: cursorBefore`. `hasMore = response.cursors?.before != nil`.
- [ ] Note: `/me/player/recently-played` does not return a total count; treat `hasMore` purely off cursor presence and don't render a `total` chip.
- [ ] Create `Xomify-iOS/Views/Library/RecentlyPlayedView.swift` mirroring `LikesView` structure (header without count chip, `.searchable`, infinite scroll, hint footer, states). Use `TrackActionsMenu` for row actions.
- [ ] Replace stub in `MainShell.destinationRoot`.
- [ ] Build green.
- [ ] Manual: open Recently Played from drawer, scroll to trigger pagination, confirm older history loads, search filters loaded pages.

### Phase 4 — Profile updates (PR 4)
- [ ] In `UserProfileViewModel.swift`: remove `case likes` from `ProfileTab` enum, remove the corresponding `title` / `systemImage` switch arms, remove `.likes` from `visibleTabs` for both contexts (already absent on `.other`), delete `_likesVM` storage and `likesViewModel()` accessor.
- [ ] Find ProfileView (or whichever screen renders the tab content switch) and remove the `case .likes:` branch. Build will tell you where.
- [ ] In `ProfileRecentTab.swift`: change `tracks: viewModel.recentlyPlayed` → `tracks: Array(viewModel.recentlyPlayed.prefix(10))`. After the `VStack(spacing: 8)` rendering rows, append a "See all" button (lift the gradient style from `ProfileRatingsTab.viewAllButton`) that calls `navStore.select(.recentlyPlayed)`. Show the button only when `viewModel.recentlyPlayed.count >= 10` (no point if there are fewer than 10).
- [ ] Inject `@Environment(NavigationStore.self) private var navStore` into `ProfileRecentTab` (currently doesn't have it).
- [ ] In `ProfileHeaderView.swift`: add a Likes count chip. Recommended: a fourth `statItem` in `statsRow` (icon-led tile with `heart.fill` color `.xomifyGreen`), self-only (`if viewModel.context.isSelf`). Tap → `navStore.select(.likes)`. Source the count from a new lightweight `loadLikesCount()` in `UserProfileViewModel` that calls `spotifyService.getSavedTracks(limit: 1, offset: 0)` and stores `response.total` in a new `var likesCount: Int?`.
- [ ] Add `loadLikesCount` to the `loadSelfHeader` parallel `async let` block; ignore failures (chip just doesn't render).
- [ ] Build green.
- [ ] Manual: profile no longer shows Likes pill in tab picker; Recent tab shows max 10 with "See all" footer; tap → lands on Recently Played destination; back button returns to profile (verify push/swap behavior — see risks). Header shows Likes chip with count; tap → lands on Likes destination.

### Phase 5 — Friend-profile parity (PR 5)
- [ ] In `ProfileHeaderView.statItem`, change `let isTappable = destination != nil && viewModel.context.isSelf` → `let isTappable = destination != nil`. Both contexts can tap.
- [ ] Verify accessibility hints still make sense in `.other` context (they say "Opens \(label) page" — fine).
- [ ] **Decide and document** the destination behavior on `.other`:
  - Friends tile → `.friends` destination shows viewer's own friends, not the profile-owner's. If `FriendsView` already accepts a target email param, route there with `context.email`. Otherwise, ship the un-gate **and** file a follow-up issue for friend-scoped friends/ratings/posts views — flag this in the PR description as known partial parity.
  - Same call applies to Ratings (`viewAllButton` in `ProfileRatingsTab` line 96) and Posts (no current drill-down — only the header tile).
- [ ] Re-audit `ProfileSharesTab`, `ProfileRatingsTab`, `ProfileTasteTab`, `ProfilePlaylistsTab` against the table in the Approach section. If anything else surfaces during implementation (e.g. tap targets disabled, menus hidden), enumerate it in the PR description.
- [ ] Confirm Likes chip is **not** rendered on `.other` (Spotify endpoint is self-scoped — chip would always be empty/wrong).
- [ ] Confirm Recent sub-tab is still self-only on profile (it's only in `.me` `visibleTabs`).
- [ ] Build green.
- [ ] Manual: navigate to a known friend's profile, tap each of the three stat tiles, confirm each navigates to a sensible destination (or note any gaps in PR). Tap a friend's share card → `ShareDetailView` should open. Confirm no delete buttons appear.

## Out of Scope
- Web (Angular sibling repo) parity for any of this.
- Spotify auth-scope changes.
- Server-side filtering for `/me/tracks` or `/me/player/recently-played`.
- Native playlist detail view.
- Friend-scoped writes (rate / delete / edit on friend's content).
- Implementing the disabled "Message" button on friend profile header.
- Building friend-scoped `FriendsView` / `RatingsView` / posts feed if they don't already accept a target email — file a follow-up issue, do not block this PR series.
- Version bump (`/execute` handles).
- Backend changes (a backend agent is running concurrently in another session — this feature is iOS-only).

## Risks / Tradeoffs
- **"See all" deep-link from inside a profile NavigationStack push**: `navStore.select(.recentlyPlayed)` switches the root `currentDestination` and closes the drawer. If the user was viewing a friend profile pushed onto a NavigationStack, switching the root destination effectively unmounts that stack. Verify behavior during Phase 4 manual test: tapping "See all" from a friend's profile Recent tab should take you to the global Recently Played destination (which shows **your** recent plays, not theirs — Spotify endpoint is self-scoped). Document this in the "See all" button's accessibility hint or just rely on the fact that friend profiles don't show the Recent sub-tab (it's not in `.other` `visibleTabs`). **Mitigation: this risk is moot** — Recent sub-tab is `.me`-only, so "See all" only appears on your own profile.
- **Search UX over partial pages**: filtering only loaded pages can confuse users with large libraries. Mitigation: explicit "Showing X of Y — load more to search older" hint when `!searchQuery.isEmpty && hasMore`.
- **Spotify rate limits**: low risk. `/me/tracks` and `/me/player/recently-played` are not aggressive endpoints. Pagination is triggered by user scroll, not on a timer.
- **Breaking existing `ProfileLikesViewModel` references**: rename touches every call site. Build will flush them out. Risk is low because the type is only used by `UserProfileViewModel.likesViewModel()` (which is being removed in Phase 4) and the renamed `LikesView`.
- **Header layout shift from a fourth stat tile**: four tiles in a row may crowd the existing layout. Mitigation: if it looks bad, fall back to a separate count chip row below the stats (open question).
- **Friend-profile drill-downs may land on viewer-scoped destinations**: un-gating the stat tiles ships a navigation that doesn't perfectly scope to the friend. This is honest progress (better than disabled) but should be flagged in PR description and in a follow-up issue.

## Open Questions
- [ ] **Drawer ordering**: where do `Likes` and `Recently Played` go in the drawer? Adjacent to Music Taste? Adjacent to Profile? Pick during Phase 1 — current cases list in `SidebarDestination` suggests grouping `[musicTaste, wrapped, releaseRadar, ratings]` is the "music-data" cluster; recommend slotting Likes + Recently Played at the top of that cluster.
- [ ] **Likes count chip placement**: fourth tile in the existing 3-tile `statsRow`, OR a separate row below? Recommend: try fourth tile first; fall back to separate row if cramped at iPhone SE width.
- [ ] **Recently Played count chip**: include one? `/me/player/recently-played` does not return a total. Recommend: no chip — header just shows the icon + label.
- [ ] **Friend-scoped destinations**: do `FriendsView`, `RatingsView`, and the Posts feed (`FeedView`?) accept a target email parameter? If not, do we (a) implement target-scoping as part of Phase 5, (b) ship Phase 5 with imperfect parity and file follow-ups, or (c) gate the friend-stat-tile taps until target-scoping exists? Recommend (b) — keep Phase 5 small, file follow-ups.
- [ ] **`ProfileRatingsTab.viewAllButton` on `.other`**: currently navigates to viewer's own ratings. Same decision as above — recommend changing the label to "View all" without scoping for now, file follow-up.

## Skills / Agents to Use
- **ios-standards skill**: load before any view/VM work to confirm `@Observable`, `foregroundStyle`, `NavigationStack`, async/await conventions are followed. Cited in `.claude/rules/ios.md`.
- **swift-engineer agent (if available)**: delegate the per-phase code edits — each phase is independent and well-scoped, ideal for a delegated execution pass.
- **debug-build agent (if available)**: invoke after each phase's edits to run the `xcodebuild` smoke and surface any compiler errors before manual testing.
