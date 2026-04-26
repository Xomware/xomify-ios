# Plan: Profile Likes Tab

**Status**: Done
**Created**: 2026-04-26
**Last updated**: 2026-04-26

> **Coordination note**: Dom has a backend agent running in another session. This feature is **iOS-only** and uses the existing Spotify Web API endpoint `GET /me/tracks` already wired through `SpotifyService`. **No backend changes required** — do not coordinate with the backend agent.

## Summary
Add a dedicated **Likes** tab to `ProfileView` that shows the signed-in user's full Spotify saved-tracks library (count + paginated list at 50 per page). Split the existing `.recent` tab so it only shows recently-played tracks; the "liked" half migrates into the new tab. Self-only — Spotify's `/me/tracks` is scoped to the authenticated user.

## Approach
- Reuse the existing `SpotifyService.getSavedTracks` plumbing — extend it to expose `offset` and the response's `total` for pagination + count.
- Follow the established Profile-tab pattern: enum case in `ProfileTab`, lazy child VM on `UserProfileViewModel`, dedicated `ProfileLikesTab` view that mirrors the `ProfileRecentTab` row layout (`TrackActionsMenu`, `xomifyCard` rows, `AsyncImage` album art).
- Recommend **hiding** the Likes tab on friend (`.other`) profiles via `visibleTabs`, matching how `.recent` is already hidden today. Keeps the picker compact and avoids a dead-end "private to you" empty state.

No prior `BRAINSTORM.md` / `RESEARCH.md` for this feature — approach derived directly from the existing Recent tab implementation.

## Affected Files / Components
| File / Component | Change | Why |
|-----------------|--------|-----|
| `Xomify-iOS/ViewModels/UserProfileViewModel.swift` (lines 4–35, 94–99) | Add `case likes` to `ProfileTab`, add `title` (`"Likes"`) + `systemImage` (`"heart.fill"`); insert `.likes` into `visibleTabs` for `.me` only (suggested order: `[.shares, .ratings, .taste, .playlists, .recent, .likes]`). Add lazy `_likesVM` + `likesViewModel()` accessor. | Wires the new tab into the picker and the lazy-init pattern other tabs use. |
| `Xomify-iOS/Services/SpotifyService.swift:191` | Change signature to `getSavedTracks(limit: Int = 50, offset: Int = 0) async throws -> SavedTracksResponse` (return the full response so callers see `total`). Update `SpotifyRecentProviding` and any other call sites. | VM needs `total` for the count chip and `offset` for pagination. `SavedTracksResponse` already decodes all three fields (`Models/SpotifyModels.swift:211`). |
| `Xomify-iOS/ViewModels/Profile/ProfileRecentViewModel.swift` | Drop `likedTracks`, `likedError`, `fetchLiked`, and the `getSavedTracks` requirement on `SpotifyRecentProviding`. Rename doc comment to drop "liked" framing. | Likes moves to its own VM; Recent stays single-purpose. |
| `Xomify-iOS/ViewModels/Profile/ProfileRecentViewModel.swift` (protocol) | Remove `getSavedTracks` from `SpotifyRecentProviding`. | Protocol should only expose what Recent needs. |
| `Xomify-iOS/Views/Profile/Tabs/ProfileRecentTab.swift` | Remove the "Liked songs" `section(...)` block (lines ~24–30). Keep only the "Recently played" section. | Recent tab becomes recently-played-only. |
| `Xomify-iOS/ViewModels/Profile/ProfileLikesViewModel.swift` (new) | `@Observable @MainActor` VM owning `tracks: [SpotifyTrack]`, `total: Int?`, `offset: Int`, `isLoading`, `isLoadingMore`, `errorMessage`, `hasMore: Bool`. Methods: `loadIfNeeded()`, `refresh()`, `loadMore()`. Page size 50. Re-entrant safe like `ProfileRecentViewModel`. Define `SpotifyLikesProviding` protocol exposing `getSavedTracks(limit:offset:)` and conform `SpotifyService`. | New tab's data layer with infinite-scroll pagination. |
| `Xomify-iOS/Views/Profile/Tabs/ProfileLikesTab.swift` (new) | SwiftUI view: header row with title + count chip showing `viewModel.total` (formatted with `NumberFormatter` localized grouping), `LazyVStack` of `trackRow(...)` cells (mirror layout from `ProfileRecentTab`), `TrackActionsMenu` per row, sentinel-row `.onAppear` triggers `loadMore()` when within ~5 of the end, `XomifyLoaderSpin` for initial load, footer spinner for pagination, error + empty states. `.task { await viewModel.loadIfNeeded() }`, `.refreshable { await viewModel.refresh() }`. | The view itself. |
| `Xomify-iOS/Views/Profile/ProfileView.swift` (or wherever the tab switch lives) | Add `case .likes:` branch instantiating `ProfileLikesTab(viewModel: vm.likesViewModel())`. | Hooks the new view into the tab fan-out. |
| `Xomify-iOS/Views/Profile/ProfileTabPicker.swift` | No code change required — picker iterates `tabs` from `visibleTabs`, so adding `.likes` auto-renders a pill. | Confirms zero work in the picker. |
| `Xomify-iOS/XomifyTests/...` (new) | `ProfileLikesViewModelTests` covering: initial load populates `tracks` + `total`, `loadMore` appends and increments `offset`, `hasMore` flips false when `tracks.count >= total`, error path sets `errorMessage` and leaves `tracks` empty, re-entrancy guard. | Match the test discipline from the recently added VM tests in this branch. |

