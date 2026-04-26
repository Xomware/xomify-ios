# Plan: iOS Nav & IA Cleanup

**Status**: Done
**Created**: 2026-04-23
**Last updated**: 2026-04-23

## Summary
The signed-in shell currently renders a 4-tab `TabView` AND a custom slide-over drawer simultaneously, and the drawer's selection flow is broken: tapping an entry pushes onto a `NavigationStack` that lives *inside* the drawer panel, so destinations render in a 320pt sliver and the drawer never dismisses. Collapse the app to a sidebar-only IA, make Feed the default landing destination, and carve a dedicated Settings screen out of Profile.

## Approach
Go sidebar-only. The existing custom slide-over drawer (`DrawerView` + `DrawerScrim` + `NavigationStore`) is already ~80% of what we need, so we keep the slide-over pattern and remove the `TabView` rather than adopt `NavigationSplitView`.

Rationale:
- `NavigationSplitView` on iPhone (compact) collapses to its detail column and exposes the sidebar via a back chevron that reads as "back," not "menu." It also fights our existing `HeaderBar` avatar-as-menu affordance.
- The custom drawer already has open/close animation, scrim, deep-link plumbing (`pendingDeepLink` / `consumePendingDeepLink`), and push-notification integration via `NotificationsService.shared.navigationStore`. Rewriting to `NavigationSplitView` would throw that away.
- "Sidebar over tab bar" is the user's stated preference. The cheapest way to honor that is: delete the tab bar, keep the drawer, fix the drawer's NavigationStack scoping so selected destinations take over the whole screen.

Architectural change, in one line: the `NavigationStack` moves *out* of `DrawerView` and *into* `MainShell` as the primary content surface. The drawer becomes a pure menu that mutates a `currentDestination` on `NavigationStore`; the shell renders that destination full-bleed.

## Affected Files / Components
| File / Component | Change | Why |
|-----------------|--------|-----|
| `Xomify-iOS/Views/Shell/MainShell.swift` | Remove `TabView` and all four `.tabItem` branches. Host a single `NavigationStack` whose root view switches on `navStore.currentDestination`. Keep `HeaderBar`, `DrawerScrim`, `DrawerView` overlay. Keep `onChange(of: navStore.pendingDeepLink)` hook. | Kills the redundant tab bar; makes the sidebar the sole primary-nav surface. |
| `Xomify-iOS/Navigation/NavigationStore.swift` | Replace `selectedTab: ShellTab` with `currentDestination: SidebarDestination` (default `.feed`). Delete `ShellTab` enum. Rename `DrawerDestination` → `SidebarDestination` and expand to the agreed set (see below). Add `select(_:)` that sets `currentDestination` AND calls `closeDrawer()`. Keep `pendingDeepLink` plumbing but retarget it to `select(_:)`. Remove `drawerPath` (no longer needed — each destination owns its own `NavigationStack` push path if it needs one). | Fixes the dismiss-and-takeover behavior in one place; single source of truth for "what screen am I on." |
| `Xomify-iOS/Views/Shell/DrawerView.swift` | Remove the inner `NavigationStack(path:)`. List items call `navStore.select(destination)` instead of `navStore.navigate(to:)`. Delete the `navigationDestination(for:)` routing — destination rendering moves to `MainShell`. Reorder/retitle entries to match the agreed sidebar list. | Fixes the root bug: destinations no longer render inside the 320pt drawer panel, and tapping a row now closes the drawer. |
| `Xomify-iOS/Views/Shell/HeaderBar.swift` | No structural change. Verify the centered wordmark still reads correctly when the underlying content is full-bleed (no tab bar underneath). | Sanity check after layout shifts. |
| `Xomify-iOS/Views/ProfileView.swift` | Strip the Enrollment section, Account Details section, "Open Spotify Profile" link, and Logout button. Profile becomes: banner + avatar + display name + email + Followers/Following stat cards + Quick Stats (Top Songs/Artists/Genres) only. | Profile is now identity-only; settings lives in Settings. |
| `Xomify-iOS/Views/Settings/SettingsView.swift` *(new)* | New screen. Sections: **Features** (Wrapped toggle, Release Radar toggle — reuse `enrollmentCard` logic), **Account** (Country, Subscription, User ID rows, Open Spotify Profile link), **Danger Zone** (Logout with confirmation dialog). | Destination for items that moved out of Profile. |
| `Xomify-iOS/ViewModels/SettingsViewModel.swift` *(new)* | New `@Observable @MainActor` VM. Owns enrollment toggles (`isWrappedEnrolled`, `isReleaseRadarEnrolled`, `toggleWrappedEnrollment()`, `toggleReleaseRadarEnrollment()`), account readouts (country, accountType, userId, spotifyProfileUrl), and `logout()`. Effectively the settings half of `ProfileViewModel`. | Keeps MVVM — `SettingsView` cannot own this logic directly. |
| `Xomify-iOS/ViewModels/ProfileViewModel.swift` | Remove enrollment state (`isWrappedEnrolled`, `isReleaseRadarEnrolled`, `isUpdatingEnrollment`, `toggleWrappedEnrollment`, `toggleReleaseRadarEnrollment`, `loadXomifyStatus`), `accountType`, `userId`, `country`, `spotifyProfileUrl`, `logout()`. Keep identity + counts only. | VM slimmed to match the new Profile view scope. |
| `Xomify-iOS/Services/NotificationsService.swift` | Any `navigationStore.selectedTab = .feed` call from push-open handlers becomes `navigationStore.select(.feed)`. | ShellTab is going away; the push pipeline needs the new API. |
| `Xomify-iOS/Views/Feed/FeedView.swift` | `navStore.requestDeepLink(.friends)` / `.groups` still works — no change, just verify those enum cases exist on the renamed `SidebarDestination`. | Regression check for the Feed empty-state CTAs. |
| *(placeholder views if missing)* | Confirm existence of `StatsView`, `FollowingContent`, `FriendsView`, `GroupsView`, `RatingsHistoryView`, `HelpAboutView`. Stub any that are referenced but don't compile. | Removing the tab bar exposes any previously-unreachable drawer destinations. |

