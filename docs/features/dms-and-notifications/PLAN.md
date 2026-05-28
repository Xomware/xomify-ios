# Plan: DMs and Notifications

**Status**: Draft
**Created**: 2026-04-28
**Last updated**: 2026-04-28
**Spans repos**: `xomify-backend` (Python/Lambda/DynamoDB/APNS), `xomify-ios` (SwiftUI)
**Brainstorm**: `docs/features/dms-and-notifications/BRAINSTORM.md`

---

## 1. Goal + Non-Goals

### Goal
Ship 1:1 direct messaging (with track-share inline messages) and four new push-notification categories (DM, Spotify Wrapped, Release Radar, group post by any member) on top of the existing APNS pipeline. Add a notification-prefs surface on iOS so users can toggle each category and mute individual groups.

### Non-Goals (v1)
- Group DMs (1:1 only — group posts already cover N-way)
- WebSockets / live delivery — polling + APNS only
- Typing indicators, message reactions, message edit
- Attachments other than track shares
- E2E encryption
- In-app notification inbox / history (APNS-only delivery)
- Web push for the Angular frontend
- Quiet hours / batching
- Read receipts beyond `lastReadAt` on the user's own thread index row

---

## 2. Decision Summary (already locked in)

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | DMs: BRAINSTORM Option A (single-table threads, polling, blocking, share-a-track) | Matches spec; avoids WebSocket infra; keeps blocks in scope so we don't retrofit later |
| 2 | Friends-only DM gate (server-enforced via `friendships` `status=accepted`) | Anti-spam; reuses existing `are_users_friends()` helper |
| 3 | Group-post notification fans out to **all group members** (not friends-only) | Simpler, matches Slack-channel mental model. Per-group mute covers the noise case |
| 4 | Notification triggers reuse existing `notifications_send` + `device_tokens_dynamo`; copy `_invoke_threshold_push` pattern from `shares_react` | Don't re-architect — the pipeline already does APNS + 410-prune |
| 5 | Notification prefs stored as a `notifPrefs` map on the `xomify-users` row (single read on send) | Folds into existing user profile row; one less table |
| 6 | Per-group mute stored on the `xomify-users` row as a `mutedGroupIds: Set<String>` | See section 3 for tradeoff vs. dedicated table — the set fits the existing pattern and stays in the single profile read |
| 7 | All notification categories default to ON for new users | Conservative-on-discoverability beats conservative-on-volume; users will opt out if noisy |

---

## 3. Backend Work (`xomify-backend`)

### 3a. Table schemas

**New table — `xomify-dms`** (single-table style, mirrors `shares` conventions):

```
PK: threadId           (string — sha1(min(emailA,emailB) + "#" + max(emailA,emailB)))
SK: rowType            (string — "META" | "MSG#<ulid>")
attrs (META row):
  participants: [emailA, emailB]
  createdAt: ISO8601
  lastMessageAt: ISO8601
  lastMessagePreview: string (<=80 chars)
  lastMessageKind: "text" | "track"
attrs (MSG row):
  senderEmail, kind ("text"|"track"), body?, trackPayload?, createdAt, deleted? (bool)
```

**New table — `xomify-thread-index`** (per-user inbox + unread):

```
PK: email
SK: lastMessageAt#threadId   (ISO8601 sort, desc-readable)
attrs:
  threadId, otherEmail, otherDisplayName (denorm), lastReadAt, unreadCount,
  lastMessagePreview, lastMessageKind, lastMessageAt
```

`SK` is composite so we can `ScanIndexForward=False` for inbox order without a GSI.

**New table — `xomify-blocks`** (kept tiny; wired in v1 even if UI lands later):

```
PK: blockerEmail
SK: blockedEmail
attrs: createdAt
```

**Modify — `xomify-users` row** (no migration; new attrs default-absent treated as "all on"):

```
+ notifPrefs: {
    dm: bool,           # default true
    wrapped: bool,      # default true
    releaseRadar: bool, # default true
    groupPost: bool,    # default true
    threshold: bool     # existing queue-threshold; default true
  }
+ mutedGroupIds: Set<String>            # default absent == empty
+ wrappedPlaylistIdSeen: { "<year>": "<playlistId>" }
+ releaseRadarPlaylistId: string
+ releaseRadarLastTrackIds: List<String>  # ~30 ids
```