## Implementation Steps
- [x] Step 1 — Confirm `user-library-read` scope is in the Spotify auth scope string (search `AuthService` / `SpotifyAuthService` for the scope list). It's already documented in the `getSavedTracks` doc comment, but verify it's actually requested. If missing, add it and note the user will need to re-auth.
- [x] Step 2 — Refactor `SpotifyService.getSavedTracks` to `getSavedTracks(limit: Int = 50, offset: Int = 0) async throws -> SavedTracksResponse`. Update the existing call site in `ProfileRecentViewModel.fetchLiked` (about to be deleted anyway, but unblock compile in between commits).
- [x] Step 3 — Add `case likes` to `ProfileTab` enum, with `title = "Likes"` and `systemImage = "heart.fill"`. Update `visibleTabs` for `.me` to `[.shares, .ratings, .taste, .playlists, .recent, .likes]`; leave `.other` unchanged.
- [x] Step 4 — Create `Xomify-iOS/ViewModels/Profile/ProfileLikesViewModel.swift` with the `SpotifyLikesProviding` protocol and `SpotifyService` conformance. Page size 50. `loadMore` no-ops if `isLoadingMore || !hasMore`.
- [x] Step 5 — Add lazy `_likesVM: ProfileLikesViewModel?` field + `likesViewModel()` accessor on `UserProfileViewModel` (mirror `ratingsViewModel()` pattern at line 115).
- [x] Step 6 — Create `Xomify-iOS/Views/Profile/Tabs/ProfileLikesTab.swift`. Reuse the row visuals from `ProfileRecentTab` (extract a `TrackListRow` helper if it shrinks duplication meaningfully — otherwise inline is fine for v1). Use `LazyVStack` so off-screen rows aren't measured.
- [x] Step 7 — Wire the new `case .likes` branch in the tab fan-out (the switch that currently maps tabs to views inside `ProfileView`).
- [x] Step 8 — Trim `ProfileRecentViewModel`: drop `likedTracks`, `likedError`, `fetchLiked()`, and `getSavedTracks` from `SpotifyRecentProviding`. Update the doc comment.
- [x] Step 9 — Trim `ProfileRecentTab`: remove the "Liked songs" section call. Verify the view renders cleanly with only "Recently played".
- [x] Step 10 — Add `ProfileLikesViewModelTests` (mock `SpotifyLikesProviding` returning canned `SavedTracksResponse` pages). Update existing `ProfileRecentViewModel` tests if they reference `likedTracks`.
- [x] Step 11 — Build: `xcodebuild -scheme Xomify-iOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`. Resolve any strict-concurrency warnings (per `.claude/rules/ios.md`).
- [ ] Step 12 — Manual QA on simulator: open own profile → Likes tab loads, count matches Spotify app, scroll to bottom triggers next page, pull-to-refresh resets, errors display gracefully. Open a friend's profile → Likes tab is absent. Recent tab no longer shows liked songs.

