# Plan: Xomify Social Feed — ios-drawer-residents

**Epic**: [xomify-social-feed](../xomify-social-feed/PLAN.md)
**Sub-feature ID**: 8 (`ios-drawer-residents`)
**Status**: Ready
**Created**: 2026-04-22
**Last updated**: 2026-04-22
**Scope size**: M
**Repo(s) touched**: `xomify-ios`
**Depends on**: 2 (`ios-nav-shell` — merged)

---

## Summary

Replace the five "Coming soon" drawer stubs left behind by `ios-nav-shell` with real screens. Four of the six drawer destinations in scope are relocation + glue work (Profile is already wired; Following reuses existing `FollowingView`; Stats composes existing `TopItemsView` + `WrappedView` under a segmented sub-nav; Settings builds on the existing `SettingsStubView`). Two are net-new: a **Stats** wrapper screen and a **Ratings history** screen that binds to the already-shipped `XomifyService.getAllRatings(email:)` call. Friends, Groups, Sign out are already live post-nav-shell and are explicitly out of scope here.

## One-liner (from epic)

> Profile, Stats (Top Items + Wrapped sub-nav), Following, Ratings history, Settings, Help/About, Sign out. Mostly relocating existing views + one new combined Stats view + new Ratings history view.

---

## Critical decisions inherited from epic (do not re-litigate)