**Why the user-row map vs a separate `group_notification_settings` table:**
The other reaction/share helpers all read the user row anyway (e.g. `get_user`); folding `notifPrefs` + `mutedGroupIds` into it means notification dispatch costs **one** GetItem instead of two. The set-on-profile pattern is already used elsewhere (e.g. `genreTags` on shares, similar shape). A dedicated table only earns its keep if mute counts get into the thousands per user — not realistic. Trade-off: a single row gets hot if a user mutes/unmutes rapidly, but writes are infrequent enough that this isn't a concern.

### 3b. New helpers (`lambdas/common/`)

| Helper file | Purpose |
|-------------|---------|
| `dms_dynamo.py` | `compute_thread_id`, `get_or_create_thread`, `append_message`, `list_messages`, `bump_thread_index`, `mark_read` |
| `blocks_dynamo.py` | `is_blocked_either_way(a, b)` (single GetItem on each direction; OR result) |
| `notif_prefs_dynamo.py` | `get_notif_prefs(email) -> dict`, `set_notif_prefs(email, partial)`, `is_group_muted(email, groupId)` — wraps reads/writes against `xomify-users` row |
| `push_dispatch.py` | `send_push(email, category, title, body, custom_data, collapse_id?, thread_id?)` — single entry point that: (a) checks `notifPrefs[category]`, (b) checks per-group mute when `category=="groupPost"`, (c) async-invokes `notifications_send` with the right kind. Mirrors `_invoke_threshold_push` shape. |

### 3c. Modified lambdas

| Lambda | Change |
|--------|--------|
| `notifications_send/handler.py` | Extend `VALID_KINDS` to include `dm`, `wrapped`, `release_radar`, `group_post`. Extend `OPT_IN_FLAG_BY_KIND` mapping (or short-circuit the flag check for these — the `notifPrefs` check now happens upstream in `push_dispatch.send_push`, so `notifications_send` becomes the dumb APNS pipe). Document the split. |
| `shares_create/handler.py` | After successful share write, if `groupIds` non-empty: query group memberships, filter out author, call `push_dispatch.send_push(category="groupPost", ...)` per recipient. Fire-and-forget, do not block the response. |
| `notifications_register/handler.py` | No change (existing opt-in flags `digestEnabled` / `queueNotificationsEnabled` keep working) |

### 3d. New lambdas

| Lambda | Trigger | Notes |
|--------|---------|-------|
| `dms_send` | `POST /dms/send` | Validates friendship + block check. Writes MSG row, updates META, bumps both `xomify-thread-index` rows (sender unreadCount=0, recipient unreadCount+=1). Fires `push_dispatch.send_push(category="dm")` for recipient. |
| `dms_list_threads` | `GET /dms/threads` | Query `xomify-thread-index` PK=email, ScanIndexForward=False, limit. Returns inbox. |
| `dms_list_messages` | `GET /dms/threads/{threadId}/messages` | Query `xomify-dms` PK=threadId SK begins_with `MSG#`, ScanIndexForward=False, limit + `before` cursor. **Must verify caller is a participant** before returning. |
| `dms_mark_read` | `POST /dms/threads/{threadId}/read` | Updates caller's `xomify-thread-index` row: `lastReadAt=now`, `unreadCount=0`. |
| `dms_block` / `dms_unblock` | `POST /dms/block`, `POST /dms/unblock` | Writes/deletes `xomify-blocks` row. |
| `notif_prefs_get` / `notif_prefs_update` | `GET/PATCH /me/notif-prefs` | Reads/writes `notifPrefs` map + `mutedGroupIds` set on user row. PATCH accepts partial. |
| `wrapped_poller` | EventBridge cron, daily Nov 25 – Dec 15 at 17:00 UTC | For each user with `notifPrefs.wrapped` ≠ false AND a valid Spotify refresh token: call Spotify `/me/playlists`, look for the year's Wrapped playlist, compare against `wrappedPlaylistIdSeen[year]`, fire push + write marker if first-seen. Skip silently on token failure. |
| `release_radar_poller` | EventBridge cron, weekly Friday 18:00 UTC | For each opted-in user: resolve `releaseRadarPlaylistId` (cache on profile if absent), pull current track ids, diff vs `releaseRadarLastTrackIds`, fire push + overwrite list if non-empty diff. First-ever run = store list, no push. |

