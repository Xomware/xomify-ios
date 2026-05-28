# BRAINSTORM — DMs and Notifications

> Topic: `dms-and-notifications`
> Date: 2026-04-28
> Author: Dom + Claude
> Surface: xomify-ios (SwiftUI), xomify-frontend (Angular 18), xomify-backend (Python/Lambda + DynamoDB + APNS)

---

## Phase 1 — Explore (loose ideas)

### DMs — angles considered
- 1:1 only vs group DMs (Dom's spec is 1:1; group posts already cover N-way)
- Thread-per-pair (deterministic id from sorted user ids) vs server-generated thread id
- Single `xomify-dms` table holding messages, with thread-id partition key
- Two-table split: `xomify-threads` (thread metadata, last-message preview, unread counts) + `xomify-messages` (per-message rows)
- WebSockets via API Gateway WS for live delivery vs simple polling vs APNS-as-transport
- "Share-a-track in DM" = a message with a `kind: track` payload (uri, name, artist, art) — same shape as a share record, just delivered through DM thread
- Read receipts: per-user `lastReadAt` on the thread membership row
- Typing indicators: out of scope for v1, full stop
- Blocking: a `xomify-blocks` table — `(blockerUserId, blockedUserId)` — checked on send. Cheap to add, expensive to retrofit
- Friendship gate: only allow DMs between mutual friends? Or open to anyone you can resolve by handle? Dom's `xomify-friendships` table is the natural gate
- Reactions on messages — out of scope v1
- Editing/deleting messages — soft delete only, v1
- Attachments / images — out of scope. Track shares only
- Pagination: query thread messages by `sk` descending with limit + LastEvaluatedKey
- TTL on messages? Probably not — leave them
- E2E encryption — not happening, JWT-authed transport is fine for a Spotify-companion app

### Notifications — angles considered
- All four triggers funnel through one shared `send_push(userId, payload)` helper that wraps the existing APNS pipeline
- Per-user notification prefs row: `xomify-notif-prefs` or fold into the user profile row as a map (`{dm: true, wrapped: true, releaseRadar: true, groupPost: true}`)
- Trigger sources differ:
  - **DM** → fires inline from the `dms_send` lambda (synchronous post-write)
  - **Group post by friend** → fires from `groups_post_create` lambda; fan-out to group members minus author, filtered by `xomify-friendships` so only friends-of-author get pinged (or just all members — simpler)
  - **Wrapped** → scheduled lambda, runs daily Nov 25–Dec 15, polls each opted-in user's playlists for the year's Wrapped playlist id pattern
  - **Release Radar** → scheduled lambda, runs Mondays (RR refreshes Friday but users open Mon AM); diff playlist track-ids vs last-seen set
- Detecting "new" Wrapped: Spotify's Wrapped playlist appears in user's library with a name pattern `Your [YEAR] Wrapped` or via a known playlist id format. Easiest: scan user's playlists once/day in late Nov/early Dec, look for a playlist with `wrapped` in the name owned by Spotify, store `wrappedPlaylistIdSeen` on profile. First time it's seen → fire notif
- Detecting "new" Release Radar: RR playlist id is stable per user once known (`spotify:playlist:<id>`); store `releaseRadarPlaylistId` + `releaseRadarLastTrackIds` (set hash or just a small array of ids) on profile. Diff weekly. Any new track id = notif
- Deep links: custom scheme `xomify://` already implied. Targets: `xomify://dm/<threadId>`, `xomify://group/<id>/post/<postId>`, `xomify://wrapped`, `xomify://release-radar`
- Notification grouping (APNS `thread-id`): use thread ids per category so iOS stacks them sensibly
- Web push (Angular) — out of scope v1. iOS only for push. Web can show in-app toast/badge if user is online
- Quiet hours / batching — out of scope
- Backoff for failed device tokens — already handled in existing pipeline (assumption; verify in `notifications_register`)
- Storing notif history server-side for an in-app inbox — nice but out of scope; APNS-only delivery is fine
- Wrapped/RR re-fire prevention: store last-fired marker so we don't re-notify if the lambda runs again

### Premise challenges
- **Friend-of-author filter on group posts**: do we want "friends only" or "all group members"? Dom's spec says "by a friend." Stricter filter = fewer notifs but requires a friendship lookup per recipient. All-members is simpler. **Flag for Dom.**
- **Wrapped detection** is fragile — if Spotify changes the naming convention or playlist visibility, the poller breaks. Acceptable risk for an annual event; we monitor in late Nov.
- **Release Radar polling cost**: one Spotify API call per opted-in user per week. Trivial for hundreds of users, watch it at thousands.
- **Do we need a thread-list endpoint that returns unread counts?** Yes for the inbox UI. That pushes us toward the two-table split (threads table holds counts).

---

## Phase 2 — Converge

# Section 1: DMs

## Option A: Single-table, thread-id derived, polling-only

**One-line**: One DynamoDB table holds all messages, thread id is `sorted(uidA)#sorted(uidB)`, clients poll for new messages.

**Schema sketch**:
```
xomify-dms
  PK: THREAD#<threadId>           // threadId = sha1(min(uidA,uidB) + "#" + max(uidA,uidB))
  SK: MSG#<ulid>                  // ulid is time-ordered
  attrs: senderId, body, kind ("text"|"track"), trackPayload?, createdAt, deleted?

  // Thread metadata as a sibling row
  PK: THREAD#<threadId>
  SK: META
  attrs: participants[2], lastMessageAt, lastMessagePreview

  // Per-user thread index (for inbox list + unread)
  PK: USER#<userId>
  SK: THREAD#<lastMessageAt>#<threadId>
  attrs: threadId, otherUserId, lastReadAt, unreadCount
```

**Endpoints**:
- `POST /dms/send` `{ toUserId, kind, body?, trackPayload? }` → writes message + updates META + bumps both USER index rows
- `GET /dms/threads` → query `PK=USER#me, SK begins_with THREAD#` desc, returns inbox
- `GET /dms/threads/:threadId/messages?before=<sk>&limit=50` → paginated
- `POST /dms/threads/:threadId/read` → updates `lastReadAt`, zeros unreadCount

**Real-time vs polling**: **Polling**. Client polls thread list every 15s when app is foreground; opens a thread = polls every 5s. Push notifs cover background delivery. No WebSocket infra needed.

**Share-a-track in DM**: **In scope** — `kind: "track"` payload reuses the existing share record shape so the iOS message bubble and Angular bubble can render a track card.

**Blocking**: **In scope, minimal**. Add `xomify-blocks` table: `PK=USER#<blockerId>, SK=BLOCK#<blockedId>`. `dms_send` does a single GetItem before writing; if blocked either direction → 403. Cheap now, miserable to bolt on later.

**Effort**: **M** (3–5 days). Mostly schema + 4 lambdas + iOS/Angular thread list + chat view.

**Biggest tradeoff vs Option B**: No live "typing now" or sub-second delivery while both users are in-app. Polling at 5s feels fine for Spotify-companion DMs.

---

## Option B: Same schema, API Gateway WebSocket for live delivery

**One-line**: Option A's schema + API Gateway WebSocket connection per active client for instant delivery while both users are in-thread.

**Schema sketch**: Same as A, plus:
```
xomify-ws-connections
  PK: USER#<userId>
  SK: CONN#<connectionId>
  attrs: connectedAt, ttl (1hr)
```

**Endpoints**: A's endpoints + WS routes (`$connect`, `$disconnect`, `$default`). On `dms_send`, lambda also looks up recipient's active connections and posts via `@connections` API.

**Real-time vs polling**: **Hybrid** — WS when foreground, APNS when background, polling as fallback if WS drops.

**Share-a-track in DM**: In scope, same shape as A.

**Blocking**: In scope, same as A.

**Effort**: **L** (7–10 days). API Gateway WS is straightforward but it's a new surface to monitor (connection table cleanup, dropped sockets, retry logic on send).

**Biggest tradeoff vs A**: 2x infra surface for a UX delta most users won't notice. Worth it only if real-time chat is core to retention — and for a Spotify companion, it isn't.

---

## Option C: Minimal-viable, single table, no thread metadata table

**One-line**: Just messages. Inbox is computed by querying GSI on senderId/recipientId. No unread counts server-side — client tracks `lastReadAt` locally.

**Schema sketch**:
```
xomify-dms
  PK: THREAD#<threadId>
  SK: MSG#<ulid>
  attrs: senderId, recipientId, body, kind, trackPayload?, createdAt
  GSI1PK: USER#<recipientId>
  GSI1SK: <createdAt>
```

**Endpoints**: `POST /dms/send`, `GET /dms/threads/:id/messages`, `GET /dms/inbox` (GSI scan of recent messages, group client-side by threadId).

**Real-time vs polling**: Polling only.

**Share-a-track in DM**: In scope.

**Blocking**: Out of scope (skipped to keep "minimal").

**Effort**: **S** (1–2 days).

**Biggest tradeoff vs A**: No unread counts on server, no blocking, no thread previews. Inbox UI is jankier and we'll regret skipping blocks the first time someone harasses someone.

---

# Section 2: Notification triggers

All four use a shared helper: `send_push(userId, payload)` that:
1. Looks up the user's notif prefs (fold into `xomify-users` row as `notifPrefs` map: `{dm, wrapped, releaseRadar, groupPost}`, default all true)
2. Looks up active device tokens from `xomify-devices` (or whatever the existing register/unregister tables are named)
3. Calls APNS via the existing pipeline

### Trigger 1: New DM
- **Fires from**: `dms_send` lambda, after successful message write, before returning 200
- **Event**: New row written to `xomify-dms` with `SK begins_with MSG#`
- **Opt-in/opt-out**: Yes — `notifPrefs.dm` (default on)
- **Deep link**: `xomify://dm/<threadId>`
- **Payload**:
  ```
  alert.title: "<senderDisplayName>"
  alert.body: <message preview, truncated 80 chars; "Sent you a track" if kind=track>
  thread-id: "dm-<threadId>"   // APNS grouping
  data.type: "dm"
  data.threadId: <threadId>
  ```
- **Notes**: Skip push if recipient has an active WS connection (Option B only) — message already delivered live.

### Trigger 2: Spotify Wrapped release
- **Fires from**: Scheduled lambda `wrapped_poller`, EventBridge rule running once daily Nov 25 – Dec 15 (UTC noon)
- **Event**: First time we detect a Wrapped playlist for a user that we haven't seen before
- **Detection**:
  - For each opted-in user, hit `GET /me/playlists` (or specifically search owned-by-spotify playlists in their library) using their Spotify access token
  - Look for a playlist whose name matches `Your [YEAR] Wrapped` (or owner is Spotify and name contains "Wrapped" + current year)
  - Store `wrappedPlaylistIdSeen.<year>` on `xomify-users` row
  - If the playlist exists and the marker doesn't → fire push, then write the marker
- **Opt-in/opt-out**: Yes — `notifPrefs.wrapped` (default on)
- **Deep link**: `xomify://wrapped` (in-app screen) with payload also carrying `spotifyPlaylistUri` so the screen can offer "Open in Spotify" button
- **Payload**:
  ```
  alert.title: "Your [YEAR] Wrapped is here"
  alert.body: "Tap to see your top tracks and artists."
  data.type: "wrapped"
  data.year: 2026
  data.spotifyPlaylistUri: "spotify:playlist:<id>"
  data.spotifyPlaylistUrl: "https://open.spotify.com/playlist/<id>"
  ```
- **Notes**: We need a fresh Spotify access token per user. If the refresh token is expired/revoked, skip silently. Re-firing prevention = the year-keyed marker.

### Trigger 3: Release Radar release
- **Fires from**: Scheduled lambda `release_radar_poller`, EventBridge rule running every Monday 10:00 user-local-ish (in practice: run hourly, only fire if user's local time is between 9am–11am Mon — or just run once at 14:00 UTC Mon and accept the timing isn't perfect)
- **Event**: User's Release Radar playlist has new track ids vs last-seen set
- **Detection**:
  - Resolve user's Release Radar playlist id once (search `/me/playlists` for owner=spotify, name="Release Radar"), cache on profile as `releaseRadarPlaylistId`
  - Pull current track ids (top 30 should be enough — RR caps at 30)
  - Compare against `releaseRadarLastTrackIds` (array of ~30 strings on profile row)
  - If symmetric difference is non-empty → new releases exist → fire push, store the new list
  - First-ever run for a user → just store the list, no notif
- **Opt-in/opt-out**: Yes — `notifPrefs.releaseRadar` (default on)
- **Deep link**: `xomify://release-radar` with `spotifyPlaylistUri` in payload
- **Payload**:
  ```
  alert.title: "New Release Radar"
  alert.body: "<N> new tracks for you this week."
  data.type: "releaseRadar"
  data.spotifyPlaylistUri: "spotify:playlist:<id>"
  data.spotifyPlaylistUrl: "https://open.spotify.com/playlist/<id>"
  data.newTrackCount: <N>
  ```
- **Notes**: Same access-token concern as Wrapped. Polling cost: 1 Spotify call per opted-in user per week — fine.

### Trigger 4: New post in a group by a friend
- **Fires from**: `groups_post_create` lambda, after the post write
- **Event**: New post row in `xomify-groups` (or wherever group posts live)
- **Detection / fan-out**:
  - Query group membership for groupId
  - For each member ≠ author, check if they're friends with the author (`xomify-friendships` GetItem) — **if Dom wants strict "by a friend" filter** — OR skip the friendship check and notify all members (simpler, matches "Slack channel" mental model)
  - Send push to remaining members
- **Opt-in/opt-out**: Yes — `notifPrefs.groupPost` (default on). Per-group mute is out of scope v1
- **Deep link**: `xomify://group/<groupId>/post/<postId>`
- **Payload**:
  ```
  alert.title: "<groupName>"
  alert.body: "<authorDisplayName>: <post preview 80 chars>"
  thread-id: "group-<groupId>"
  data.type: "groupPost"
  data.groupId: <groupId>
  data.postId: <postId>
  ```
- **Notes**: The friendship-filter question is a real fork in the spec. See open questions.

---

# Section 3: Recommendation

**DMs: Option A (single-table-ish with thread metadata + per-user index, polling, blocking in scope, share-a-track in scope).**

It hits the spec, gives us unread counts and a real inbox, and includes blocking — which is a 1-hour add now and a refactor later. Option C saves a couple of days but ships without blocks and without server-side unread counts, which we'll immediately want once the iOS inbox UI renders. Option B's WebSocket layer is a cool toy but Spotify-companion DMs don't need sub-second delivery; APNS + 5s polling while a thread is open is indistinguishable in practice and skips a whole infra surface.

**Notifications: shared `send_push(userId, payload)` helper + the four triggers as specified above, prefs folded into the existing `xomify-users` row as a `notifPrefs` map.**

Two of the four triggers (DM, group post) are inline lambda fires — basically free given the existing APNS pipeline. The other two (Wrapped, Release Radar) are scheduled pollers with simple "have we seen this before" markers on the user profile row. No new infra primitives, no fan-out queue, no notification history table. We can add an in-app inbox later if we want, but APNS-only is correct for v1.

This depends on:
- The existing `notifications_register` lambda actually storing device tokens in a way we can query by `userId` (need to verify the table shape — listed in open questions)
- Spotify refresh tokens being available server-side per user (needed for Wrapped + RR pollers to call Spotify on the user's behalf without them opening the app)

---

# Section 4: Open questions

1. **Group-post filter**: Does "new post in a group by a friend" mean (a) only notify members who are friends with the author, or (b) notify all group members (since they opted into the group)? (a) is the literal spec; (b) is simpler and probably what users actually want.
2. **Backend device-token table shape**: Need to confirm `notifications_register` stores tokens keyed by `userId` so we can fan-out by user. If it's keyed by token only, we need a GSI or schema tweak.
3. **Spotify refresh tokens server-side**: Are refresh tokens stored on the `xomify-users` row, or only the access token (which expires hourly)? Wrapped + RR pollers need refresh tokens to call Spotify without the user being active.
4. **Friendship gate on DMs**: Can any user DM any other user (handle-resolvable), or only mutual friends? Recommend mutual-friends-only for v1 to avoid spam vectors.
5. **Wrapped polling window**: Confirm Nov 25 – Dec 15 covers the release. Spotify dropped Wrapped on Dec 4 in 2024, Nov 29 in 2023. The window is conservative.
6. **Release Radar timing**: RR refreshes Friday morning. Notify Monday morning (when most people check phones) or Friday afternoon (immediately fresh)? Recommend Friday afternoon UTC, simpler scheduling.
7. **Notification prefs UI surface**: Settings screen on iOS + Angular, or in-line toggles? Out of scope for this brainstorm but flagging for the plan.
8. **Existing `xomify-shares` track payload shape**: Confirm the schema so the DM `kind: track` payload mirrors it exactly — avoids two formats for "a track inside a message."
9. **Web push for Angular**: Confirmed out of scope for v1? (Recommend: yes, out of scope.)
10. **Notification deep link handler**: Does iOS already have a `xomify://` URL scheme handler registered, or does this PR introduce it?

---

```
Brainstorm saved: docs/features/dms-and-notifications/BRAINSTORM.md
Recommendation: Option A — Single-table threads + polling + blocking + share-a-track
Next: /plan dms-and-notifications — I'll use this doc as context
```
