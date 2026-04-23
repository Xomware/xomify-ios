# Plan: Xomify Social Feed — ios-nav-shell

**Epic**: [xomify-social-feed](../xomify-social-feed/PLAN.md)
**Sub-feature ID**: 2 (`ios-nav-shell`)
**Status**: Done
**Created**: 2026-04-22
**Last updated**: 2026-04-22
**Scope size**: M
**Repo(s) touched**: `xomify-ios`
**Depends on**: 1 (`repo-cleanup`)

---

## Summary

Replace `MainTabView`'s 7-tab layout with an X/Twitter-style shell: persistent top header (avatar left → drawer, "Xomify" wordmark center), 4-tab bottom bar (`Home` · `Feed` · `Releases` · `Builder`), and a slide-out side drawer hosting the demoted surfaces (Profile, Stats, Following, Friends, Groups, Ratings history, Settings, Help/About, Sign out). This is the structural prerequisite for every iOS feature-tab sub-feature that follows. Drawer destinations are stubbed in this PR — real screens land in `ios-drawer-residents` (#8).

## One-liner (from epic)

> New persistent header (avatar / wordmark / search), side drawer, 4-tab bar restructure.

---

## Critical decisions inherited from epic (do not re-litigate)

- **Nav style**: X/Twitter. Persistent top header + left drawer + 4 tabs. (Epic decision #5)
- **Tab naming**: the social tab is `Feed`, not `Social`. (Epic decision #6)
- **Tab set**: exactly 4 — `Home`, `Feed`, `Releases`, `Builder`.
- **Header content**: avatar (left, opens drawer) + "Xomify" wordmark (center). **No search icon in v1** per Locked Answer #2. Keep layout permissive for later re-add.
- **Drawer inventory**: Profile, Stats (Top Items + Wrapped sub-nav), Following, Friends (+ invite-a-friend), Groups, Ratings history, Settings, Help/About, Sign out. Real screens land in #8 / #6 / #7; this PR only wires routes + placeholders.

---

## Investigation findings (current nav structure)

Verified against the current tree under `Xomify-iOS/`:

- **App entry**: `Xomify-iOS/App/Xomify_iOSApp.swift` — `@main struct Xomify_iOSApp: App` → `ContentView()` with `.preferredColorScheme(.dark)`.
- **Root view**: `Xomify-iOS/Views/ContentView.swift` — auth gate using `@State private var authService = AuthService.shared`; switches between `MainTabView()` and `LoginView()` on `authService.isAuthenticated`. Uses `@Observable` singleton.
- **Current tab bar**: `Xomify-iOS/Views/MainTabView.swift` — plain `TabView` with 7 tabs (`Feed=0`, `ProfileView=1 (Home)`, `TopItemsView=2`, `ReleaseRadarView=3`, `WrappedView=4`, `PlaylistBuilderTabView=5`, `MoreView=6`). No top bar on the shell — each tab manages its own `NavigationStack` + `.navigationTitle`.
- **"More" screen**: `Xomify-iOS/Views/MoreView.swift` — existing list-based drawer analogue, containing Friends / Groups / Invites / Ratings / PlaylistAnalysis / MoodPicks. Will be retired; most entries migrate into the new drawer (Groups/Friends/Ratings) and the analysis/mood picks relocate under Home or are dropped (sub-feature #8 decides).
- **Project structure**: Xcode project uses `PBXFileSystemSynchronizedRootGroup` — any new `.swift` file added under `Xomify-iOS/` is automatically picked up by the `Xomify-iOS` scheme. No manual pbxproj edits required. Scheme: `Xomify-iOS`.
- **Observable pattern in use**: all services (`AuthService`, `SpotifyService`) and view models use iOS 17+ `@Observable` macro already — consistent with `.claude/rules/ios.md`.

---

## Target architecture

```
Xomify_iOSApp (@main)
   └─ ContentView                      // auth gate — unchanged responsibility
        └─ if authService.isAuthenticated
              └─ MainShell              // NEW — replaces MainTabView as root for signed-in users
                    └─ ZStack {
                        VStack {
                            HeaderBar   // NEW — persistent sticky top: avatar (L), wordmark (C), spacer (R)
                            TabView     // 4 tabs: Home / Feed / Releases / Builder
                                └─ each tab has its own NavigationStack
                        }
                        DrawerView      // NEW — slides in from leading edge, overlays TabView
                        DrawerScrim     // NEW — dim background, tap-to-close
                      }
                    .environment(navStore)
           else
              └─ LoginView              // unchanged
```

Key choices:

- **`MainShell`** owns layout; `HeaderBar` and `DrawerView` are siblings in a `ZStack` (not tab-scoped) so the header/drawer persist across tab switches.
- **`NavigationStore`** (`@Observable`, iOS 17+) is the single source of nav state: `selectedTab: ShellTab`, `isDrawerOpen: Bool`, `drawerDestination: DrawerDestination?`. Injected via `.environment(_:)`.
- **Per-tab navigation stacks** stay inside each tab's root view (existing pattern). The shell's `HeaderBar` does not own a stack — drawer destinations push via their own `NavigationStack` inside the drawer overlay.
- **Drawer lives outside `TabView`** so it overlays all tabs uniformly. Slide animation is driven by `withAnimation(.easeInOut(duration: 0.25))` toggling an offset on `DrawerView`.
- **No search icon slot** for v1, but `HeaderBar` exposes a trailing `ToolbarContent?` parameter so it can be wired in later without re-layout.

---

## Affected Files / Components

### New files

| File | Purpose |
|------|---------|
| `Xomify-iOS/Views/Shell/MainShell.swift` | New signed-in root: ZStack(TabView + DrawerView + DrawerScrim), hosts HeaderBar. |
| `Xomify-iOS/Views/Shell/HeaderBar.swift` | Sticky top bar: avatar button (L) + wordmark (C) + optional trailing slot. |
| `Xomify-iOS/Views/Shell/DrawerView.swift` | Slide-out drawer list: renders drawer entries, routes to destinations via NavigationStack. |
| `Xomify-iOS/Views/Shell/DrawerScrim.swift` | Tap-to-close dim overlay, animated opacity. |
| `Xomify-iOS/Views/Shell/ShellTab.swift` | `enum ShellTab: Hashable { case home, feed, releases, builder }` + labels + SF symbols. |
| `Xomify-iOS/Views/Shell/DrawerDestination.swift` | `enum DrawerDestination: Hashable` with cases: profile, stats, following, friends, groups, ratingsHistory, settings, helpAbout. |
| `Xomify-iOS/Navigation/NavigationStore.swift` | `@Observable` store for shell nav state. |
| `Xomify-iOS/Views/Shell/Stubs/StatsStubView.swift` | Placeholder — real screen in #8. |
| `Xomify-iOS/Views/Shell/Stubs/FollowingStubView.swift` | Placeholder — real screen in #8. |
| `Xomify-iOS/Views/Shell/Stubs/RatingsHistoryStubView.swift` | Placeholder — real screen in #8. |
| `Xomify-iOS/Views/Shell/Stubs/SettingsStubView.swift` | Minimal stub (just Sign out button lives here for now + placeholder rows). |
| `Xomify-iOS/Views/Shell/Stubs/HelpAboutStubView.swift` | Placeholder — real screen in #8. |
| `Xomify-iOS/Views/Shell/Stubs/FeedPlaceholderView.swift` | Feed tab placeholder until `ios-feed` (#5) ships. Route stays wired. |

### Modified files

| File | Change | Why |
|------|--------|-----|
| `Xomify-iOS/Views/ContentView.swift` | Swap `MainTabView()` → `MainShell()`. Pass shared `NavigationStore`. | New signed-in root. |
| `Xomify-iOS/Views/MainTabView.swift` | **Delete** (or reduce to deprecated shim for 1 PR) | Replaced by `MainShell`. |
| `Xomify-iOS/Views/MoreView.swift` | **Delete** | Drawer replaces it. Routes it owned (Friends / Groups / Ratings) move to drawer destinations. The remaining entries (PlaylistAnalysis, MoodPicks, Invites) are out of scope for this sub-feature — `ios-drawer-residents` (#8) decides whether to keep them and where. |
| `Xomify-iOS/Views/FeedView.swift` | **Untouched** here; the `ShellTab.feed` case points to `FeedPlaceholderView` until #5 ships. FeedView.swift can remain on disk unused or be deleted — defer the call to #5. | Keep existing file; don't couple the shell PR to the feed PR. |

No backend changes. No Angular changes.

---

## Drawer destinations: real vs. stub boundary

Locked here so `ios-drawer-residents` (#8) knows exactly what it inherits.

| Drawer entry | This PR ships | #8 will deliver |
|--------------|---------------|-----------------|
| Profile | Route → existing `ProfileView` (already built; lives in `Views/ProfileView.swift`). | No change, unless #8 decides to redesign. |
| Stats (Top Items + Wrapped sub-nav) | `StatsStubView` → `Text("Coming soon")`. **Route wired.** | New combined screen with internal sub-nav for Top Items + Wrapped. |
| Following | `FollowingStubView` → `Text("Coming soon")`. **Route wired.** | Real screen. |
| Friends (+ invite-a-friend) | Route → existing `FriendsView`. **No invite-a-friend CTA yet.** | `ios-friends-management` (#7) adds Invite-a-Friend CTA + share-sheet. |
| Groups | Route → existing `GroupsView`. | `ios-groups-management` (#6) fills in create/add-member/remove-member. |
| Ratings history | `RatingsHistoryStubView` → `Text("Coming soon")`. **Route wired.** Note: existing `RatingsView` is NOT reused — #8 designs a history-style view. | Real screen. |
| Settings | `SettingsStubView` → hosts **Sign out** button (real, wired to `AuthService.signOut()`) + placeholder rows. | Real settings UI (notification prefs, account). |
| Help/About | `HelpAboutStubView` → `Text("Coming soon")`. **Route wired.** | Real screen. |
| Sign out | Real — button inside Settings stub, calls `AuthService.shared.signOut()`. | No further work. |

**Rule for this PR**: every drawer entry renders, every route navigates, but only Profile / Friends / Groups / Sign out do real work. Everything else is a `Text("Coming soon")` placeholder with the correct navigation title.

---

## Navigation store design

```swift
// Xomify-iOS/Navigation/NavigationStore.swift
import SwiftUI

enum ShellTab: Hashable, CaseIterable {
    case home, feed, releases, builder

    var label: String {
        switch self {
        case .home: "Home"
        case .feed: "Feed"
        case .releases: "Releases"
        case .builder: "Builder"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .feed: "sparkles"
        case .releases: "antenna.radiowaves.left.and.right"
        case .builder: "music.note.list"
        }
    }
}

enum DrawerDestination: Hashable {
    case profile, stats, following, friends, groups
    case ratingsHistory, settings, helpAbout
}

@Observable
@MainActor
final class NavigationStore {
    var selectedTab: ShellTab = .home
    var isDrawerOpen: Bool = false
    var drawerPath: [DrawerDestination] = []   // NavigationPath-equivalent for drawer

    func openDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) { isDrawerOpen = true }
    }

    func closeDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isDrawerOpen = false
            drawerPath.removeAll()
        }
    }

    func navigate(to destination: DrawerDestination) {
        drawerPath.append(destination)
    }
}
```

- `@MainActor` because nav state is UI state; avoids strict-concurrency warnings when mutated from button actions.
- Uses `[DrawerDestination]` array instead of `NavigationPath` for `Hashable` safety and easy reset on drawer close.
- No tab-local state — each tab's internal `NavigationStack` still owns its own path (existing pattern).
- Animation config is centralised in the store so HeaderBar / Scrim / DrawerView all animate in lockstep.

---

## Implementation Steps

- [x] **1. Branch + scaffolding**
  - [x] Branch `feat/ios-nav-shell` off `master`.
  - [x] Create empty directories: `Xomify-iOS/Views/Shell/`, `Xomify-iOS/Views/Shell/Stubs/`, `Xomify-iOS/Navigation/`.
- [x] **2. Navigation store**
  - [x] Create `NavigationStore.swift` with `ShellTab`, `DrawerDestination`, `NavigationStore` as specified.
  - [x] Verify no strict-concurrency warnings (`@MainActor` on the class, `@Observable` macro).
- [x] **3. Shell primitives**
  - [x] Create `HeaderBar.swift` — sticky HStack: `AvatarButton` (36pt, leading) → `Spacer` → `Text("Xomify")` (wordmark, centered via overlay trick) → `Spacer` → trailing slot (empty for v1). Height 44pt. Dark background. VoiceOver labels per Accessibility section below.
  - [x] Create `DrawerScrim.swift` — full-screen `Color.black.opacity(0.45)` that fades with `isDrawerOpen`. Tap gesture calls `store.closeDrawer()`.
  - [x] Create `DrawerView.swift` — 280pt-wide leading panel containing a `NavigationStack(path: $store.drawerPath)`. Inside: List of drawer entries with SF symbols + labels, tapping each calls `store.navigate(to:)`. `.navigationDestination(for: DrawerDestination.self)` routes to Profile / Friends / Groups / stub views. Slides in from `.leading` via offset transform driven by `store.isDrawerOpen`.
- [x] **4. Stub destinations**
  - [x] Create each of `StatsStubView`, `FollowingStubView`, `RatingsHistoryStubView`, `HelpAboutStubView` — each a `VStack { Text("Coming soon") }` with correct `.navigationTitle`.
  - [x] Create `SettingsStubView` — includes one real button: Sign out (calls `AuthService.shared.logout()` — method exists as `logout()`).
  - [x] Create `FeedPlaceholderView` — `VStack { Image(systemName: "sparkles"); Text("Feed coming soon") }`. Keeps the route alive until #5.
- [x] **5. Shell assembly**
  - [x] Create `MainShell.swift`:
    - [x] Instantiate `@State private var navStore = NavigationStore()`.
    - [x] Body: `ZStack(alignment: .leading)` with
      - inner `VStack(spacing: 0) { HeaderBar(...); TabView(selection: $navStore.selectedTab) { ... } }`
      - `DrawerScrim` (visible when `isDrawerOpen`)
      - `DrawerView` (offset translates by -drawerWidth when closed)
    - [x] TabView content: `HomeTab` → `ProfileView()`, `.feed` → `FeedPlaceholderView()`, `.releases` → `ReleaseRadarView()`, `.builder` → `PlaylistBuilderTabView()`, each tagged with `ShellTab`.
    - [x] Inject `.environment(navStore)`.
- [x] **6. Entry rewire**
  - [x] Edit `ContentView.swift`: replace `MainTabView()` with `MainShell()`.
  - [x] Delete `MainTabView.swift`.
  - [x] Delete `MoreView.swift`. Routes that were in MoreView (PlaylistAnalysis, MoodPicks, Invites) are out of scope — deferred to #8.
- [x] **7. Avatar source**
  - [x] `HeaderBar` avatar pulls via async `SpotifyService.shared.getCurrentUser()` in `.task` on `MainShell`. Falls back to `person.crop.circle.fill` SF symbol if nil.
- [x] **8. Accessibility pass** (see Accessibility section).
- [x] **9. Build + manual smoke**
  - [x] Run `xcodebuild -project Xomify-iOS.xcodeproj -scheme Xomify-iOS -sdk iphonesimulator clean build`. BUILD SUCCEEDED.
  - [ ] Boot iPhone 15 simulator, sign in, verify: all 4 tabs switch, header stays put, avatar tap opens drawer, scrim tap closes it, each drawer entry navigates, Sign out works, stubs show "Coming soon". (Manual smoke for Dom to run)
- [x] **10. PR**
  - [x] Commit style: `#25 feat(ios): replace tab bar with X-style nav shell + drawer`.
  - [x] PR description uses the standard template with `Closes #25`, manual-test checklist.
  - [ ] Request `code-reviewer` agent pass before merge.

---

## Accessibility

- **Avatar button**: `.accessibilityLabel("Open menu")`, `.accessibilityHint("Shows profile, friends, groups, and settings")`, `.accessibilityAddTraits(.isButton)`. Minimum 44×44pt touch target even if the avatar image is 36pt.
- **Tab labels**: use `Label(tab.label, systemImage: tab.systemImage)` so VoiceOver reads "Home, tab, 1 of 4" etc. Dynamic Type support inherited from `.tabItem`.
- **Drawer entries**: each row is a `NavigationLink` with `.accessibilityLabel` matching visible text; icons marked `.accessibilityHidden(true)` so they don't double-announce.
- **Scrim**: `.accessibilityLabel("Close menu")`, `.accessibilityHint("Double-tap to dismiss")`, `.accessibilityAddTraits(.isButton)`.
- **Wordmark**: `.accessibilityLabel("Xomify")`, marked as header with `.accessibilityAddTraits(.isHeader)`.
- **Dynamic Type**: test at `.accessibility3` — tab labels should scale; if the 4-tab bar clips, fall back to icon-only labels at XL+ sizes.
- **Touch targets**: every tappable element ≥ 44×44pt. Verified in Accessibility Inspector during smoke.

---

## Build / test commands

```bash
# Clean build
xcodebuild -project Xomify-iOS.xcodeproj \
           -scheme Xomify-iOS \
           -sdk iphonesimulator \
           clean build

# Simulator run (manual smoke)
open -a Simulator
xcrun simctl boot "iPhone 15" 2>/dev/null || true
xcodebuild -project Xomify-iOS.xcodeproj \
           -scheme Xomify-iOS \
           -sdk iphonesimulator \
           -destination 'platform=iOS Simulator,name=iPhone 15' \
           test-without-building || true
```

- `.claude/CLAUDE.md` says `echo "no tests configured"` — no XCTest target exists yet, so unit tests are not required for this PR. `NavigationStore` logic (open/close/navigate) is simple enough that manual smoke covers it. If the `ios-engineer` agent wants to add a minimal XCTest target during this PR, acceptable but not required — flag for Dom's approval first.
- Manual smoke checklist (above) is the acceptance gate.

---

## PR shape

- **Branch**: `feat/ios-nav-shell`
- **Commit**: `#<issue-number> feat(ios): replace tab bar with X-style nav shell + drawer`
- **PR title**: `feat(ios): X-style nav shell + side drawer`
- **PR description**: must include `Closes #<issue-number>`, 2 simulator screenshots (home + drawer open), and the manual-smoke checklist above.
- **Reviewer**: `code-reviewer` agent.
- **Merge gate**: green build + manual smoke pass.

---

## Out of Scope

- Drawer *content* for Stats, Following, Ratings history, Help/About, Settings — stubbed here, real in `ios-drawer-residents` (#8).
- Friends Invite-a-Friend CTA + share sheet — `ios-friends-management` (#7).
- Groups create/add/remove flows — `ios-groups-management` (#6).
- Feed tab real content — `ios-feed` (#5).
- Search icon in header — dropped from v1 per epic Locked Answer #2.
- APNs permission prompt / device-token registration — `ios-notifications` (#9).
- XCTest scaffolding — project has no XCTest target; adding one is out of scope here.
- Decisions about whether PlaylistAnalysis / MoodPicks / Invites (previously in MoreView) keep a home in the drawer — deferred to #8.

---

## Risks / Tradeoffs

- **Drawer vs. tab-bar discoverability**: demoting Profile / Stats / Friends / Groups into a drawer reduces surface-level visibility. Accepted per epic Risks.
- **Shell refactor touches the app's visible root**: if this PR regresses, the whole signed-in experience breaks. Mitigation: manual smoke on simulator before merge; keep a revertable single-PR boundary (don't pile #5/#8 work into this PR).
- **`MoreView` deletion orphans PlaylistAnalysis / MoodPicks / Invites routes**: these currently reachable screens become unreachable after this PR. Mitigation: call out in PR description that #8 (`ios-drawer-residents`) will relocate or drop them; none are on the critical path.
- **Existing per-tab `NavigationStack` pattern + shell-level `HeaderBar`**: two navigation contexts could confuse SwiftUI's back-stack. Mitigation: the shell's HeaderBar is purely presentational (no push/pop); all pushes happen inside per-tab or drawer stacks.
- **Drawer animation on small devices**: 280pt drawer on iPhone SE (375pt wide) leaves only 95pt of scrim — verify tap-to-close still feels natural. Mitigation: drawer width scales to 80% of screen width, capped at 320pt.
- **Avatar fetch race**: header rendering can't block on `SpotifyService.userProfile`. Mitigation: SF symbol placeholder until image resolves.
- **`AuthService.signOut()` existence**: must verify method exists before wiring Sign-out button; if not, add in this PR (it belongs to AuthService regardless of which PR introduces it).

---

## Open Questions

- [ ] Does `SpotifyService` currently expose a `userProfile` / `currentUser.imageUrl`-style property for the avatar, or do we need to add a getter? Check `Xomify-iOS/Services/SpotifyService.swift` during step 7 — if absent, add a minimal `@Observable` read-only property; don't turn this PR into a user-profile refactor.
- [ ] Does `AuthService` already have a `signOut()` method? If not, add a minimal one (clear keychain + reset published properties). Verify in step 4.
- [ ] Keep `MoreView.swift` deleted in this PR, or keep it compiled-but-unused for one PR as an escape hatch? Recommend deleting — simpler revert story if anything goes wrong.
- [ ] Drawer edge-swipe gesture (iOS-standard swipe-from-left-edge to open) — in scope for v1 or defer? Recommend in scope (small, familiar UX win); revisit if it fights the per-tab `NavigationStack` swipe-back.

---

## Skills / Agents to Use

- **ios-engineer agent**: primary implementer. Knows `@Observable`, modern SwiftUI, MVVM split, strict concurrency.
- **code-reviewer agent**: single mandatory review pass pre-merge. Focus on concurrency warnings, force unwraps, accessibility labels, and navigation-store ownership.
- **docs-writer agent**: not needed — this plan is self-contained.
- **ios-standards skill**: invoke during step 2 (NavigationStore) + step 5 (MainShell) to double-check `@Observable` patterns and modern SwiftUI idioms.