### 3e. Backend tests

Per-lambda unit tests under `lambdas/<name>/tests/`:
- `dms_send`: happy path, friendship-rejected, block-rejected, self-DM rejected, track payload shape, push fired
- `dms_list_threads`: ordering, limit, empty inbox
- `dms_list_messages`: pagination cursor, participant gate (non-participant gets 403)
- `dms_mark_read`: zeros unreadCount idempotently
- `notif_prefs_get/update`: defaults when attrs absent, partial PATCH preserves other keys, mute-group set ops
- `push_dispatch.send_push`: gates on prefs, gates on per-group mute, no-op when category disabled
- `wrapped_poller`: first-seen fires, second-seen no-op, missing refresh token silent-skip
- `release_radar_poller`: first run no-fire, diff-fires, no-diff no-fire
- `shares_create` (regression): single-recipient, multi-group fan-out, no-groupIds path unchanged

---

## 4. iOS Work (`xomify-ios`)

### 4a. Models (Codable)

- `DMThread { threadId, otherEmail, otherDisplayName, otherAvatarUrl?, lastMessagePreview, lastMessageAt, unreadCount }`
- `DMMessage { messageId, threadId, senderEmail, kind: DMKind, body?, trackPayload?, createdAt, deleted }`
- `DMKind = .text | .track`
- `DMTrackPayload` mirrors `Share` track fields (`trackId, trackUri, trackName, artistName, albumName, albumArtUrl`) so the existing track bubble component renders unchanged
- `NotifPrefs { dm, wrapped, releaseRadar, groupPost, threshold }` (all `Bool`, default true)
- `MutedGroupIds = Set<String>`

### 4b. Networking (services layer)

- `DMService`: `sendMessage`, `listThreads`, `listMessages(threadId, before:)`, `markRead(threadId)`, `block(email)`, `unblock(email)`
- `NotifPrefsService`: `getPrefs()`, `updatePrefs(partial:)`, `muteGroup(groupId)`, `unmuteGroup(groupId)`
- `PushNotificationRouter`: maps incoming APNS `data.type` → deep-link target (`dm`, `wrapped`, `releaseRadar`, `groupPost`)

### 4c. View models

- `InboxViewModel` (polls `listThreads` every 15s while foreground; pauses on background)
- `ChatViewModel` (polls `listMessages` every 5s while view is on screen + `markRead` on open and on app-foreground)
- `NotifPrefsViewModel` (loads on Settings open, debounced PATCH on toggle)
- `BlockListViewModel` (settings sub-screen, lists blocked users + unblock action)

### 4d. Views

- `InboxView` — list of `DMThread`s, unread badge, tap to open chat, "New Message" entry that picks from friends list (friends-only — no handle search)
- `ChatView` — message list (text + track bubbles), input bar, "Share a track" inline picker (reuses existing track-search sheet), block menu in nav bar
- `NotifSettingsView` — section on the Profile/Settings screen with 5 toggles (DMs, Wrapped, Release Radar, Group posts, Threshold pushes) and a "Muted groups" sub-list
- `MutedGroupsView` — list of muted groups with unmute swipe action
- Empty states: "No messages yet — share a track with a friend to start a thread"

### 4e. Navigation / deep links

- Register `xomify://` URL scheme handler if not already (open question — see §6)
- Routes: `xomify://dm/<threadId>`, `xomify://group/<id>/post/<postId>`, `xomify://wrapped`, `xomify://release-radar`
- APNS `userNotificationCenter(_:didReceive:)` → `PushNotificationRouter.handle(userInfo:)` → push the right view onto the active nav stack

### 4f. Polling cadence (locked)

