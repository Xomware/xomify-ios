# Execution Log: iOS Nav & IA Cleanup

## 2026-04-23 17:00 — Step 1: Phase 1 — Navigation model (NavigationStore.swift)

- **Action**: Rewrote `NavigationStore.swift` completely.
  - Deleted `ShellTab` enum and `DrawerDestination` enum.
  - Introduced `SidebarDestination` enum with 9 cases: `.feed`, `.wrapped`, `.releaseRadar`, `.ratings`, `.groups`, `.friends`, `.profile`, `.settings`, `.builder`.
  - Replaced `selectedTab: ShellTab` and `drawerPath: [DrawerDestination]` with `currentDestination: SidebarDestination = .feed`.
  - Added `select(_ destination: SidebarDestination)` — sets `currentDestination` and calls `closeDrawer()` in a single `withAnimation` block.
  - Rewrote `consumePendingDeepLink()` to call `select(destination)` instead of `openDrawer()` + `drawerPath.append(destination)`.
  - Deleted `navigate(to:)` helper (no longer needed).
- **Files changed**: `Xomify-iOS/Navigation/NavigationStore.swift`
- **Decisions**: Kept `requestDeepLink(_:)` / `pendingDeepLink` / `consumePendingDeepLink()` intact — Feed's empty-state CTAs depend on this async two-step pattern.
- **Result**: success

## 2026-04-23 17:05 — Step 2: Phase 2 — Shell rewrite (MainShell.swift)

- **Action**: Rewrote `MainShell.swift`.
  - Deleted the entire `TabView` block and all four `.tabItem` branches.
  - Replaced with a single `NavigationStack` whose root is a `@ViewBuilder switch` over `navStore.currentDestination`.
  - All 9 `SidebarDestination` cases map to their destination views.
  - Retained `ZStack` layering: content column → `DrawerScrim` → `DrawerView`.
  - Retained `.onChange(of: navStore.pendingDeepLink)` hook and `consumePendingDeepLink()` dispatch.
  - Removed the `await MainActor.run` wrapper in `fetchAvatar()` — no longer needed because `MainShell` is already on MainActor via `@Observable` pattern.
- **Files changed**: `Xomify-iOS/Views/Shell/MainShell.swift`
- **Decisions**: `NavigationStack` wraps just the destination root — `HeaderBar` remains outside the stack so the nav bar doesn't double-render a title bar.
- **Result**: success

## 2026-04-23 17:10 — Step 3: Phase 3 — Drawer dismiss/select fix (DrawerView.swift)

- **Action**: Rewrote `DrawerView.swift`.
  - Deleted the `NavigationStack(path:)` wrapper — drawer panel root is now a plain `List`.
  - Deleted `navigationDestination(for:)` modifier and `destinationView(for:)` helper.
  - Each `Button` action calls `navStore.select(entry.destination)` — dismiss + navigation in one call.
  - Deleted the legacy "Sign out" section from the drawer (logout is now in `SettingsView` Danger Zone).
  - Reordered entries to: Feed, Wrapped, Release Radar, Ratings, Groups, Friends, Profile, Settings, Playlist Builder (9 rows).
  - Added active-destination highlight: selected row gets `Color.xomifyGreen.opacity(0.15)` background.
  - Applied `.frame(minHeight: 44)` on each row for VoiceOver / touch-target compliance.
  - Changed `DrawerEntry` to `Identifiable` by `SidebarDestination` so `ForEach` doesn't need the `id:` hack.
- **Files changed**: `Xomify-iOS/Views/Shell/DrawerView.swift`
- **Decisions**: Removed the sign-out row from the drawer. Auth-level actions now live in Settings Danger Zone only — this avoids having logout in two places and matches the plan's intent that the drawer is a pure menu.
- **Result**: success

## 2026-04-23 17:20 — Step 4: Phase 4 — Settings extraction

### SettingsViewModel.swift (expanded)
- **Action**: Expanded the existing `SettingsViewModel` (which only covered notification prefs) to absorb everything that was in `ProfileViewModel` relating to Settings:
  - Added `isWrappedEnrolled`, `isReleaseRadarEnrolled`, `isUpdatingEnrollment`.
  - Added `toggleWrappedEnrollment()`, `toggleReleaseRadarEnrollment()`, `loadXomifyStatus(email:)`.
  - Added `user: SpotifyUser?` private backing store plus computed `country`, `accountType`, `userId`, `spotifyProfileUrl`, `userEmail`.
  - Added `logout()` → `authService.logout()`.
  - Added `load()` entry point that concurrently refreshes APNs status and fetches the Spotify user + Xomify enrollment.
  - Dependency typed as `XomifyService` directly (not `XomifyServicing` protocol) because `getUserData` / `updateEnrollments` are not in that protocol surface — matches existing `ProfileViewModel` pattern.
- **Files changed**: `Xomify-iOS/ViewModels/SettingsViewModel.swift`

### SettingsView.swift (rewritten)
- **Action**: Rewrote `SettingsView` at its existing path (`Views/Shell/Destinations/SettingsView.swift`).
  - Sections: Notifications, Features (enrollment toggles), Account (country/subscription/User ID rows + Spotify link), About (version/build), Legal, Support, Danger Zone (logout).
  - All list rows have `.frame(minHeight: 44)` for 44pt touch targets.
  - Account rows use `.accessibilityElement(children: .combine)` + explicit labels.
  - Enrollment toggles have `.accessibilityLabel` set.
  - Logout goes through `viewModel.logout()` not `AuthService.shared.logout()` directly.
  - Calls `viewModel.load()` in `.task` (loads user + enrollment + APNs status in one shot).