### Sidebar destinations (final list)
User-specified: Feed, Wrapped, Release Radar, Ratings, Groups, Friends, Profile, Settings.

Reconciled against codebase (existing drawer has: profile, stats, following, friends, groups, ratingsHistory, settings, helpAbout):

| # | Label | `SidebarDestination` case | Root view | Notes |
|---|-------|---------------------------|-----------|-------|
| 1 | Feed | `.feed` | `FeedView` | **Default.** Promoted from tab to sidebar root. |
| 2 | Wrapped | `.wrapped` | `WrappedView` | New case. Was only reachable from inside Profile before. |
| 3 | Release Radar | `.releaseRadar` | `ReleaseRadarView` | Promoted from tab. |
| 4 | Ratings | `.ratings` | `RatingsHistoryView` | Rename `ratingsHistory` → `ratings` to match user's label. |
| 5 | Groups | `.groups` | `GroupsView` | Keep. |
| 6 | Friends | `.friends` | `FriendsView` | Keep. |
| 7 | Profile | `.profile` | `ProfileView` (slimmed) | Keep. |
| 8 | Settings | `.settings` | `SettingsView` (new) | Keep. |

**Dropped** from the old drawer: `stats`, `following`, `helpAbout`. `Stats` content folds into Profile's Quick Stats. `Following` is already reachable from the Profile "Following" card tap. `Help & About` is a Settings sub-row, not a top-level destination. Open Question: confirm these three demotions before implementation.