| Surface | Cadence | Notes |
|---------|---------|-------|
| Inbox open | 15s | Pause when app backgrounded |
| Chat open | 5s | Mark read on open + on each new-message arrival while focused |
| Background | n/a | APNS handles delivery |

---

## 5. Phasing / Order

Two independent tracks. Notifications-prefs UI is a prerequisite for Phase 2 user-facing toggles, but the backend `notifPrefs` plumbing can ship first behind defaults.

### Phase 0 — Foundations (1 PR, backend only)
- Add `notifPrefs` defaults + `push_dispatch.send_push` helper
- Extend `notifications_send` to accept new kinds
- Add `notif_prefs_get` / `notif_prefs_update` lambdas + `/me/notif-prefs` routes

**Ships independently. No iOS dependency. Verifiable by hitting the endpoint with curl.**

### Phase 1 — DMs (2 PRs, backend + iOS — landed together behind a feature flag)
- Backend: `xomify-dms` + `xomify-thread-index` + `xomify-blocks` tables, all 6 DM lambdas
- iOS: models, services, Inbox + Chat views, friends-only thread creation, block/unblock, polling, push handler for `dm` category
- Wire DM push trigger inside `dms_send` via `push_dispatch.send_push(category="dm", ...)`

### Phase 2 — Group post notifications (1 PR, backend only)
- Modify `shares_create` to fan out push when `groupIds` non-empty
- Per-group mute already wired via `push_dispatch` from Phase 0
- Regression test on `shares_create` paths
- iOS already has the deep-link handler from Phase 1

### Phase 3 — Wrapped + Release Radar pollers (1 PR, backend only)
- `wrapped_poller` + `release_radar_poller` lambdas + EventBridge schedules
- `xomify-users` schema additions for markers (no migration — attrs default-absent)
- **Depends on**: Spotify refresh tokens being persisted server-side (open question §6)

### Phase 4 — iOS notification settings UI polish (1 PR, iOS only)
- `NotifSettingsView` + `MutedGroupsView` wired up
- Profile screen integration

**Dependency tree:**
```
Phase 0 ─┬─> Phase 1 (DMs)
         ├─> Phase 2 (Group push) ──┐
         ├─> Phase 3 (Wrapped/RR)   ├─> Phase 4 (Settings UI)
         └──────────────────────────┘
```

Phases 1, 2, 3 can run in parallel after Phase 0 lands.

---

## 6. Risks + Open Questions

### Risks
- **Spotify API fragility (Wrapped detection)**. Naming convention can change year-over-year. Mitigation: log + alarm on the poller's "found a wrapped playlist" counter in late November; manual-trigger lambda exists for hot-fix. Acceptable risk for an annual event.
- **Spotify rate limits (Release Radar weekly poll)**. 1 call per opted-in user per week. Trivial at hundreds, watch at low-thousands. Mitigation: chunk the poller into batches with sleeps if user count grows past ~1k.
- **Notification fatigue**. Four new categories on top of existing threshold pushes. Mitigation: defaults stay ON but the prefs UI ships in the same release; per-group mute provides escape valve for chatty groups.
- **Polling cost on DMs**. 5s during chat open is fine for a couple of users; thousands of concurrent open-chat sessions adds up. Mitigation: cheap query (single PK GetItem-ish), but keep an eye on read-capacity metrics. Future: switch open-chat to longer poll if needed.
- **Block bypass via group post**. A blocked user could still pop into your notification stream via a shared group. Acceptable for v1 — block is DM-scope only. Document this on the block UI.
- **Friendship-gate UX**: opening a thread with someone who's no longer a friend (unfriend mid-conversation) — the thread still exists but new sends 403. Spec'd as "frozen thread, read-only" — confirm this matches Dom's mental model (open question).

