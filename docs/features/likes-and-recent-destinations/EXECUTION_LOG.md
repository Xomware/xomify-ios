# Execution Log: Likes & Recently Played — Top-Level Destinations + Friend-Profile Parity

## [2026-04-26 11:41] — Phase 1: Sidebar destinations scaffolded

- **Action**: Added `likes` and `recentlyPlayed` cases to `SidebarDestination`, stub views to `MainShell.destinationRoot`, two drawer entries in `DrawerView`
- **Files changed**: `NavigationStore.swift`, `MainShell.swift`, `DrawerView.swift`, `Views/Library/LikesView.swift` (new), `Views/Library/RecentlyPlayedView.swift` (new), `project.pbxproj`
- **Decisions**: Placed Likes + Recently Played adjacent to Feed (after Feed, before Music Taste) per plan default. Stubs return Text placeholders.
- **Result**: success — PR #85 merged, version bumped to 1.8.0

## [2026-04-26 12:00] — Phase 2: LikesView top-level destination

- **Action**: Evolved `ProfileLikesViewModel` → `LikesViewModel` (moved to `ViewModels/Library/`). Evolved `ProfileLikesTab` → `LikesView` (moved to `Views/Library/`). Added `searchQuery`/`filteredTracks`, `.searchable`, search hint footer. Moved `SpotifyLikesProviding` protocol into `LikesViewModel.swift`. Updated `UserProfileViewModel` to reference `LikesViewModel`.
- **Files changed**: `LikesViewModel.swift` (renamed/moved), `LikesView.swift` (replaced stub), `UserProfileViewModel.swift`, `ProfileView.swift`, `project.pbxproj`. Deleted `ProfileLikesViewModel.swift`, `ProfileLikesTab.swift`.
- **Decisions**: `SpotifyLikesProviding` protocol moved to `LikesViewModel.swift` since old file was deleted. Profile `.likes` tab case updated to use `LikesView()` temporarily until Phase 4 removes it.
- **Result**: success — PR #86 merged, version bumped to 1.9.0

## [2026-04-26 12:15] — Phase 3: RecentlyPlayedView top-level destination

- **Action**: Extended `getRecentlyPlayed` to accept `before: String?` and return `RecentlyPlayedResponse`. Added `cursors.before` to `RecentlyPlayedResponse` model. Updated `ProfileRecentViewModel` + `SpotifyRecentProviding` protocol. Created `RecentlyPlayedViewModel` with cursor pagination. Replaced `RecentlyPlayedView` stub with full implementation.
- **Files changed**: `SpotifyService.swift`, `SpotifyModels.swift`, `ProfileRecentViewModel.swift`, `RecentlyPlayedViewModel.swift` (new), `RecentlyPlayedView.swift` (replaced stub), `project.pbxproj`
- **Decisions**: Created `SpotifyRecentlyPlayedProviding` as a separate protocol from `SpotifyRecentProviding` to keep top-level VM independent from profile VM.
- **Result**: success — PR #87 merged, version bumped to 1.10.0

## [2026-04-26 12:30] — Phase 4: Profile updates

- **Action**: Removed `case likes` from `ProfileTab` enum and all switch arms. Removed `_likesVM`/`likesViewModel()` from `UserProfileViewModel`. Added `likesCount: Int?` populated via parallel `getSavedTracks(limit:1)`. Added self-only Likes stat chip to `ProfileHeaderView`. Capped `ProfileRecentTab` to `prefix(10)` with "See all" button. Injected `NavigationStore` into `ProfileRecentTab`.
- **Files changed**: `UserProfileViewModel.swift`, `ProfileView.swift`, `ProfileRecentTab.swift`, `ProfileHeaderView.swift`, `project.pbxproj`
- **Decisions**: Used `SpotifyService.shared.getSavedTracks` directly in `loadSelfHeader` parallel block rather than extending `SpotifyCurrentUserProviding` — simpler and non-critical (failure is silently ignored).
- **Result**: success — PR #88 merged, version bumped to 1.11.0

## [2026-04-26 12:45] — Phase 5: Friend-profile stat tile parity

- **Action**: Removed `&& viewModel.context.isSelf` from `statItem.isTappable` in `ProfileHeaderView`. All stat tiles now tappable in both `.me` and `.other` contexts.
- **Files changed**: `ProfileHeaderView.swift`, `project.pbxproj`
- **Decisions**: Shipped with viewer-scoped destinations for friend stat tiles (partial parity). Filed as known limitation in PR #89 description. Friend-scoped FriendsView/RatingsView/posts-feed scoping is a follow-up item.
- **Result**: success — PR #89 merged, version bumped to 1.12.0

## Final Summary

All 5 phases complete. Plan status set to Done.

| Phase | PR | Version | Summary |
|---|---|---|---|
| 1 | #85 | 1.8.0 | Sidebar stubs scaffolded |
| 2 | #86 | 1.9.0 | LikesView with search/pagination |
| 3 | #87 | 1.10.0 | RecentlyPlayedView with cursor pagination |
| 4 | #88 | 1.11.0 | Profile: remove Likes tab, Recent cap+CTA, Likes chip |
| 5 | #89 | 1.12.0 | Friend profile stat tile parity |