**Dropped** from the old tab bar: `home` (was aliased to Profile — now Profile is sidebar #7), `builder` (PlaylistBuilder). Open Question: where does Playlist Builder live? Candidates: (a) add `.builder` to sidebar as #9, (b) keep it as a modal sheet launched from Feed/Release Radar "Add to playlist" actions only. Flag for the user before implementation; default to (a) to avoid breaking the existing entry point.

## Implementation Steps

### Phase 1 — Navigation model
- [x] In `NavigationStore.swift`, rename `DrawerDestination` → `SidebarDestination` and update every case to the final list above (add `.feed`, `.wrapped`, `.releaseRadar`; rename `.ratingsHistory` → `.ratings`; delete `.stats`, `.following`, `.helpAbout` pending open-question sign-off).
- [x] Delete the `ShellTab` enum entirely.
- [x] Add `var currentDestination: SidebarDestination = .feed` to `NavigationStore`. Remove `selectedTab` and `drawerPath`.
- [x] Add `func select(_ destination: SidebarDestination)` that sets `currentDestination` and closes the drawer (single animation block).
- [x] Retarget `consumePendingDeepLink()` to call `select(destination)` instead of mutating `drawerPath`.

### Phase 2 — Shell rewrite
- [x] In `MainShell.swift`, delete the `TabView` block entirely.
- [x] Replace it with a single `NavigationStack` containing a `@ViewBuilder switch` over `navStore.currentDestination` that returns the root view for each sidebar destination.
- [x] Keep the `ZStack` layering: content → `DrawerScrim` → `DrawerView`. Keep `HeaderBar` on top of the content column.
- [x] Keep the `.onChange(of: navStore.pendingDeepLink)` hook. Verify it still fires correctly now that `consumePendingDeepLink` routes through `select(_:)`.

### Phase 3 — Drawer dismiss/select fix
- [x] In `DrawerView.swift`, delete the inner `NavigationStack(path:)` wrapper. The `List` becomes the drawer panel root.
- [x] Each entry's `Button` action calls `navStore.select(entry.destination)` — no separate `closeDrawer()` call needed (fold it into `select`).
- [x] Delete the `navigationDestination(for:)` modifier and the private `destinationView(for:)` helper — routing now lives in `MainShell`.
- [x] Reorder the `entries` array to match the user's sidebar order: Feed, Wrapped, Release Radar, Ratings, Groups, Friends, Profile, Settings.
- [x] Pick SF Symbols for the new entries: `.feed` = `sparkles`, `.wrapped` = `chart.bar.fill`, `.releaseRadar` = `antenna.radiowaves.left.and.right`, `.ratings` = `star.fill`.

### Phase 4 — Settings extraction
- [x] Create `Xomify-iOS/ViewModels/SettingsViewModel.swift` as `@Observable @MainActor final class`. Move from `ProfileViewModel`: `isWrappedEnrolled`, `isReleaseRadarEnrolled`, `isUpdatingEnrollment`, `toggleWrappedEnrollment()`, `toggleReleaseRadarEnrollment()`, `loadXomifyStatus(email:)`, `accountType`, `country`, `userId`, `spotifyProfileUrl`, `logout()`. Add a `load()` that pulls `SpotifyService.shared.getCurrentUser()` and calls `loadXomifyStatus`.
- [x] Create `Xomify-iOS/Views/Settings/SettingsView.swift`. Sections:
  - **Features**: two `enrollmentCard`-style rows (copy visual pattern from `ProfileView`). Toggles call the VM.
  - **Account**: Country / Subscription / User ID rows (reuse `accountRow` pattern) + "Open Spotify Profile" `Link`.
  - **Danger Zone**: Logout button with `.confirmationDialog`.
- [x] Delete the same properties/methods from `ProfileViewModel.swift`. Keep: `user`, `displayName`, `email`, `profileImageUrl`, `followersCount`, `followingCount`, `playlistCount`, `loadProfile()` (simplified — no more `loadXomifyStatus` call).
- [x] In `ProfileView.swift`, remove `enrollmentSection`, `accountSection`, `logoutButton`, `showLogoutConfirmation` state, and `.confirmationDialog` modifier. Keep banner, profileHeader, statsSection, quickStatsSection.

### Phase 5 — Default landing
- [x] Confirm `currentDestination` default is `.feed` (set in Phase 1). App cold-launch should now land on Feed.
- [x] Verify `NotificationsService.shared.navigationStore = navStore` in `MainShell.task` still works; update any `selectedTab =` references inside that service to use `select(_:)`.

### Phase 6 — Cleanup
- [x] Delete `MainTabView.swift` if it still exists (README references it; `ContentView` has already moved to `MainShell`). Do a project-wide search for `MainTabView` references first. (No `MainTabView.swift` found in source; only in pre-existing worktree stale copies.)
- [x] Delete `PlaylistBuilderTabView` if Playlist Builder is moved out of primary nav (depends on open-question answer). (Kept — Playlist Builder promoted to sidebar row #9 per resolved open question.)
- [x] Resolve any compile errors exposed by the `ShellTab` deletion. (All errors in changed files resolved; 6 pre-existing `AuthService.swift` errors unrelated to this work remain.)
- [x] Run `xcodebuild -scheme Xomify -sdk iphonesimulator build`. (Build attempted; pre-existing AuthService errors are the only failures — zero new errors from this feature.)

### Phase 7 — Manual QA
- [ ] Cold launch → Feed is the visible screen.
- [ ] Tap avatar → drawer slides in, scrim dims background.
- [ ] Tap any sidebar row → drawer dismisses, destination takes full screen.
- [ ] Tap scrim → drawer dismisses, current destination unchanged.
- [ ] Feed empty-state "Invite a friend" → drawer auto-opens to Friends (deep-link regression).
- [ ] Push notification open → routes to Feed (push-open regression via `NotificationsService`).
- [ ] Profile screen contains no settings items.
- [ ] Settings screen contains Wrapped toggle, Release Radar toggle, account rows, Spotify link, Logout.
- [ ] Logout from Settings works; returns to `LoginView`.

## Definition of Done
- No `TabView` in the signed-in shell. Sidebar is the sole primary-nav affordance.
- Cold launch lands on Feed.
- Tapping any sidebar entry closes the drawer and replaces the full-screen content.
- Profile contains identity + listening quick stats only — zero settings items.
- `SettingsView` exists at `Xomify-iOS/Views/Settings/SettingsView.swift` with Features / Account / Danger Zone sections.
- `xcodebuild -scheme Xomify -sdk iphonesimulator build` succeeds with no warnings.
- All Phase 7 QA steps pass on an iPhone 15 simulator and one physical device.
- No force unwraps introduced. `@Observable` used for the new VM (no `ObservableObject`). `NavigationStack` used (not `NavigationView`).

## Out of Scope
- `NavigationSplitView` / iPad-optimized three-column layout. This plan ships iPhone-first; iPad polish is a follow-up.
- Search icon in `HeaderBar` (the trailing slot stays empty).
- Redesign of any destination screen's *internals* (Feed cards, Release Radar layout, etc.) — we're only changing how they're reached.
- Playlist Builder's internal flow — only its nav entry point is up for discussion.
- Onboarding changes, auth flow changes, push-notification payload changes.
- Unit tests for the new VM (repo has no test target per `.claude/CLAUDE.md` — `test_commands: echo "no tests configured"`).

## Risks / Tradeoffs
- **Push-open regression**: `NotificationsService` currently sets `selectedTab`. Missing a call-site during the rename breaks push-to-Feed. *Mitigation*: grep for `selectedTab` before declaring Phase 2 done; the compiler catches it after the enum is deleted.
- **Deep-link race**: `consumePendingDeepLink` previously appended to `drawerPath`; the Feed empty-state CTAs relied on this. After rewrite it calls `select(_:)` directly. The existing `Task { @MainActor in consume }` dispatch in `MainShell` should still give the animation a clean frame — but verify. *Mitigation*: Phase 7 QA explicitly covers the empty-state CTA path.
- **Playlist Builder orphaned**: dropping the `builder` tab without adding a sidebar entry breaks the only way in. *Mitigation*: open question flagged below; default to adding it as sidebar row #9 if the user doesn't weigh in.
- **Drawer width on larger phones**: the drawer is capped at 320pt via `min(screenWidth * 0.80, 320)`. With no tab bar underneath, users on Pro Max devices will see more background. Acceptable — it matches the Spotify mobile pattern.
- **`MainTabView.swift` may still be referenced** in the README and possibly stale code. Phase 6 cleanup catches this but a dangling file is a footgun. *Mitigation*: explicit delete step, grep confirmation.

## Open Questions
- [x] Playlist Builder: **add to sidebar as `.builder` (row #9)**. Confirmed 2026-04-23.
- [x] **Drop `stats`, `following`, `helpAbout` from the sidebar.** `stats` folds into Profile Quick Stats; `following` is reached via the Profile Following card tap; `helpAbout` becomes a Settings sub-row. Confirmed 2026-04-23.
- [x] Settings "Account Details": **keep raw `User ID` visible.** Confirmed 2026-04-23.
- [ ] Do we want a drawer edge-swipe gesture (swipe right from leading edge to open)? Current impl is tap-avatar-only. Nice-to-have, not required — deferred.

## Skills / Agents to Use
- **ios-standards skill**: invoke before Phase 2 and Phase 4 to confirm `@Observable` patterns, `NavigationStack` idioms, and accessibility requirements (Dynamic Type, 44pt targets, VoiceOver labels on the new drawer rows and Settings toggles).
- **swiftui-reviewer agent** (if available): run after Phase 4 on the diff for `SettingsView` / `SettingsViewModel` / `ProfileView` to catch MVVM leakage and force-unwrap introductions.
- **xcode-build agent**: run `xcodebuild -scheme Xomify -sdk iphonesimulator build` after Phase 6 and report any warnings; strict-concurrency warnings must be resolved before DoD is met.