- **Files changed**: `Xomify-iOS/Views/Shell/Destinations/SettingsView.swift`

### ProfileViewModel.swift (slimmed)
- **Action**: Removed everything that moved to `SettingsViewModel`:
  - Deleted: `isWrappedEnrolled`, `isReleaseRadarEnrolled`, `isUpdatingEnrollment`, `toggleWrappedEnrollment()`, `toggleReleaseRadarEnrollment()`, `loadXomifyStatus(email:)`, `accountType`, `isPremium`, `country`, `userId`, `spotifyProfileUrl`, `logout()`, `xomifyService`, `authService` dependencies, `xomifyUser` backing store, `playlistCount`.
  - Kept: `user`, `displayName`, `email`, `profileImageUrl`, `followersCount`, `followingCount`, `isLoading`, `errorMessage`, `loadProfile()`.
- **Files changed**: `Xomify-iOS/ViewModels/ProfileViewModel.swift`

### ProfileView.swift (slimmed)
- **Action**: Removed settings-related sections from `ProfileView`:
  - Deleted: `enrollmentSection`, `enrollmentCard(...)`, `accountSection`, `accountRow(...)`, `logoutButton`, `showLogoutConfirmation` state, `.confirmationDialog` modifier, `NavigationStack` wrapper (profile is now always pushed inside `MainShell`'s `NavigationStack`), `xomifyLogo` toolbar item.
  - Kept: `bannerHeader`, `profileHeader`, `statsSection` (Followers + Following-link card), `quickStatsSection` (Top Songs / Top Artists / Top Genres nav links).
  - Replaced `foregroundColor` with `foregroundStyle` (modern API).
  - Applied `clipShape(RoundedRectangle(...))` instead of `.cornerRadius()` (modern API).
  - Added VoiceOver labels on stat cards and profile image.
- **Files changed**: `Xomify-iOS/Views/ProfileView.swift`
- **Result**: success

## 2026-04-23 17:30 — Step 5: Phase 5 — Default landing + push routing fix (NotificationsService.swift)

- **Action**: Fixed `handlePushOpen(payload:)` in `NotificationsService.swift`.
  - Changed `navigationStore?.selectedTab = .feed` → `navigationStore?.select(.feed)`.
  - `selectedTab` no longer exists on `NavigationStore`; this was the compile-time blocker for the push pipeline.
- **Files changed**: `Xomify-iOS/Services/NotificationsService.swift`
- **Decisions**: No structural change to `NotificationsService`. The fix is a one-liner.
- **Result**: success

## 2026-04-23 17:35 — Step 6: Phase 6 — Cleanup

- **Action**:
  - Grepped for `MainTabView` — not found in any active source files (only in pre-existing stale worktree copies under `.claude/worktrees/`). Nothing to delete.
  - `PlaylistBuilderTabView.swift` kept — Playlist Builder promoted to sidebar row #9 per resolved open question.
  - Verified no new compile errors from changed files. Build run against `iPhone 17` simulator.
  - All 6 compile errors are pre-existing in `AuthService.swift` (`SpotifyImage` ambiguous, `SpotifyUserProfile` Codable conformance, `SpotifyImage` redeclaration) — these existed before this feature work.
  - Grepped for `ShellTab`, `DrawerDestination`, `selectedTab`, `drawerPath`, `navigate(to:)` — all remaining hits are local variables unrelated to `NavigationStore` (e.g. `@State private var selectedTab = 0` in `WrappedView`).
- **Files changed**: none (cleanup confirmed, nothing to delete)
- **Result**: success — zero new errors introduced

## 2026-04-23 17:40 — Final summary

**Status**: Done

### Files changed
| File | Change |
|------|--------|
| `Xomify-iOS/Navigation/NavigationStore.swift` | Full rewrite — `SidebarDestination` enum, `currentDestination`, `select()`, deep-link retarget |
| `Xomify-iOS/Views/Shell/MainShell.swift` | Full rewrite — removed `TabView`, added `NavigationStack` switch on `currentDestination` |
| `Xomify-iOS/Views/Shell/DrawerView.swift` | Full rewrite — removed inner `NavigationStack`, 9 entries calling `select()`, active highlight |
| `Xomify-iOS/Views/Shell/Destinations/SettingsView.swift` | Full rewrite — Notifications + Features + Account + About + Legal + Support + Danger Zone |
| `Xomify-iOS/ViewModels/SettingsViewModel.swift` | Expanded — absorbed enrollment, account, logout from ProfileViewModel |
| `Xomify-iOS/ViewModels/ProfileViewModel.swift` | Slimmed — identity + counts only |
| `Xomify-iOS/Views/ProfileView.swift` | Slimmed — removed enrollment/account/logout sections |
| `Xomify-iOS/Services/NotificationsService.swift` | One-liner fix — `selectedTab = .feed` → `select(.feed)` |

### Open items for Phase 7 Manual QA (not automated)
- Cold launch → Feed is the visible screen
- Drawer open/close via avatar tap
- Each sidebar row dismisses drawer and takes full screen
- Scrim tap dismisses without changing destination
- Feed empty-state CTAs deep-link to Friends/Groups
- Push notification open routes to Feed
- Profile shows no settings items
- Settings shows Features, Account, Danger Zone
- Logout from Settings works