### Open Questions
- [ ] **Do Spotify refresh tokens already persist on the `xomify-users` row?** If only access tokens are cached, Wrapped + Release Radar pollers cannot function. Phase 3 blocks on this — needs a 5-min check in the auth lambda. If missing, prepend a sub-phase: "persist refresh tokens at OAuth callback."
- [ ] **iOS `xomify://` URL scheme** — already registered in `Info.plist`, or new in this PR? Affects effort estimate for Phase 1.
- [ ] **Frozen thread on unfriend** — read-only or hidden entirely from inbox? Recommend read-only with a banner ("You and X are no longer friends — replies disabled").
- [ ] **`shares_create` group-post recipients** — query existing groups membership table directly, or is there a `list_group_members` helper? If neither, Phase 2 needs that helper added first.
- [ ] **Wrapped polling year window** — Spotify dropped Wrapped on Nov 29 in 2023, Dec 4 in 2024. Confirm Nov 25 – Dec 15 is the right window for 2026.
- [ ] **Release Radar timing** — Friday 18:00 UTC vs. Monday morning local. Recommend Friday (simpler, fresh content) unless there's a usage data argument otherwise.
- [ ] **Notification volume budget** — APNS has no per-user cap, but is there a per-app warning threshold we want to set in CloudWatch?

---

## 7. Test Plan

### Backend
- Unit tests per new lambda (see §3e)
- **Friendship gate regression**: explicit test that `dms_send` with `(emailA, emailB)` where status≠accepted returns 403 with a structured error
- **Block gate regression**: same, for `xomify-blocks` row in either direction
- **Idempotency**: `dms_mark_read` called twice produces the same state; `wrapped_poller` re-run on the same day no-ops
- **`shares_create` regression suite**: existing tests pass unchanged; new tests for group-post fan-out

### iOS
- **Unit**: ViewModel logic with mocked services (polling pause on background, mark-read on open, debounce on prefs PATCH)
- **Preview**: SwiftUI previews for `InboxView`, `ChatView` (text + track bubble), `NotifSettingsView`, empty + populated states
- **Manual checklist**:
  - Send DM A→B, verify push lands on B's device
  - Send DM A→B with B muted via `notifPrefs.dm=false`, verify no push
  - Block A from B, verify A's send returns 403
  - Open thread, send 5 messages, verify polling picks them up
  - Background app, send DM, verify APNS deep-links into chat on tap
  - Toggle off "Group posts" prefs, verify no push on new group share
  - Mute one group, post in two groups, verify only the unmuted one fires
  - Force-fire `wrapped_poller` via direct invoke, verify push + deep link
  - Force-fire `release_radar_poller` after seeding a non-empty diff, verify push

---

## 8. Cutover / Rollout

### Feature flag
- iOS: `featureFlags.dmsEnabled` (defaults false in the first TestFlight build, flip true after smoke test)
- Backend: lambdas + tables can ship live (no flag needed — endpoints just 404 until the iOS app calls them)
- Notification triggers: gate each category behind `notifPrefs.<category>` defaults — flip to ON globally once smoke-tested on Dom's device

### Gradual rollout
- TestFlight internal-only build: Dom + 1-2 friends for a week
- Watch CloudWatch metrics:
  - `dms_send` invocation count + p99 latency
  - `notifications_send` invocations grouped by `kind`
  - APNS 410 prune rate (should not spike)
- Promote to TestFlight external once metrics look clean

### Telemetry to add
- Log line in `dms_send` with `threadId, hasTrack=bool, pushDispatched=bool`
- CloudWatch metric filter on `push_dispatch` for `category` cardinality
- iOS: log notification-tap → deep-link resolution events to existing analytics surface

### Rollback plan
- DMs: feature flag flip on iOS hides the inbox tab; backend tables stay (zero blast radius if tab is hidden)
- Notification categories: server-side, set `notifPrefs.<category>=false` for all users via a one-shot script (or just flip `VALID_KINDS` in `notifications_send` to drop the kind silently)
- Wrapped/RR pollers: disable EventBridge rule

---

## Skills / Agents to Use
- **backend-engineer**: Phase 0, 2, 3 — Python/Lambda/DynamoDB work in `xomify-backend`
- **ios-engineer**: Phase 1 (iOS half), Phase 4 — SwiftUI views, view models, deep-link routing
- **test-engineer**: per-phase unit-test pass before each PR opens
- **code-reviewer**: final pass on every PR — friend-gate and block-gate are the easy-to-miss correctness bugs

