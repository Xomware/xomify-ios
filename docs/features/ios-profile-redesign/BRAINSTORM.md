# Brainstorm — iOS Profile Page Redesign

**Topic**: Turn the Profile tab from a settings page into a real social profile (shares, ratings, rotating top tracks/artists) that is also viewable by other users.
**Date**: 2026-04-23
**Status**: Draft

---

## Framing / Premise Check

Current state (from code):

- `ProfileView` + `ProfileViewModel` is basically a settings page. Stats row, three "Top..." links into `TopItemsView`, two enrollment toggles (Wrapped / Release Radar), an account details block, and a logout button. No concept of "what I've shared" or "how I'm perceived".
- `FriendProfileView` + `FriendProfileViewModel` already exists for viewing other users and calls `GET /friends/profile`. It renders a small header, a stats row, and three horizontal scrollers (top artists / songs / genres) driven by the loose `FriendProfile` payload. No shares, no ratings.
- Shares infrastructure is mature: `Share` model is denormalized, `FeedViewModel` paginates with keyset cursors, `ShareCardViewModel` owns per-card queue/rate with optimistic updates. All feed rendering today is global (`getFeed`), not per-user.
- Ratings infrastructure is also mature: `/ratings/all?email=...` works today and already accepts any user's email, not just your own. `RatingsViewModel` uses it.
- Top Items today is **Spotify-only** (via `SpotifyService.getTopTracks/Artists`). For the self profile this is fine. For the other-user profile, top items come from the backend `/friends/profile` payload (loose `[String: JSONValue]`), which is lower fidelity and doesn't include album art.

Key implication: "self view" and "other-user view" need to be conceptually one profile surface but are sourced from **different pipelines** for three of the four content types.

| Content type | Self view source | Other-user view source | Gap |
|---|---|---|---|
| Header / stats | `SpotifyService.getCurrentUser` + counts | `FriendProfile` payload | none |
| Top tracks / artists / genres | `TopItemsViewModel` (Spotify API) | `FriendProfile.topSongs/topArtists/topGenres` (loose JSON) | other-user is thin text tiles; no album art |
| Ratings | `GET /ratings/all?email=me` | `GET /ratings/all?email=them` — already works | iOS does not call it for another user yet |
| Shares | `GET /shares/feed` (social-graph feed — not mine-only) | nothing | **no `getShares(email:)` method in `XomifyService`**. User mentions backend has `/shares/user` — iOS hasn't wired it |

So the single hard backend gap the user called out is real: we need a `shares_by_user` iOS client method (`XomifyService.getSharesByUser(email:)` → paginated list). Everything else can be wired with existing endpoints.

---

## Phase 1 — Explore (wide)

Dumping ideas, not filtering:

- Instagram-style profile: header up top (avatar, handle, follower/following/friend counts, edit/follow button), row of highlight bubbles for "rotating top tracks" and "top artists", then a tabbed feed below (Shares | Ratings | Top).
- Spotify-artist-style profile: big hero with blurred album art from most recent share, stats overlayed, then stacked sections ("Recent Shares", "Top Right Now", "Ratings") — each horizontally scrollable.
- Twitter/X profile clone: pinned share at top, then chronological stream of shares mixed with ratings ("rated 5 stars", "shared a track") as a unified activity feed.
- Grid-first: Instagram-grid of album art tiles, one per share. Tap a tile → share detail card. Top items rotate as a small strip above the grid. Very visual but genre/mood context is weak.
- Tabbed profile: Header + three tabs (Shares / Ratings / Taste). "Taste" holds rotating top tracks/artists/genres. Keeps concerns separate, easier to scale.
- "Now Playing Identity" concept: profile centers on a rotating "what I'm into this week" card (auto-cycling top track → top artist → top genre every few seconds), rest is secondary. Risky — user might hate auto-rotation.
- Collage / mood-board: randomized poster wall of shares + top items + ratings. Cool, high-effort to build.
- Bento grid: iOS-17 bento layout with mixed-size cards — one large "Top Track right now" card, a medium "Recent Share" card, a small "Avg rating given" card. Modern, on-brand for iOS.
- Playlist-disguised-as-profile: show the user's shares as if they were a Spotify playlist (track row list with album art thumbnails). Familiar mental model, very native.
- Time-boxed rotation: cycle "Top This Week" → "Top This Month" → "Top All Time" every few seconds in a single card (honors the user's "rotating" ask literally).
- Carousel rotation: horizontal paged scroll between Top Tracks / Top Artists / Top Genres with page indicator. User-driven, not time-driven.
- Auto-scrolling marquee: album art strip scrolls like a concert marquee. Looks cool, accessibility concerns.
- "Posts" concept: treat each share as a "post" with its own detail view (big album art, caption, mood tag, who queued it, comments if/when added). Reuse `ShareCardViewModel`.
- Rating distribution chart: small bar chart showing how many 1-2-3-4-5 stars they've given. Cheap insight, visually distinct from shares.
- Mood fingerprint: pie / radar chart of mood tags used across their shares. Fun identity signal.
- "Listen-alike" score: on another user's profile, show % genre overlap vs you. Requires comparing both top-genres payloads.
- Activity heatmap: GitHub-style contribution graph of shares per day. Nerdy, probably not worth it.
- "Edit Profile" in self view (bio field, vibe tag) — backend gap, skip unless bio storage exists.
- Share sheet: tap "share profile" → URL deep link. Backend gap.
- Self vs other-user unification: use ONE `ProfileView` that takes a `viewMode: .me | .other(email)` enum. Cleaner than two views.
- Reuse `ShareCardViewModel` inside the profile shares list so queue/rate works identically to feed.
- Pin the "most recent share" as a hero at the top — makes the profile feel alive.
- If no shares yet, show top-track card as the hero so profile isn't empty.
- "Quick actions" row on other-user view: Add friend / Remove friend / Mute (if ever added).
- Settings moves OUT of profile into its own Settings tab (or a gear icon) — the user implicitly wants this by reframing profile as social.
- Keep enrollment toggles on self view only, collapsed into a "Preferences" disclosure row near the bottom.

---

## Phase 2 — Converge: 3 concrete options

### Option 1: Tabbed Profile (Instagram-style header + segmented tabs)

**What**: Fixed header (avatar, display name, stat row, action button) + a segmented `Picker` below the stats that switches between three sub-views: **Shares**, **Ratings**, **Taste**. Same structure for self and other-user — the action button swaps (Edit vs Add Friend).

**How it works**:
- **Shares tab**: Vertical list of the user's `Share`s, each rendered with the existing `ShareCard` using `ShareCardViewModel`. Loads via a new `XomifyService.getSharesByUser(email:before:limit:)` wrapping `/shares/user`. Pagination mirrors `FeedViewModel` (keyset on `sharedAt`). Empty state: "No shares yet — drop your first track." with a deep link to the composer.
- **Ratings tab**: Reuses the existing `RatingsViewModel` but parameterized by email. Grouped by stars descending, like today's Ratings screen. For other-user view, delete is hidden; for self, it's enabled.
- **Taste tab**: Three horizontally paged carousels stacked vertically — Top Tracks, Top Artists, Top Genres. Each carousel has a small term-range `Picker` ("Last 4 weeks" / "6 months" / "All time"). Rotation is **user-driven** via swipe, plus an optional subtle auto-advance every ~6s that pauses on interaction. Self pulls from `TopItemsViewModel` (Spotify API, rich). Other-user pulls from the `FriendProfile` term-map (lower fidelity — tiles, no art).
- Header pinning: when the user scrolls the tab content, the header collapses into a compact form (small avatar + name) using iOS 17 `ScrollView` + `scrollTargetBehavior` so context stays visible.
- Action button: self → "Edit Profile" (no-op for now, or jumps to a Preferences sheet holding enrollment toggles + logout). Other-user → Add Friend / Remove Friend / Pending (driven by the existing `Friend` model fields).

**Pros**:
- Clear information architecture. Each tab has one job.
- Reuses `ShareCardViewModel` and `RatingsViewModel` with near-zero rework.
- Scales: adding a "Groups" tab later or a "Wrapped" tab is trivial.
- Matches the mental model users already have (IG, TikTok, Spotify all use this).
- Tab-level pagination scoping is clean — Shares tab manages its own cursor without clashing with Ratings.

**Cons / Risks**:
- Tabs require an extra tap to see anything beyond the header — feels less "alive" on first load.
- Rotating top items live inside a tab, so the "rotating" vibe isn't the first thing visitors see.
- Segmented `Picker` styling takes work to feel premium; default iOS look is bland.
- Sync/scroll state management across tab switches needs discipline (don't refetch on every switch).

**Best if**: You want clarity, easy testability, and low risk of regressing existing share/rating flows.

---

### Option 2: Bento + Pinned Share Hero (single scrolling surface, no tabs)

**What**: One long scrolling profile surface with a bento-grid vibe. Header on top, then a large pinned "Recent Share" card (the user's most recent share) as the hero, then a rotating "Taste" card that auto-cycles through Top Track / Top Artist / Top Genre (three-page TabView with `PageIndexView`), then a horizontal ratings strip, then a grid of remaining shares.

**How it works**:
- Header: avatar, name, stats row (Shares, Ratings, Friends), action button.
- Hero: most recent share, full-width, big album art, caption, mood tag, rate/queue actions wired to `ShareCardViewModel`. If user has zero shares, fall back to a "Top Track Right Now" card driven by `TopItemsViewModel.shortTermTracks.first`.
- **Taste** card: square-ish card with a paged TabView — page 1 Top Tracks, page 2 Top Artists, page 3 Top Genres. A `Timer` auto-advances pages every 6s; user swipe resets the timer. Term range is a compact `Menu` button in the corner ("4w ▾"). This is where the "rotating" feeling lives.
- Ratings strip: horizontally scrolling row of recent ratings (album art + star count badge). Tap → rating detail or re-rate sheet (self) / read-only (other).
- Remaining shares: 3-column grid of album art tiles below. Tap → share detail sheet.
- Same view for self and other-user; just flip action button and hide self-only affordances (enrollment toggles shown in a "Preferences" sheet triggered by a gear icon, self-only).

**Pros**:
- Feels alive on first scroll — the rotating taste card is front-and-center and matches the user's literal ask.
- Hero share makes the profile feel like a living thing even with sparse content.
- Bento aesthetic is very on-brand for 2026 iOS (Apple's own profiles use this direction).
- Single scroll surface = simpler pagination (only one list, the share grid, has "load more").

**Cons / Risks**:
- Auto-rotation can feel gimmicky and creates accessibility work (must respect Reduce Motion, VoiceOver pausing, touch-to-pause).
- Grid of album art for shares drops caption / mood context — might undersell the social nature of a share.
- More custom layout code. Higher initial build cost than tabs.
- "Ratings strip" horizontal scroll can get lost between two other horizontal-ish elements — visual rhythm risk.
- Pagination for the grid is fine but mixing that with a hero share means the top of the view is "static" and only the bottom paginates — minor awkwardness.

**Best if**: The feature is primarily an identity / vibe statement and the user values visual polish over information density.

---

### Option 3: Unified Activity Stream (Twitter-style)

**What**: Header + a single chronological stream below that interleaves shares and ratings as "activity" items. Top items live in a compact strip between header and stream, swiped manually.

**How it works**:
- Header: avatar, name, bio-ish line (e.g. "Rated 42 tracks · 18 shares · 5-star avg 3.8"), stats row, action button.
- "Top Strip": single horizontally paged row between header and stream with three pages — Top Track, Top Artist, Top Genre. No auto-rotation; user swipes. Tiny page dots. Self pulls rich data with album art, other-user falls back to text tiles.
- Activity stream: a unified `[ActivityItem]` where each item is either `.share(Share)` or `.rating(TrackRating)`. Sorted by `sharedAt` / `createdAt`. Share items render as full cards (reuse `ShareCardViewModel`). Rating items render as a condensed row: "Rated ★★★★☆ — Track - Artist".
- Pagination: merge-sort two paginated streams. For v1, take the first N shares and first M ratings, sort in-memory, and paginate naively. Cursor complexity only matters if a user has hundreds of both.

**Pros**:
- Most "social" feel — ratings and shares interleave, so the profile tells a temporal story.
- Reuses `ShareCardViewModel` unchanged.
- Empty state is less of an issue — a first rating populates the stream without needing a share.

**Cons / Risks**:
- Merge-sorting two paginated endpoints is fiddly. Ratings endpoint (`/ratings/all`) returns the full list today (no pagination), which is OK-ish until someone has 500 ratings.
- Top strip competes for attention with the stream right below it — visual hierarchy muddled.
- Rating-as-activity-item is a new UI pattern in the app — needs a dedicated row component.
- Loses the "destination" feel: scrolling past the top strip means the rotating taste is gone from view.

**Best if**: You'd rather optimize for "this user is active" signal than for discovering their taste.

---

## Phase 3 — Recommendation

**Recommend Option 1: Tabbed Profile.**

Reasoning:

1. **Reuse dominates.** Option 1 is the only option where every existing view model (`ShareCardViewModel`, `RatingsViewModel`, `TopItemsViewModel`, `FriendProfileViewModel`) slots in with minimal rework. The only net-new thing is a `getSharesByUser` service method and a small `UserProfileViewModel` that fans out to the right sources based on `.me | .other(email)`.
2. **Self / other-user parity is cleanest in tabs.** Other-user view simply hides self-only affordances per tab (delete rating, edit share, enrollment toggles move to a self-only Preferences sheet). No need to redesign sections conditionally.
3. **The "rotating" ask is best satisfied by user-driven paging**, not auto-rotation. Auto-rotation (Option 2's hero premise) introduces accessibility work and can annoy power users; a paged `TabView` in the Taste tab gives the rotating feel without the tax.
4. **Information density matches the data.** Shares and ratings are content-heavy and belong in their own tab. Bento (Option 2) forces you to truncate both.
5. **Future-proof.** Adding a "Groups" or "Wrapped" tab is one enum case. Options 2 and 3 would need layout reshuffles.

### Biggest tradeoffs vs the runners-up

- **Vs Option 2 (Bento)**: You give up the "wow on first load" hero share. Mitigation: make the Shares tab the default selection so the first thing other users see on your profile is your most recent share at the top of the list.
- **Vs Option 3 (Activity Stream)**: You lose the temporal "this user is alive right now" signal. Mitigation: show a small "last active" line in the header (`"Last share: 3h ago"`).
- **Tabs can feel bureaucratic**. Mitigation: keep the header rich (big avatar, stats row, optional taste preview sliver above the tab bar) so the profile doesn't feel empty before you tap into a tab.

---

## Tradeoffs Summary

| Axis | Option 1 Tabbed | Option 2 Bento | Option 3 Activity |
|---|---|---|---|
| Build cost | Low | High | Medium |
| Reuse of existing VMs | Maximum | High | High |
| "Rotating" top items feel | Good (user-paged) | Strongest (auto) | Weakest |
| First-load wow | Medium | Highest | Medium |
| Self/other parity | Easiest | Medium | Medium |
| Accessibility risk | Low | Medium (auto-scroll) | Low |
| Scales to more content types | Easiest | Hard | Medium |

---

## Backend / Codebase Gaps Honestly Called Out

1. **`shares_by_user` is not wired on iOS.** User said `/shares/user` exists on the backend. `XomifyService` does not have a `getSharesByUser(email:)` method today — every share call is either create/delete/interact on a single share or the global `getFeed`. Need to add this method, plus a `SharesByUserResponse` if the shape differs from `FeedResponse`. (If the shape is identical, `FeedResponse` can be reused.)
2. **Other-user top items are lower fidelity.** `FriendProfile.topSongs/topArtists/topGenres` are `[String: JSONValue]` and rendered as text tiles in today's `FriendProfileView`. Self-view Taste tab will have album art via `TopItemsViewModel`; other-user Taste tab won't, unless the backend starts denormalizing album art into `FriendProfile` or we proxy Spotify lookups per-item (expensive). **Recommendation**: ship v1 with text tiles for other-user Taste; flag as follow-up.
3. **No "shares count" on `FriendProfile`.** Header stats row for other-user view wants a share count. Options: derive from the first page of `getSharesByUser` (`totalCount` if the backend returns it), or live without it and show three counts instead of four. **Backend ask**: include `shareCount` in `FriendProfile` payload.
4. **Ratings for another user.** `/ratings/all?email=them` appears to work already (RatingsViewModel doesn't restrict by viewer), but needs confirmation that the backend isn't auth-gating it to "email == caller". If it is gated, either add a new endpoint or expose a read-only variant.
5. **Settings / Preferences orphaned**. Moving enrollment toggles, account details, and logout out of ProfileView means we need a Settings sheet or Settings tab. **Not a blocker for this feature**, but the decision has to be made before execution. Recommended: gear icon in the self-profile header opens a Settings sheet; no new tab.
6. **`FriendProfileView` becomes redundant**. Once `ProfileView` supports `.other(email)`, the existing `FriendProfileView` should be deleted or reduced to a thin forwarder. Plan the deprecation in the execute step, not a blocker.
7. **Term-range picker for other-user Taste**. The `FriendProfile` payload parsing prefers `mediumTerm` but falls back. If we want to let other-user viewers flip between 4w / 6m / all-time, the backend needs to return all three term buckets consistently. **Flag as backend question**.

---

## Open Questions

- Which tab should be the default on (a) self view and (b) other-user view? Probably Shares for both, but worth confirming.
- Do we want the profile deep-linkable by email / user id for sharing profile URLs? (Affects routing, not v1.)
- Where does the Wrapped / Release Radar entry point go once it leaves the Profile page? Settings? Home? A new "Insights" tab?
- Do we want a subtle "last active" indicator in the header? (Requires a `lastSeenAt` field that may or may not exist on the backend.)
- Should the Taste tab auto-advance pages by default, with a setting to disable? Or require manual swipe only? Leaning manual-only for accessibility.
- Should ratings on the other-user profile be collapsible (grouped by stars, hidden by default) or always expanded? Grouped by stars is already how `RatingsViewModel.grouped` works — reuse that.

---

## Next

Run `/plan ios-profile-redesign` using this doc as context. Plan should cover:

- New `UserProfileViewModel` with `mode: .me | .other(email)`
- New `XomifyService.getSharesByUser(email:before:limit:)`
- Refactor `ProfileView` → `UserProfileView(mode:)` with three tabs
- Migration of settings (enrollment toggles, account, logout) into a separate Settings sheet or tab
- Deprecation plan for `FriendProfileView`
- Empty states for each tab (self and other)
- Accessibility pass for the Taste tab's paged rotation (VoiceOver, Reduce Motion)