## Web app parity — out of scope for this plan
Mirror this work in the Xomify web repo as a sibling feature. Intentionally **not** included here — track separately so the iOS plan stays atomic.

What the web side will need:
- New "Likes" tab on the user profile page (matches the iOS tab order).
- Reuse the existing `/me/tracks` proxy/call (whatever the web app uses today for the saved-tracks half of its Recent tab) and surface the response `total` for the count badge.
- Paginated list (infinite scroll or "Load more" button — match existing web patterns).
- Trim the web Recent tab to recently-played-only, same as iOS.
- Hide the tab on friend profiles.

**Action**: open a sibling plan in the Xomify web repo (`docs/features/profile-likes-tab/PLAN.md` there) once this iOS plan is in flight. Do not block iOS shipping on web.

## Out of Scope
- Web app changes (tracked separately, see section above).
- Backend changes — Spotify is called direct from iOS; nothing to proxy.
- Changing rating / comment / share behavior on saved tracks.
- "Unlike" / remove-from-library affordance (read-only v1).
- Sorting / filtering (date-added desc only — Spotify default).
- Caching saved tracks locally between app launches.

## Risks / Tradeoffs
- **Spotify rate limits on paginated calls**: `/me/tracks` isn't aggressively rate-limited, and 50/page keeps request count low even for large libraries. Accepted.
- **Large libraries (10k+ liked tracks)**: infinite scroll loads on demand — never load the whole library up front. Memory grows linearly with scroll depth; acceptable for v1. If it becomes a problem, add a virtualized list or a hard cap with a "showing first N of total" footer.
- **`user-library-read` scope**: doc comment claims it's required and presumably already requested. Step 1 verifies. If it isn't in the current scope string, **users must re-auth** — flag this in the PR description and consider a one-time silent re-auth prompt.
- **Spotify `total` is `Int?`**: model already makes it optional. Count chip should hide gracefully when `total == nil`.
- **Refactoring `getSavedTracks` signature**: breaks `ProfileRecentViewModel` until Step 8 lands. Steps are ordered so the build only breaks within a single commit window — keep the refactor + Recent trim in adjacent commits or one commit.
- **Row UI duplication with Recent tab**: tolerated for v1 (small surface). If a third tab needs the same row, extract `TrackListRow` then.

## Open Questions
- [ ] Tab ordering: confirm `.likes` goes after `.recent` (proposed) vs grouped near `.taste`. Default to after `.recent`.
- [ ] Count chip placement: inline next to "Likes" header inside the tab body (matches `ProfileRecentTab` section header pattern), **or** badge on the picker pill itself? Picker pill currently shows icon-only — adding a count would be a picker-wide change. **Recommend** in-body header chip for v1.
- [ ] Pagination trigger threshold: load next page when the user is within N rows of the end. Default N=5; revisit after manual QA.
- [ ] Should pull-to-refresh reset `offset` to 0 and refetch page 1 (discarding loaded pages), or refetch the entire current scroll depth? **Recommend** reset-to-page-1 for simplicity.

## Skills / Agents to Use
- **ios-standards skill**: enforce `@Observable`, `foregroundStyle()`, `clipShape(.rect(...))`, `NavigationStack`, async/await, no force unwraps, accessibility labels and 44pt touch targets per `.claude/rules/ios.md`.
- **swift-test agent (if defined)**: scaffold `ProfileLikesViewModelTests` mirroring the test style of the recently added VM tests in this branch (`AICoachViewModelTests`, `ProfileViewModelTests`).