- **Drawer inventory is fixed** per epic Scope. This sub-feature covers Profile, Stats, Following, Ratings history, Settings, Help/About. Friends (#7) and Groups (#6) live in separate sub-features and are wired already by `ios-nav-shell`.
- **Stats is a combined screen**: Top Items + Wrapped live under a single Stats entry with internal sub-nav. See epic Scope.
- **Relocation, not redesign**: existing `ProfileView`, `WrappedView`, `TopItemsView`, `FollowingView` are composed into drawer destinations largely as-is.
- **Ratings history is net-new at the UI layer only**: reads from existing `/ratings/all` backend (already wired in `XomifyService.getAllRatings`). No backend work required.
- **Sign out stays in the drawer** (bottom `Button(role: .destructive)` in `DrawerView`, wired to `AuthService.shared.logout()`). We also keep a Sign out row inside real `SettingsView` for parity with platform conventions.

---

## Investigation findings (current state, 2026-04-22)

Verified against the current tree under `Xomify-iOS/`:

### Drawer wiring (from `ios-nav-shell`)
- `DrawerDestination` enum (profile, stats, following, friends, groups, ratingsHistory, settings, helpAbout) lives in `Xomify-iOS/Navigation/NavigationStore.swift` (confirmed by nav-shell plan; the current `DrawerView.swift` imports it via `@Environment(NavigationStore.self)`).
- `Xomify-iOS/Views/Shell/DrawerView.swift` already declares the 8 drawer entries, renders them with SF symbols, and routes via `destinationView(for:)`. The sign-out button sits at the bottom and calls `AuthService.shared.logout()`.
- Current routing (from `DrawerView.swift:116-133`):
  - `.profile` → `ProfileView()` (REAL, nothing to do)
  - `.stats` → `StatsStubView()` (STUB)
  - `.following` → `FollowingStubView()` (STUB — real `FollowingView` exists but is not wired)
  - `.friends` → `FriendsView()` (REAL — out of scope, owned by #7)
  - `.groups` → `GroupsView()` (REAL — out of scope, owned by #6)
  - `.ratingsHistory` → `RatingsHistoryStubView()` (STUB)
  - `.settings` → `SettingsStubView()` (STUB, has real Sign out)
  - `.helpAbout` → `HelpAboutStubView()` (STUB)

### Existing views we relocate / reuse
- `Xomify-iOS/Views/ProfileView.swift` — already the `profile` destination. No changes.
- `Xomify-iOS/Views/FollowingView.swift` — full-featured (search, empty/error states, artist rows). Wraps its content in a `NavigationStack` with its own title. **Will clash** with the drawer's `NavigationStack` if dropped in as-is. Fix: refactor to render bare content when pushed from the drawer (no inner `NavigationStack`) while keeping the existing API.
- `Xomify-iOS/Views/TopItemsView.swift` — same `NavigationStack` wrapping issue. Used by Stats sub-nav.
- `Xomify-iOS/Views/WrappedView.swift` — same. Used by Stats sub-nav.

### Existing services
- `AuthService.logout()` — synchronous, clears keychain + state. Confirmed at `Xomify-iOS/Services/AuthService.swift:346`.
- `XomifyService.getAllRatings(email:)` — already implemented at `Xomify-iOS/Services/XomifyService.swift:362`. Returns `RatingsAllResponse { email, ratings: [TrackRating], totalCount }`. **No backend work needed.**
- `XomifyService.removeRating(email:trackId:)` — already implemented; supports delete from history.

### Existing models
- `TrackRating` (`Xomify-iOS/Models/SocialModels.swift:387`): `{ email, trackId, trackName?, artistName?, rating: Int, review?, createdAt?, updatedAt? }`. Identifiable by `trackId`. No new model required.
- `RatingsAllResponse` (`SocialModels.swift:400`): `{ email?, ratings: [TrackRating]?, totalCount? }`.

### What's **not** on disk
- No `SettingsView.swift`, `HelpAboutView.swift`, `StatsView.swift`, `RatingsHistoryView.swift`, `RatingsHistoryViewModel.swift` — all net-new in this PR.
- No `UserProfileService` separate from `SpotifyService` / `AuthService`. Sign-out wiring uses `AuthService.shared.logout()` directly from the view (matches the existing `DrawerView` and `SettingsStubView` patterns).

### Backend endpoints
- `GET /ratings/all?email=...` — **exists and is deployed**. Verified by its presence in `XomifyService.getAllRatings`. No lambda work needed; **no missing backend endpoints for this sub-feature.**

---

## Per-destination specification

### 1. Profile (`.profile`) — no-op

- **Shows**: existing `ProfileView` (banner, stats, quickStats, enrollment toggles, account info, logout button).
- **Action**: already wired. Confirm it pushes cleanly into the drawer's `NavigationStack` (verify its inner `NavigationStack` doesn't break back-navigation; if so, extract a `ProfileContentView` body the same way we do for Following/TopItems/Wrapped — see step 4).
- **Data**: `ProfileViewModel.loadProfile()` (unchanged).
- **Acceptance**: tap Profile in drawer → shows profile → back chevron returns to drawer list.

### 2. Stats (`.stats`) — NEW wrapper

- **Shows**: a new `StatsView` that hosts a segmented picker (`Picker(...).pickerStyle(.segmented)`) at the top with two options: **Top Items** and **Wrapped**. Body swaps between `TopItemsContent()` and `WrappedContent()` (the de-`NavigationStack`'d bodies of the existing views — see step 4).
- **Replaces**: `Xomify-iOS/Views/Shell/Stubs/StatsStubView.swift` (deleted).
- **New file**: `Xomify-iOS/Views/Shell/Destinations/StatsView.swift`.
- **Data**: inherited from `TopItemsViewModel` / existing `WrappedView` state. No new service calls.
- **Actions**: all actions already in Top Items / Wrapped (playlist builder FAB, save-to-Spotify, etc.) continue to work. Playlist-builder sheet presentation should be hoisted once at `StatsView` level so switching tabs doesn't unmount an active sheet mid-operation.
- **Navigation title**: `"Stats"` with `navigationBarTitleDisplayMode(.inline)`. Segmented picker sits in the safe area just below the nav bar (matches `TopItemsView`'s current `categorySelector` layout).
- **State preservation**: the picker state (`@State private var selected: StatsTab = .topItems`) is local to `StatsView`. Each sub-view keeps its own internal state (TimeRange, selected category, etc.) across picker flips because the SwiftUI diff keeps the subview identity stable — verify by flipping Top Items → Wrapped → Top Items and asserting the term selector stays where it was.

**Decision — segmented picker vs. `TabView(.page)`**: use a **segmented picker**. Page-style TabView has a long-running bug with `NavigationStack` and `scrollContentBackground(.hidden)` interactions; the segmented picker is simpler, lighter, and matches the existing pattern already used inside `TopItemsView` (`categorySelector`) and `WrappedView` (`tabPicker`). No swipe gesture tradeoff — users discover the option via the visible control.

### 3. Following (`.following`) — relocated

- **Shows**: existing `FollowingView` content (search bar + artist rows, loading/error/empty states).
- **Replaces**: `Xomify-iOS/Views/Shell/Stubs/FollowingStubView.swift` (deleted).
- **Update**: refactor `FollowingView` so the **inner `NavigationStack` is removed** when pushed into the drawer. Approach: split into `FollowingView` (existing, keeps its `NavigationStack` for any other caller) and a new internal `FollowingContent` body view that the drawer uses. Simpler alternative: add a `@Environment(\.isInsideDrawer)` bool (custom `EnvironmentKey`) and conditionally skip the inner `NavigationStack`. **Decision: go with the split-view approach.** It's explicit, has no hidden environment-coupling, and the shared body is a single View struct.
- **Data**: `SpotifyService.shared.getFollowedArtists()` (unchanged).
- **Actions**: artist row taps into `ArtistView(artistId:)` still push on the drawer stack (confirm `ArtistView` itself does not inject a second `NavigationStack` — if it does, the same split-view refactor applies there; verify during step 4).
- **Navigation title**: `"Following"` with `navigationBarTitleDisplayMode(.inline)` plus the existing `count` sub-label toolbar.

### 4. Ratings History (`.ratingsHistory`) — NEW

- **Shows**: a scrollable list of the user's past ratings, sorted by `updatedAt ?? createdAt` **descending** (most-recent first). Each row shows: track name, artist, star rating (1–5 visualized with `star.fill`/`star`), optional review snippet (1 line, `.lineLimit(1)`), relative time.
- **Replaces**: `Xomify-iOS/Views/Shell/Stubs/RatingsHistoryStubView.swift` (deleted).
- **New files**:
  - `Xomify-iOS/Views/Shell/Destinations/RatingsHistoryView.swift`
  - `Xomify-iOS/ViewModels/Social/RatingsHistoryViewModel.swift`
- **Data**: `XomifyService.shared.getAllRatings(email:)`. VM stores `ratings: [TrackRating]`, `isLoading: Bool`, `errorMessage: String?`. `.task` triggers initial load; `.refreshable` re-fetches. Email source: `AuthService.shared` → current user via existing `SpotifyService` `/me` call (match the pattern used by `ProfileViewModel.loadProfile()`).
- **Actions**:
  - Tap row → navigate to a simple detail view (stretch: push `ArtistView` or open Spotify track link if `trackId` resolves). **Minimum v1**: tap opens the Spotify track URI via `UIApplication.shared.open(URL(string: "spotify:track:\(trackId)")!)` — fail silently if not installed. No detail screen.
  - Swipe-to-delete row → `XomifyService.removeRating(email:trackId:)`; optimistic removal with rollback on error.
- **Navigation title**: `"Ratings History"`.
- **Empty state**: "No ratings yet" + SF symbol `star.slash`.
- **Error state**: "Couldn't load ratings" + retry button.
- **Accessibility**: each row has a combined `accessibilityLabel` like "`<track>` by `<artist>`, rated `<n>` out of 5", `.accessibilityHint("Double-tap to open in Spotify")`, star icons marked `.accessibilityHidden(true)`.

### 5. Settings (`.settings`) — replaces `SettingsStubView`

- **Shows** (top to bottom):
  1. **Notifications** section — two `Toggle` rows: "Push notifications" and "Weekly digest". Backed by `@AppStorage("xomify.notifications.pushEnabled")` and `@AppStorage("xomify.notifications.digestEnabled")` (default `true`). **TODO comment** on each: `// TODO(#9): wire to NotificationsService.registerDeviceToken once ios-notifications ships.`
  2. **About** section — two read-only rows:
     - "Version" → `Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"`
     - "Build" → `Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"`
  3. **Legal** section — two `Link` rows:
     - "Privacy Policy" → `https://xomify.xomware.com/privacy`
     - "Terms of Service" → `https://xomify.xomware.com/terms`
  4. **Support** section — one `Link`:
     - "Email support" → `mailto:support@xomware.com` (confirm address in Open Questions).
  5. **Danger zone** — `Button(role: .destructive)` "Sign out" calling `AuthService.shared.logout()`. Wrapped in a `confirmationDialog` ("Sign out of Xomify?") to prevent accidental taps.
- **Replaces**: `Xomify-iOS/Views/Shell/Stubs/SettingsStubView.swift` (deleted).
- **New file**: `Xomify-iOS/Views/Shell/Destinations/SettingsView.swift`.
- **Data**: none (all static + local `@AppStorage`).
- **Navigation title**: `"Settings"`.
- **Accessibility**: toggles announce on/off state; destructive button announces "Sign out, button, destructive".

### 6. Help & About (`.helpAbout`) — replaces `HelpAboutStubView`

- **Shows** (vertically stacked inside a `ScrollView` so it Dynamic-Type-grows cleanly):
  1. App logo (`Image("logo")`, 96pt, rounded) + wordmark "Xomify".
  2. Version line: `"Version <x> (<build>)"`.
  3. Short tagline: `"Your Spotify companion — smarter Release Radar, monthly Wrapped, and now shared with friends."`
  4. Section `Support` — "Email support" link (same address as Settings).
  5. Section `Legal` — "Privacy Policy", "Terms of Service" (duplicate of Settings links; acceptable — users expect to find them in either place).
  6. Section `Acknowledgements` — single `NavigationLink("Open Source Licenses")` → `Text("Acknowledgements coming soon")` placeholder (licenses generation is out of scope for v1; file an issue if we ever bundle third-party Swift packages).
- **Replaces**: `Xomify-iOS/Views/Shell/Stubs/HelpAboutStubView.swift` (deleted).
- **New file**: `Xomify-iOS/Views/Shell/Destinations/HelpAboutView.swift`.
- **Data**: none; `Bundle.main` lookups for version strings.
- **Navigation title**: `"Help & About"`.

---

## Affected Files / Components

### New files

| File | Purpose |
|------|---------|
| `Xomify-iOS/Views/Shell/Destinations/StatsView.swift` | Combined Top Items + Wrapped wrapper with segmented picker. |
| `Xomify-iOS/Views/Shell/Destinations/RatingsHistoryView.swift` | List of user's past ratings. |
| `Xomify-iOS/Views/Shell/Destinations/SettingsView.swift` | Real Settings screen (notifications toggles, about, legal, sign out). |
| `Xomify-iOS/Views/Shell/Destinations/HelpAboutView.swift` | Static Help & About content. |
| `Xomify-iOS/ViewModels/Social/RatingsHistoryViewModel.swift` | `@Observable @MainActor` VM for ratings list. |

### Modified files

| File | Change | Why |
|------|--------|-----|
| `Xomify-iOS/Views/Shell/DrawerView.swift` | Update `destinationView(for:)` switch: `.stats` → `StatsView()`, `.following` → `FollowingView()` (drawer-mode overload), `.ratingsHistory` → `RatingsHistoryView()`, `.settings` → `SettingsView()`, `.helpAbout` → `HelpAboutView()`. | Point routes at real screens. |
| `Xomify-iOS/Views/FollowingView.swift` | Extract body into a `FollowingContent` view that renders without a wrapping `NavigationStack`. `FollowingView` stays and becomes a thin `NavigationStack { FollowingContent() }` wrapper for any standalone caller; the drawer uses `FollowingContent` directly. | Avoid nested `NavigationStack`s when pushed from the drawer. |
| `Xomify-iOS/Views/TopItemsView.swift` | Same split: extract `TopItemsContent`. Keep `TopItemsView` as a `NavigationStack { TopItemsContent() }` wrapper for any existing tab-level caller. | Used by `StatsView`. |
| `Xomify-iOS/Views/WrappedView.swift` | Same split: extract `WrappedContent`. | Used by `StatsView`. |

### Deleted files

- `Xomify-iOS/Views/Shell/Stubs/StatsStubView.swift`
- `Xomify-iOS/Views/Shell/Stubs/FollowingStubView.swift`
- `Xomify-iOS/Views/Shell/Stubs/RatingsHistoryStubView.swift`
- `Xomify-iOS/Views/Shell/Stubs/SettingsStubView.swift`
- `Xomify-iOS/Views/Shell/Stubs/HelpAboutStubView.swift`

(Any other stubs in `Xomify-iOS/Views/Shell/Stubs/` — e.g. `FeedPlaceholderView.swift` — are **not** this sub-feature's concern. Feed is sub-feature #5.)

No backend changes. No Angular changes. No new models.

---

## Implementation Steps

- [ ] **1. Branch + scaffolding**
  - [ ] Branch `feat/ios-drawer-residents` off `master`.
  - [ ] Create directory `Xomify-iOS/Views/Shell/Destinations/`.
  - [ ] Verify PBXFileSystemSynchronizedRootGroup picks up new files automatically (confirmed in nav-shell plan — no pbxproj edits needed).

- [ ] **2. Split existing views so their bodies push cleanly**
  - [ ] `FollowingView.swift`: extract the current body into `struct FollowingContent: View`. Make `FollowingView` a 3-line wrapper: `NavigationStack { FollowingContent() }`. Preserve all `@State`, `spotifyService`, and methods on `FollowingContent`.
  - [ ] `TopItemsView.swift`: extract `struct TopItemsContent: View` the same way.
  - [ ] `WrappedView.swift`: extract `struct WrappedContent: View` the same way.
  - [ ] Build and verify nothing regresses in the Home tab (which still uses `ProfileView`) or anywhere else `TopItemsView` / `WrappedView` are referenced.

- [ ] **3. Build `StatsView`**
  - [ ] Create `Xomify-iOS/Views/Shell/Destinations/StatsView.swift`.
  - [ ] Declare `enum StatsTab: String, CaseIterable, Hashable { case topItems = "Top Items", wrapped = "Wrapped" }`.
  - [ ] Body: `VStack { Picker("", selection: $selected) { ForEach(StatsTab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(); content }`.
  - [ ] `@ViewBuilder content`: switch on `selected` → `TopItemsContent()` / `WrappedContent()`.
  - [ ] Background: `Color.xomifyDark.ignoresSafeArea()`.
  - [ ] Navigation title "Stats", inline display mode.
  - [ ] Hoist `PlaylistBuilderManager.shared.isShowing` sheet presentation at `StatsView` level (already implicitly hoisted because both children reference the same singleton — verify nothing double-presents).

- [ ] **4. Build `RatingsHistoryViewModel`**
  - [ ] Create `Xomify-iOS/ViewModels/Social/RatingsHistoryViewModel.swift`.
  - [ ] `@Observable @MainActor final class RatingsHistoryViewModel` with: `ratings: [TrackRating] = []`, `isLoading = false`, `errorMessage: String? = nil`.
  - [ ] `func load() async` — fetch current user's email via `SpotifyService.shared.getCurrentUser()` (mirroring `ProfileViewModel`), then `XomifyService.shared.getAllRatings(email:)`. Sort descending by `updatedAt ?? createdAt ?? ""`. Handle errors into `errorMessage`.
  - [ ] `func delete(_ rating: TrackRating) async` — optimistic remove from `ratings`, call `XomifyService.shared.removeRating(email:trackId:)`, on error re-insert and set `errorMessage`.

- [ ] **5. Build `RatingsHistoryView`**
  - [ ] Create `Xomify-iOS/Views/Shell/Destinations/RatingsHistoryView.swift`.
  - [ ] `@State private var viewModel = RatingsHistoryViewModel()`.
  - [ ] `List { ForEach(viewModel.ratings) { rating in RatingRow(rating: rating) } .onDelete { indexSet in ... } }` — use `.swipeActions` instead of `onDelete` if we want a styled destructive button with an icon.
  - [ ] `.task { await viewModel.load() }` + `.refreshable { await viewModel.load() }`.
  - [ ] Empty / error / loading states per spec.
  - [ ] Tap row: open `spotify:track:<trackId>` URL; guard non-nil; if open fails, no-op.
  - [ ] Private `RatingRow` subview renders `VStack(alignment: .leading) { Text(trackName).font(.subheadline); Text(artistName).font(.caption).foregroundStyle(.gray); HStack { starRow; Spacer(); Text(relativeTime).font(.caption2) } }`. Accessibility labels per spec.

- [ ] **6. Build `SettingsView`**
  - [ ] Create `Xomify-iOS/Views/Shell/Destinations/SettingsView.swift`.
  - [ ] `@AppStorage("xomify.notifications.pushEnabled") private var pushEnabled = true`.
  - [ ] `@AppStorage("xomify.notifications.digestEnabled") private var digestEnabled = true`.
  - [ ] `@State private var showSignOutConfirm = false`.
  - [ ] `List` with Notifications / About / Legal / Support / Danger sections exactly as spec'd above.
  - [ ] `.confirmationDialog("Sign out of Xomify?", isPresented: $showSignOutConfirm, titleVisibility: .visible) { Button("Sign out", role: .destructive) { AuthService.shared.logout() }; Button("Cancel", role: .cancel) {} }`.
  - [ ] Match existing dark-mode styling: `.listRowBackground(Color.xomifyCard)`, `.scrollContentBackground(.hidden)`, `.background(Color.xomifyDark.ignoresSafeArea())`.

- [ ] **7. Build `HelpAboutView`**
  - [ ] Create `Xomify-iOS/Views/Shell/Destinations/HelpAboutView.swift`.
  - [ ] `ScrollView { VStack(alignment: .leading, spacing: 16) { header; versionLine; tagline; Divider(); sections } }`.
  - [ ] Version helper: `private var versionString: String { let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"; let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"; return "Version \(v) (\(b))" }`.
  - [ ] Links use `Link(destination:)` with the same URLs as Settings.
  - [ ] Acknowledgements row is a `NavigationLink` to a placeholder `Text("Acknowledgements coming soon")` view.

- [ ] **8. Rewire `DrawerView` routes**
  - [ ] Update the `destinationView(for:)` switch:
    - `.stats` → `StatsView()`
    - `.following` → `FollowingContent()` (bare — drawer owns the `NavigationStack`) with `.navigationTitle("Following").navigationBarTitleDisplayMode(.inline)` applied at the destination site.
    - `.ratingsHistory` → `RatingsHistoryView()`
    - `.settings` → `SettingsView()`
    - `.helpAbout` → `HelpAboutView()`
  - [ ] Leave `.profile`, `.friends`, `.groups` untouched.

- [ ] **9. Delete stubs**
  - [ ] Remove the 5 stub files listed above.
  - [ ] Confirm `Xomify-iOS/Views/Shell/Stubs/FeedPlaceholderView.swift` is **not** deleted — it belongs to sub-feature #5.

- [ ] **10. Accessibility pass**
  - [ ] Dynamic Type test at `.accessibility3` on all 5 new/modified screens.
  - [ ] VoiceOver pass on Settings toggles + destructive Sign out + Ratings row labels.
  - [ ] 44pt minimum touch targets on every tappable element (Ratings row, Settings toggles, Help links).
  - [ ] Icons decorative-only: `.accessibilityHidden(true)`.

- [ ] **11. Build + manual smoke**
  - [ ] `xcodebuild -project Xomify-iOS.xcodeproj -scheme Xomify-iOS -sdk iphonesimulator clean build`.
  - [ ] Boot simulator, sign in, open drawer, verify each of the 6 destinations: Profile / Stats (picker flips) / Following / Ratings History (loads data, swipe-to-delete works, tap opens Spotify) / Settings (toggles persist, Sign out works) / Help & About.
  - [ ] Flip drawer open/closed between destinations; back chevron always returns to drawer list.
  - [ ] Re-verify Friends / Groups still work (regression guard on nav-shell wiring).

- [ ] **12. PR**
  - [ ] Commit style: `#<issue-number> feat(ios): real drawer destinations (stats, ratings history, settings, help/about)`.
  - [ ] PR description uses `Closes #<issue-number>`, includes smoke checklist + 3 simulator screenshots (Stats with picker, Ratings History list, Settings).
  - [ ] Request `code-reviewer` agent pass before merge.

---

## Out of Scope

- **Friends** drawer destination (handled by `ios-friends-management` #7 — adds Invite-a-Friend CTA + share sheet).
- **Groups** drawer destination (handled by `ios-groups-management` #6 — adds create / add-member / remove-member flows).
- **APNs registration** + real notification preferences wiring (`ios-notifications` #9). The toggles in Settings are `@AppStorage`-backed stubs with a TODO comment linking to #9.
- **New backend endpoints** — none required. `/ratings/all` and `/ratings/remove` are already deployed and wired in `XomifyService`.
- **Profile redesign** — Profile route is already wired by nav-shell; this sub-feature only verifies the nested-`NavigationStack` concern doesn't break back-navigation.
- **Acknowledgements / licenses generation** — single placeholder row; full OSS license bundling deferred to a future plan when third-party Swift packages are introduced.
- **Deep links from ratings to a full track detail page** — v1 opens the Spotify app directly via `spotify:track:` URL. A bespoke in-app track detail screen is not in scope.
- **Analytics** on drawer-destination taps — not in scope for this PR (no analytics framework wired in the app yet).

---

## Risks / Tradeoffs

- **Nested `NavigationStack`s on `FollowingView` / `TopItemsView` / `WrappedView`**: dropping any of them into a drawer destination as-is produces a navigation-bar-inside-navigation-bar glitch and double back chevrons. Mitigation: the split-body refactor in step 2. **Not optional** — must ship with this PR. Verify manually because SwiftUI won't warn at compile time.
- **Stats picker state preservation**: flipping between Top Items and Wrapped must not reset each sub-view's internal state (selected term, category, loaded tracks). SwiftUI keeps identity stable for each `@ViewBuilder` branch because the struct types differ, but confirm in smoke by setting term=long-term in Top Items, flipping to Wrapped, flipping back, and asserting long-term is still selected. If it regresses, hoist the relevant state into `StatsView` or introduce `@StateObject`-like caching via a shared `@Observable` store.
- **Playlist builder sheet double-presentation**: `TopItemsContent` and `WrappedContent` each present `PlaylistBuilderView()` on `PlaylistBuilderManager.shared.isShowing`. With both mounted inside `StatsView`'s `@ViewBuilder` switch, only one is instantiated at a time — so no double-presentation. Leave as-is, but confirm in smoke.
- **Ratings API latency on cold start**: `/ratings/all` can be a full DynamoDB scan for heavy users. Loading state must show a `ProgressView`; no hard timeout in v1 — rely on URLSession default (60s).
- **`@AppStorage` toggles are a stub, not real prefs**: they persist locally but don't sync to the backend. Users will assume they do. Mitigation: add a small `Text("Preferences take effect in a future update")` footer to the Notifications section — sets expectation until #9 ships.
- **Sign out lives in two places**: drawer bottom + Settings danger zone. Intentional — platform convention. Both call `AuthService.shared.logout()`; no state-sync issue.
- **`ProfileView` also has its own Sign out button in its "Account" section** (confirmed at `ProfileView.swift:44` `.confirmationDialog`). Now three sign-out surfaces exist. Acceptable for v1 but flag in code review — might consolidate later.
- **support email address** (`support@xomware.com`) is a guess. Mitigation: confirm with Dom before merge — flagged in Open Questions.

---

## Open Questions

- [ ] **Support email address**: confirm `support@xomware.com` vs. `dominickj.giordano@gmail.com` vs. a new `support@xomify.xomware.com`. Default if no answer before PR: `support@xomware.com`.
- [ ] **Legal URLs**: confirm `https://xomify.xomware.com/privacy` and `/terms` exist on the live frontend. If not, pick placeholder URLs and file a follow-up issue to add the pages in `xomify-frontend`. Default: use the URLs above even if they currently 404 — cheaper than hard-coding a placeholder we'd need to ripout later.
- [ ] **Ratings row tap behavior**: accept "open in Spotify via `spotify:track:`" as v1, or invest in an in-app track detail screen now? Default: Spotify-open. If Dom wants in-app, add a separate plan — it's a full new screen with playback / share / re-rate actions.
- [ ] **`ProfileView` nested `NavigationStack` (also has one)**: refactor it to the same split-body pattern to avoid the same back-nav glitch? Default: **yes**, include in step 2. If smoke test passes before the refactor, skip — but the consistent approach is safer.
- [ ] **Ratings sort tiebreak**: for two ratings with identical `updatedAt`, sort by `trackName` ascending or leave undefined? Default: `trackName` ascending. Cheap to implement, predictable UX.

---

## Skills / Agents to Use

- **ios-engineer agent**: primary implementer. Respect MVVM, `@Observable`, `@MainActor`, async/await, no force unwrapping. Views stay lightweight; data flow lives in `RatingsHistoryViewModel`.
- **ios-standards skill**: invoke during steps 4–7 to validate modern SwiftUI patterns (`Toggle` + `@AppStorage`, segmented `Picker`, `confirmationDialog`, `Link`, swipe actions).
- **code-reviewer agent**: single mandatory review pass pre-merge. Focus on (a) the split-body refactor didn't break other call sites of `TopItemsView` / `WrappedView` / `FollowingView`, (b) `@AppStorage` keys follow the `xomify.notifications.*` namespace, (c) no force unwraps, (d) every destructive button has a `confirmationDialog`, (e) accessibility labels on toggles / stars / destructive buttons.
- **test-writer agent**: not required — project has no XCTest target per `.claude/CLAUDE.md` (`test_commands: echo "no tests configured"`). If an XCTest target exists by the time this ships, add a minimal `RatingsHistoryViewModelTests` covering load-success / load-error / optimistic-delete-rollback.
