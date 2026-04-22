# Xomify Feed Feed — Brainstorm

**Date**: 2026-04-17
**Owner**: Dominick
**Status**: Decided — ready for `/plan`
**Related repos**: `xomify-ios`, `xomify-backend`, `xomify-frontend`

---

## DECISIONS (2026-04-17)

User answered the three open questions and overrode the staged recommendation:

1. **Share atom**: **track + optional caption + optional tags** (mood/genre). Both caption and tags are in scope.
2. **Fan-out**: **fan-out-on-read**. Rationale: built for 5 friends now but must scale to "a real social feed of all your friends, filterable by groups you create." Read-time fan-out handles both — the friend-list-to-query grows naturally, and group filters are trivially expressible as "intersect fan-out source with group members." Write-time fan-out would make group filters painful and require N writes per post.
3. **Audience**: Dogfood with 5 friends, but built to support real social-feed usage with group filters. No MVP staging.

**Scope override**: "Full throttle, don't stage it out — build the whole thing." Supersedes the "Option 1 first, Option 2 later" recommendation.

### Final feature set to plan

Union of Option 1 + Option 2 + Groups-as-filter-layer:

- **Shares feed** (Option 1 foundation): `shares` table, fan-out-on-read, create/delete/feed/user-shares lambdas.
- **Signal loop** (Option 2): `share_interactions` table (queue-add + rating tracked per viewer), sharer profile shows who-queued-who-rated, APNs push + daily digest cron, "queued by N friends" chip on feed items.
- **Groups as feed filters** (not deferred): reuse existing groups backend. Feed tab has filter chips — "All friends" / "Group: X" / "Group: Y". `groups_list` → filter chips. `groups_info` members → intersect with fan-out source. Groups UI also gets a management surface (create group, add/remove members) since filters presume groups exist. **Groups are not shared queues in this product** — they're friend subsets. Existing `groups_add_song`/`groups_song_status` lambdas stay in the backend but do not get iOS UI. (Revisit if we decide groups should also carry their own shared queue later.)
- **Share atom**: `{trackUri, sharedBy, sharedAt, caption?, moodTag?, genreTags?}`. Caption ≤ 140 chars. `moodTag` single enum (hype / chill / sad / party / focus / discovery). `genreTags` array of strings, ≤ 3.
- **Interactions per feed item**: Add to Spotify queue (primary), rate 1–5 (reuses `ratings_track`), see who-else-queued-or-rated.
- **Notifications**: APNs device token registration, per-sharer push when ≥3 friends queue their share, daily digest push at user-chosen time.
- **Naming**: the social tab is labeled `Feed`, not `Social`.
- **Navigation model**: X/Twitter-style. Persistent header with avatar top-left (opens side drawer), "Xomify" wordmark centered, search top-right. Bottom tab bar holds the 4 daily-use flows; the drawer holds everything else and scales with new features. The Feed screen uses horizontal filter chips under the header (like X's "For you / Following / [list]" pattern) for group filtering. Floating action button bottom-right on Feed = compose-a-share.

**Bottom tabs (4)**: `Home` · `Feed` · `Releases` · `Builder`

**Drawer contents**:
- Header: avatar + display name + @handle + friends/groups counts
- Main list: Profile, Stats (Top Items + Wrapped, sub-nav on entry), Following (artists), Friends (requests/pending/list), Groups (create/manage — these are Feed filter sources), Ratings history
- Divider
- Footer: Settings, Help/About, Sign out

**Feed screen layout**:
- Persistent header
- Horizontal filter chips row: `All Friends` · `Group: [name]` · `Group: [name]` · `+`
- Feed cards (track art, sharer, caption, mood/genre tags, timestamp, actions: queue / rate / "queued by N friends" chip)
- Pull-to-refresh
- FAB bottom-right: `+` → share composer (track picker + caption + mood + tags)

- **Pre-plan cleanup** (still blocking): delete stray `Xomfit/` tree from repo.

### Out of scope (explicit)

- Stories / ephemeral 24h shares (can add later; additive).
- Friend-of-friend discovery / public profiles.
- Reply-with-a-song threading.
- Groups-as-shared-queue UI (backend lambdas remain, UI not built).
- Album-level or playlist-level shares (track-only for v1).

---

---

## Premise check

The user has already ruled in Option B (global friends feed) over Option A (group chat). That's the correct instinct:

- Spotify Collaborative Playlists already occupy the "shared queue of songs with friends" space. Groups-as-shared-queue is a commodity feature — better-executed competitors exist inside Spotify itself.
- A "what are my friends into right now" feed is the genuinely differentiated thing. No one does it well. BeReal-for-music is a real unoccupied niche.
- The existing Groups backend doesn't need to be thrown away — it just isn't the *home tab*. It becomes a curation/playlist layer later (or gets deprecated if it doesn't earn its keep post-launch).

What I want to challenge before we go further:

1. **Is a feed actually the right primitive, or is a profile?** A "feed" presupposes volume and recency. If each user shares 1–2 tracks/week, the feed will feel empty. A friend-profile-centric model ("go see what Dom's been into this month") might be more honest about share volume. The feed can still exist, but it may want to be a timeline of *rating + share events* rather than just shares, to have enough signal.
2. **Does Option B actually obsolete Option A, or are they compatible?** They're compatible. Shares are the social substrate. Groups are an opt-in curation layer where a subset of friends curate a shared queue. Different job-to-be-done. Don't ship them simultaneously though — feed first.
3. **Critical-mass problem is real.** A social feed with 0 friends is a dead screen. Invite flow and cold-start content (friends' recent ratings auto-surfaced as "implicit shares"?) are not nice-to-haves, they gate whether this is usable at launch.

---

## Phase 1 — Explore (loose list)

**Content model ideas**
- Share = `{trackUri, sharedBy, sharedAt}` — minimal
- Share = above + optional caption (140 chars)
- Share = above + mood tag (single enum: hype / chill / sad / party / focus / etc.)
- Share = above + "context" (listening to this right now / throwback / new discovery / just rated 5 stars)
- Implicit shares — auto-surface when a friend rates a track ≥ 4 stars
- Implicit shares — auto-surface a friend's top track of the week from their listening history
- Story-style shares that expire in 24h (BeReal-like ephemerality)
- Persistent "pinned current obsession" — one slot per user, overwrites prior
- Album shares, not just tracks
- Playlist shares (link to an existing Spotify playlist)

**How shares get created**
- Big "+ Share" button on a new Feed tab
- Long-press on any track anywhere in the app → "Share to friends"
- Hook into iOS share sheet from Spotify (URL → xomify handles)
- Auto-prompt after rating a track 5 stars ("share this with friends?")
- Daily prompt at a fixed time ("what are you listening to?") à la BeReal
- Auto-share your top-played track of the day (opt-in)

**Feed shape**
- Strict reverse-chronological
- Chronological but collapsed by track ("3 friends shared this today")
- Grouped by friend (horizontal rails per person, latest 5 shares)
- Algorithmic (recency decay × friend affinity × novelty)
- Two tabs: "Recent" (chrono) and "Popular" (most-queued by your friend group this week)
- Stories strip on top (24h ephemeral) + persistent feed below

**Interactions per feed item**
- Add to Spotify queue (primary action)
- Rate 1–5 (reuses existing ratings)
- React with emoji (🔥 ❤️ 🎧 💀)
- Reply with your own song share ("if you liked this, try this")
- See roster of friends who already queued/rated this share
- Save to a personal "stash" playlist
- Mark "already knew this" / "already own it"

**Notifications**
- Push on every new share (too noisy)
- Daily digest ("5 new shares from your friends today")
- Push only when ≥3 of your friends share in the same session
- Push when someone queues/rates your share (sharer-side social reward)
- Weekly "your top shared track" recap

**Discovery beyond direct friends**
- Strictly friends-only (MVP)
- Friend-of-friend, opt-in ("see what friends of friends are sharing")
- Public profiles (anyone can follow — Twitter model, later)

**Ratings ↔ Shares integration**
- Reuse `ratings_track` as-is; a share is orthogonal
- A share auto-publishes the sharer's rating alongside it
- Rating a shared track shows up back on the sharer's share as a social signal
- "This week's top-rated shares from your friends" digest

**Backend shape options**
- **A. Pure shares_ table** (fan-out on read). PK=userEmail, SK=timestamp#shareId. Feed query = parallel query per friend, merge-sort client or server-side. Cheap writes, slightly more expensive reads.
- **B. Pure inbox_ table** (fan-out on write). On share creation, write one row per friend's inbox. Feed query = single `Query(PK=myEmail)`. Expensive writes (×N friends), cheap reads. Classic Twitter timeline.
- **C. Hybrid** — shares table as source of truth + small inbox table for hot recent feed (last 7 days). Complex for MVP.
- **D. Repurpose groups** — auto-create implicit "friends" group per user. Rejected up front; couples unrelated concepts.
- GSI on `shares` by `trackId` to support "who else shared/queued this track"

**Abuse/privacy**
- Rate limit: N shares per user per day (10? 20?)
- Block/mute a friend without unfriending
- Hide your own feed from specific friends
- Report share (inappropriate / spam)

**Empty / cold-start states**
- "Invite a friend" hero card
- "See trending across all Xomify users" (opt-in, public pool)
- Seed feed with the user's *own* recent top tracks as placeholder cards
- Pre-populate with releases from followed artists (bridges to existing Release Radar feature)

**Parallel cleanup**
- Delete stray `Xomfit/` folder from this repo (fitness app bleed-in, unrelated)
- Repo is `xomify-ios`; `Xomfit/` tree shouldn't exist here at all
- Finalize existing tab structure before adding a Feed tab (current: Home / Top / Releases / Wrapped / Builder — adding Feed makes 6, which is the iOS tab bar limit; consider demoting something to Profile submenu)

---

## Phase 2 — Converge

### Option 1: Lean Feed MVP

**What**: Ship a minimum-viable shares feed. One share type (track + optional 140-char caption). Reverse-chrono. Queue + rate per item. No reactions, no notifications, no stories.

**How it works**:
- New `shares` DynamoDB table: PK=`email`, SK=`timestamp#shareId`, attrs include denormalized track metadata (name, artist, album art, trackUri), caption, createdAt.
- New lambdas: `shares_create` (POST), `shares_feed` (GET — fan-out-on-read across user's accepted friends), `shares_delete` (DELETE), `shares_user` (GET one user's shares for profile views).
- GSI on `trackId` for "who else shared this track."
- iOS: new `Feed` tab (demote one existing tab to Profile submenu). Feed view with pull-to-refresh. Long-press on any track anywhere in the app shows "Share to friends" sheet. Rating a track prompts "share this?" with a single tap.
- Queue-add reuses existing Spotify queue API client-side; no backend state change on queue (skip the "who queued" signal for MVP).
- Rating reuses existing `ratings_track` endpoint. Share item shows sharer's rating inline if present.
- Empty state: "Invite a friend" CTA + shows user's own recent top tracks as placeholder "you might share these."

**Pros**:
- Shippable in 2–3 weeks
- Clean backend separation of concerns
- Reuses friends graph and ratings entirely
- Easy to iterate on — adds (reactions, notifications, stories) layer on top cleanly

**Cons / Risks**:
- Fan-out-on-read won't scale past ~200 friends per user (fine for MVP, not for launch growth)
- No notifications = no retention loop
- Cold start problem not really solved — if user has 2 friends and they don't share, feed is dead
- 140-char caption is a UX call that might be wrong; pure tracks might feel more honest

**Best if**: You want to validate whether the core loop (friends share → I queue/rate → repeat) is compelling before investing in social-reward mechanics.

**Scope**: **M** (~2–3 weeks: 4 new lambdas + table + GSI, 1 new tab + 3 views + share sheet + view model on iOS, basic integration tests)

---

### Option 2: Feed + Signal (MVP that retains)

**What**: Option 1 + the sharer-side social signal loop + smart notifications. A share is a dialogue, not a monologue.

**How it works**:
- Everything from Option 1, plus:
- `shares_interaction` lambda + `share_interactions` table: records per-share `{queued, rated}` events by each viewer. PK=shareId, SK=viewerEmail#action.
- Sharer sees on their profile: "Dom rated this 5★" / "Sarah queued your share of Track X."
- Push notifications (APNs):
  - To sharer: "3 friends queued your share of [track]"
  - To feed: daily digest at user-chosen time ("5 new shares from your friends today")
  - No per-share push (too noisy)
- Optional mood tag on share (single enum, 6 options) — cheap to add, improves filter/sort later.
- Feed view gets "Queued by N friends" chip per item, creating a light recommendation signal without algorithmic feed.

**Pros**:
- Sharer gets dopamine → keeps sharing → feed stays populated → viewers come back
- Daily digest solves retention without being spammy
- Mood tag unlocks future filtering without redesign
- "Queued by N friends" surfaces hot tracks organically without a ranking algo

**Cons / Risks**:
- APNs setup adds infrastructure (device token storage, notification lambda, iOS permission flow)
- `share_interactions` table doubles backend writes per user action
- Digest scheduling = cron lambda = more ops surface
- Still not solving true cold-start (no friends = no feed)

**Best if**: You believe retention is the main risk, not core-loop validity. Worth the extra 1–2 weeks if you intend to launch publicly rather than dog-food.

**Scope**: **L** (~4–5 weeks: Option 1 + interactions table + 2 lambdas + APNs plumbing + cron digest + device token handling)

---

### Option 3: Shares-as-Ratings-Timeline

**What**: Don't build "shares" as a net-new primitive. Instead, treat every published rating as an implicit share. The feed is "recent ratings from your friends." Explicit shares are just ratings with optional caption.

**How it works**:
- No new `shares` table. Extend `track_ratings` with `caption`, `visibility` (public/friends/private), `sharedAt` (nullable — present means user opted to publish).
- New lambda: `feed_get` (GET) — fans out across friend list, queries each friend's `ratings_all`, filters to `visibility != private`, sorts by `sharedAt desc`. Reuses `ratings_publish` endpoint entirely.
- "Share" button on any track = rate-and-publish modal. No rating = no share. This forces signal quality.
- iOS: Feed tab shows rating-events timeline. Each item: "Dom rated [track] 5★ · 2h ago · 'banger for the drive'". Queue + react.
- Collapses shares-and-ratings data model — one fewer concept.

**Pros**:
- Zero new tables, minimal new backend surface
- Forces shares to carry signal (a rating) — no empty "check this out" posts
- Leverages existing ratings infrastructure heavily
- Elegant: the feed IS the ratings activity stream

**Cons / Risks**:
- Conflates two things that may want to diverge. "I shared this without rating it" is a real use case (just discovered, haven't decided yet).
- Requires users to rate to share — higher friction may kill share volume
- Rating schema gets `visibility` + `caption` + `sharedAt` which may not fit existing flows cleanly
- The product positioning changes: "rating app with social layer" vs "social app with rating feature." Probably the wrong framing for "BeReal for music."

**Best if**: You value minimal backend surface over product flexibility, OR you believe a rating should be the atomic unit of taste-signaling. This is the "purist engineer" choice.

**Scope**: **S–M** (~1.5–2 weeks: extend ratings table + 1 new feed lambda + iOS feed tab + view model)

---

## Phase 3 — Recommendation

**Go with Option 1 (Lean Feed MVP) with a lightweight plan to layer Option 2 features in immediately after.**

Reasoning:

- **Option 3 is too clever.** Conflating shares with ratings sounds elegant but creates product-positioning drag. The user explicitly wants a "song-sharing social app" — that wording implies shares are a first-class object. Hiding them inside ratings will bite you in v2 when you want to add caption-only shares, album shares, mood-only posts, etc. The tiny backend savings aren't worth the conceptual debt.

- **Option 2 is where you want to be, but not what you should build first.** APNs + interactions + digest cron adds a week or two of infrastructure that's easy to bolt on once Option 1's data model is proven. Shipping Option 2 cold risks over-investing in retention mechanics before you know the core loop works.

- **Option 1 gives you the shippable thing and keeps all of Option 2's doors open.** The `shares` table schema in Option 1 already accommodates a `share_interactions` child table, notification device-tokens, mood tags — none of that requires a rewrite.

**This recommendation depends on one thing**: that Dominick dog-foods this with at least 3–5 friends immediately, and treats the first 2 weeks post-launch as learning-not-growing. If the goal is "launch publicly on the App Store with real marketing," skip to Option 2 — the cold-start/retention risks are too high without notifications.

**On Groups**: defer. Don't ship Groups in this release. Keep the backend lambdas but hide the UI. Revisit after feed MVP has 2 weeks of real usage — groups might naturally emerge as "create a group from a hashtag/mood thread" rather than as an iMessage clone.

**On parallel cleanup**: delete the stray `Xomfit/` folder in this repo before planning. It's polluting file searches and will confuse any agent reading the tree. That's a pre-plan chore, not part of this feature.

**On tab bar**: adding Feed makes 6 tabs, hitting iOS limit. Recommend demoting `Builder` to a button inside `Top` or `Profile`, since Playlist Builder is a destination action, not a browse surface. New tab order: Home / Feed / Top / Releases / Wrapped.

---

## Top 3 open questions to answer before `/plan`

1. **Share atom: track-only, or track + optional caption?** This is the biggest product question. Caption-optional is more expressive but risks Twitter-ification. Track-only is purer but may feel thin. My lean: track + optional 140-char caption + optional mood enum (6 values). Cheap to include, easy to hide in UI if we decide it's noise.

2. **Fan-out-on-read vs fan-out-on-write for the feed.** Read is simpler to build, write scales better. For MVP with ≤50 users each having ≤50 friends, read wins by a mile. But this decision locks in the DynamoDB schema — changing later means a migration. Need a call: am I optimizing for *shipping this month* or *scaling to 10k users*? Recommend: fan-out-on-read now, revisit at 1k DAU.

3. **Is the target audience "Dom's 5 friends" or "a real user base"?** This changes everything about notifications, invite flow, cold-start UX, and whether Option 1 vs Option 2 is right. If it's the former, Option 1 ships and we iterate in public. If it's the latter, we need Option 2 at minimum and probably an invite/referral flow too.

---

## Appendix — Existing backend surfaces we're leaning on

- `friends_list` — returns `accepted` friends list with emails. This is the input to fan-out-on-read.
- `ratings_track` / `ratings_publish` / `ratings_all` — per-track ratings, already denormalize trackName/artistName/albumArt. Reusable as-is inside share cards.
- `authorizer` — JWT authorizer lambda, already wrapping all protected endpoints. New `shares_*` lambdas drop in behind it with no auth work.
- Groups lambdas — left intact, UI hidden. Not deleted.

## Appendix — iOS-side architectural notes

- MVVM constraint (per `.claude/CLAUDE.md`): views don't call `XomifyService` directly. Add `FeedFeedViewModel` and extend `XomifyService` with `getFeed`, `createShare`, `deleteShare`, `getUserShares`.
- Reuse `NetworkService.xomifyGet/Post` patterns — `XomifyService` is already an actor singleton, keep that.
- New models in `Models/XomifyModels.swift`: `Share`, `FeedResponse`, `CreateShareRequest`. Match backend field names camelCase.
- Share sheet: SwiftUI `.sheet` with track context passed in — reuse the `SpotifyTrack` model that already floats around Playlist Builder / Queue Builder.
- Offline: cache last feed response in UserDefaults or a lightweight on-disk JSON blob (follows existing caching constraint). Stale feed beats blank feed.
