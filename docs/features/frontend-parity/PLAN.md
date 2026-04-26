# Plan: Xomify Social Feed — frontend-parity

**Epic**: [xomify-social-feed](../xomify-social-feed/PLAN.md)
**Sub-feature ID**: 10 (`frontend-parity`)
**Status**: Ready
**Created**: 2026-04-22
**Last updated**: 2026-04-23
**Scope size**: M (confirmed after audit — see Split strategy below; expected two PRs)
**Repo touched**: `xomify-frontend` (Angular 18 / TypeScript strict)
**Branch**: `feat/frontend-parity`
**Depends on**: `backend-shares` (#3, landed), `backend-interactions-and-notifications` (#4, landed)

---

## Summary

Bring the Angular web client up to parity with the deployed backend schema for shares / reactions / invites / notifications. Audit confirmed significant model drift: the web `Share` interface uses a legacy `{ type, payload, interactionCounts }` shape with `like|fire|love|none` emoji reactions, while the backend ships denormalized track metadata (`trackId|trackUri|trackName|artistName|albumName|albumArtUrl|caption|moodTag|genreTags`) + enrichment (`queuedCount|ratedCount|viewerHasQueued|viewerRating|sharerRating`) and `queued|rated|unqueued|unrated` reactions. Web also has invites/create + invites/accept wired but is missing `/invites/pending` + `/invites/decline`, which are now live. Groups UI in web is richer than iOS (admin + shared-queue UI survives) — no alignment needed, only a small audit sweep.

Success = the web Feed renders live shares with real track art/caption/tags, queue/rate reactions round-trip with backend counts, users can manage outstanding + incoming invites, and the notifications settings page shows registered devices with an unregister affordance.

## Approach

Two-PR split, driven by the audit: **model drift fix first, UX additions second.** This is forced by the fact that the current `Share` and `ReactionAction` types are structurally incompatible with the deployed backend, so the Feed is almost certainly broken in prod already — we unblock that with a surgical interface + template fix before layering invites/notifications UX on top.

- **PR 1 — `feat/frontend-parity-models`**: type/model drift fix for `Share`, `FeedResponse`, `ReactionAction`. Rewrite `share-feed.service.ts` signatures (`createShare`, `getFeed`, `reactToShare`), `share-card.component.ts` (+ template), `feed.component.ts`. Delete the old emoji-reaction UI, swap in queue + rate (star rating reuses the existing `StarRatingComponent`). Add `viewerHasQueued` / `viewerRating` visual state. Add track-specific composer path alongside the legacy wrapped/release-radar branches. Spec updates.
- **PR 2 — `feat/frontend-parity-ux`**: invites management page (pending list + decline + resend), notifications preferences page (list registered devices, unregister), wire both into the user drawer/profile menu. Group filter chips on the Feed view (uses existing `GroupsService.getGroups`).

Both PRs branch off `master`; PR 2 branches off `feat/frontend-parity-models` (after merge) because its UI reuses the fixed Share type.

Following existing Angular 18 patterns in the repo: module-per-feature (pages/social for route-level, components/ for reusable), `HttpClient` via feature-scoped services, `BehaviorSubject` caches in services (see `friends.service.ts`, `groups.service.ts`), `take(1)` on subscriptions. No new frameworks. TypeScript strict already on.

## Source-of-truth backend shapes (for reference while coding)

Canonical shapes lifted directly from the deployed backend handlers:

**Share** (from `shares_create` / `shares_feed` / `shares_user` responses):
```ts
interface Share {
  shareId: string;
  email: string;                // author (was `sharedBy` in early epic doc; handler uses `email`)
  trackId: string;
  trackUri: string;
  trackName: string;
  artistName: string;
  albumName: string;
  albumArtUrl: string;
  caption?: string;             // <= 140 chars
  moodTag?: 'hype' | 'chill' | 'sad' | 'party' | 'focus' | 'discovery';
  genreTags?: string[];         // <= 3
  createdAt: string;            // ISO8601
  sharedAt: string;             // mirror of createdAt
  // enrichment (shares_feed, shares_user)
  queuedCount: number;
  ratedCount: number;
  viewerHasQueued: boolean;
  viewerRating: number | null;
  sharerRating: number | null;
}
interface FeedResponse { shares: Share[]; nextBefore: string | null; }
```

**Reaction** (`shares_react`):
```ts
type ReactionAction = 'queued' | 'rated' | 'unqueued' | 'unrated';
interface ReactRequest { email: string; shareId: string; action: ReactionAction; rating?: number; }
interface ReactResponse { queuedCount: number; ratedCount: number; viewerHasQueued: boolean; viewerRating: number|null; sharerRating: number|null; }
```

**Invites** (`invites_create`, `invites_accept`, `invites_pending`, `invites_decline`):
```ts
interface Invite { inviteCode: string; senderEmail: string; createdAt: string; expiresAt: string; consumedAt?: string; consumedBy?: string; inviteUrl?: string; }
interface PendingInvitesResponse { email: string; invites: Invite[]; count: number; }
interface CreateInviteResponse { inviteCode: string; inviteUrl: string; expiresAt: string; createdAt: string; }
interface AcceptInviteResponse { ok: true; senderEmail: string; inviteCode: string; }
interface DeclineInviteResponse { ok: true; inviteCode: string; senderEmail: string; }
```

**Notifications** (`notifications_register`, `notifications_unregister`):
```ts
interface RegisterRequest { email: string; deviceToken: string; digestEnabled?: boolean; queueNotificationsEnabled?: boolean; }
// Web note: browsers do NOT receive APNs tokens. The UI only reads existing registrations
// (iOS devices) and can call unregister. No register call from web.
```

## Critical decisions inherited from epic (do not re-litigate)

- **Backend is source of truth**. Angular reconciles to #3 + #4. See epic Risks → schema drift.
- **Additive-only backend responses**: holds — legacy `type`/`payload`/`interactionCounts` fields are no longer emitted by backend. Web type must be rewritten (non-breaking on the wire, but breaking for existing web renders — acceptable because Feed was freshly rebuilt and Dom is the only real user).
- **Frontend cleanup (broken top-nav tabs) is out of scope** — tracked separately.
- **No lockstep requirement**: Angular may lag iOS TestFlight by a week. Merging PR 1 within the week, PR 2 within two weeks, is fine.
- **Groups stay "shared-queue" on web**, "filter-only" on iOS. Web keeps its existing richer Groups UI; only change is adding Group filter chips to the Feed page.

## Affected Files / Components

| File / Component | Change | Why | PR |
|------------------|--------|-----|----|
| `src/app/services/share-feed.service.ts` | rewrite | `Share` / `FeedResponse` / `ReactionAction` drift; new endpoints for invites pending + decline | 1 |
| `src/app/components/share-card/share-card.component.ts` | rewrite | old emoji reactions → queue + 1-5 star rate + count chips | 1 |
| `src/app/components/share-card/share-card.component.html` | rewrite | render track metadata directly + queue button + star rating + mood/genre tag chips + "queued by N" chip | 1 |
| `src/app/components/share-card/share-card.component.scss` | extend | style new chips + reaction row | 1 |
| `src/app/pages/feed/feed.component.ts` | modify | consume new `FeedResponse` (nextBefore pagination), add group filter state | 1 + 2 |
| `src/app/pages/feed/feed.component.html` | modify | filter chip row (PR 2), pagination "Load more" button | 1 + 2 |
| `src/app/components/share-composer/` **(new)** | add | track-share composer (caption, mood, genre tags) — adapted from `add-song-modal` pattern | 1 |
| `src/app/services/invites.service.ts` **(new)** | add | wrap `/invites/create|accept|pending|decline`; moves invite methods out of `share-feed.service.ts` | 2 |
| `src/app/pages/invites/invites.component.*` **(new)** | add | Pending invites page (list / copy link / decline / revoke) + Accept-by-code form | 2 |
| `src/app/pages/social/social.module.ts` | modify | declare `InvitesComponent`, `NotificationSettingsComponent`, `ShareComposerComponent`, add `/invites` + `/settings/notifications` routes | 2 |
| `src/app/services/notifications.service.ts` **(new)** | add | GET registered devices (list via new backend read — see Open Questions) + POST unregister | 2 |
| `src/app/pages/notification-settings/notification-settings.component.*` **(new)** | add | List user's registered iOS devices, toggle digest/queue prefs, unregister | 2 |
| `src/app/components/toolbar/` | modify | add nav entries for `/invites` and `/settings/notifications` in user drawer | 2 |
| `src/app/pages/friends/friends.component.*` | modify | "Invite a friend" button that calls `invites.service.createInvite` + shows share sheet (`navigator.share` / clipboard fallback) | 2 |
| `src/app/components/share-card/share-card.component.spec.ts` | rewrite | new reaction model | 1 |
| `src/app/pages/feed/feed.component.spec.ts` | modify | new FeedResponse shape, pagination, filter | 1 + 2 |
| `src/app/services/share-feed.service.spec.ts` | rewrite | new endpoint contract | 1 |
| `src/app/services/invites.service.spec.ts` **(new)** | add | unit spec for the 4 invite endpoints | 2 |
| `src/app/services/notifications.service.spec.ts` **(new)** | add | unit spec for list + unregister | 2 |
| `src/app/pages/invites/invites.component.spec.ts` **(new)** | add | component spec | 2 |

## Implementation Steps

### PR 1 — Model drift fix (`feat/frontend-parity-models`)

- [ ] Step 1 — Branch from `master`: `git checkout -b feat/frontend-parity-models`.
- [ ] Step 2 — Rewrite types in `src/app/services/share-feed.service.ts`:
  - Delete `ShareType`, `InteractionCounts`, old `Share`, old `ReactionAction`.
  - Add new `Share`, `FeedResponse`, `ReactionAction = 'queued'|'rated'|'unqueued'|'unrated'`, `ReactResponse`, `CreateShareRequest`, `MoodTag` enum, `ReactRequest`.
  - Keep `CreateInviteResponse` / `AcceptInviteResponse` for now (moved to invites.service.ts in PR 2).
- [ ] Step 3 — Rewrite `createShare(email, track, caption?, moodTag?, genreTags?)` in `share-feed.service.ts` to POST the backend body shape (`email`, `trackId`, `trackUri`, `trackName`, `artistName`, `albumName`, `albumArtUrl`, optional `caption`, `moodTag`, `genreTags`).
- [ ] Step 4 — Rewrite `getFeed(email, opts?: { groupId?, limit?, before? })` to append query params and return `FeedResponse`.
- [ ] Step 5 — Rewrite `reactToShare(email, shareId, action, rating?)` — single action union, optional rating for `rated`. Return `ReactResponse`.
- [ ] Step 6 — Rewrite `src/app/components/share-card/share-card.component.ts`:
  - Remove `payload`-based getters (`trackName`, `trackArtist`, `trackImage`, `playlistName`, etc.).
  - Add direct getters that read `share.trackName`, `share.artistName`, `share.albumArtUrl`, `share.caption`, `share.moodTag`, `share.genreTags`.
  - Replace 3-emoji reaction set with: (a) Queue button (toggles `queued`/`unqueued`) and (b) 1–5 star rating row (posts `rated` with rating; `unrated` via tapping current). Reuse `<app-star-rating>` from SharedModule.
  - Track viewer state via `share.viewerHasQueued` + `share.viewerRating` (no more session-only `myReaction`).
  - Optimistic update: flip local `viewerHasQueued` / `queuedCount` on click; rollback on error; on success overlay backend-returned counts.
- [ ] Step 7 — Rewrite `src/app/components/share-card/share-card.component.html`:
  - Single unified card: album art + track name + artist + caption + mood chip + genre chips + queue button (filled when `viewerHasQueued`) + star rating + "queued by N" chip when `queuedCount > 0`.
  - Remove wrapped/release-radar/playlist branches — backend no longer emits those share types.
- [ ] Step 8 — Update `src/app/components/share-card/share-card.component.scss`: add styles for mood chip, genre-tag row, queued-count chip. Drop emoji-reaction button styles.
- [ ] Step 9 — Update `src/app/pages/feed/feed.component.ts`:
  - Use `FeedResponse` (replace `totalCount` — no longer emitted; use `shares.length`).
  - Track `nextBefore: string | null`; add `loadMore()` that appends when not null.
  - Wire `trackByShareId` to continue working.
- [ ] Step 10 — Update `src/app/pages/feed/feed.component.html`: add "Load more" button when `nextBefore` present; update empty state copy to mention posting a share.
- [ ] Step 11 — Create `src/app/components/share-composer/share-composer.component.{ts,html,scss}`:
  - Input: current track from `PlayerService` OR searched track (pattern from `add-song-modal`).
  - Form: caption (≤140 char counter), mood dropdown (6 options), genre chips input (≤3).
  - Submit → `shareFeedService.createShare()` → emit `shared` event, close modal, toast success, parent refreshes feed.
  - Wire into `FeedComponent` as a FAB button `+ Share` on the feed page header (opens modal).
- [ ] Step 12 — Declare `ShareComposerComponent` in `social.module.ts`.
- [ ] Step 13 — Rewrite `src/app/services/share-feed.service.spec.ts` with Jasmine + `HttpTestingController`. Cover `createShare`, `getFeed` (query param encoding + limit/before/groupId), `reactToShare` (with/without rating).
- [ ] Step 14 — Rewrite `src/app/components/share-card/share-card.component.spec.ts`: queue toggle roundtrip, rating submit, optimistic rollback on error.
- [ ] Step 15 — Update `src/app/pages/feed/feed.component.spec.ts`: consume new `FeedResponse`, verify `loadMore` appends.
- [ ] Step 16 — Run `npm run test -- --watch=false` and `npm run build:prod` locally. Fix any strict-mode errors.
- [ ] Step 17 — Commit + push, open PR titled `feat: frontend parity — shares/reactions model drift fix`. Do NOT add Co-Authored-By.
- [ ] Step 18 — Request `code-reviewer` agent pass; merge to `master`.

### PR 2 — Invites + Notifications UX (`feat/frontend-parity-ux`)

- [ ] Step 19 — Branch from `master` (post-PR-1 merge): `git checkout -b feat/frontend-parity-ux`.
- [ ] Step 20 — Create `src/app/services/invites.service.ts`:
  - Move `createInvite` / `acceptInvite` out of `share-feed.service.ts` into this new service.
  - Add `listPending(email): Observable<PendingInvitesResponse>` → GET `/invites/pending?email=...`.
  - Add `declineInvite(email, inviteCode): Observable<DeclineInviteResponse>` → POST `/invites/decline`.
  - Add a `BehaviorSubject<Invite[]>` cache of outstanding invites, pattern mirroring `friends.service.ts`.
- [ ] Step 21 — Remove invite methods from `share-feed.service.ts`; callers import from `invites.service.ts`.
- [ ] Step 22 — Create `src/app/pages/invites/invites.component.{ts,html,scss}`:
  - Tabs: **Outstanding** (your sent invites — `listPending`), **Accept a code** (text input → `acceptInvite`).
  - Outstanding list: show code, created/expires timestamps, "Copy link" (uses existing `ShareService.copyToClipboard`), "Share" (uses `ShareService.share`), "Revoke" (calls `declineInvite` with the sender's own email — note: backend rejects self-decline, so Revoke needs to be a no-op UI that hides locally and flags open question, OR require a new `invites_revoke` endpoint — flag to Dom in Open Questions).
  - Accept-by-code tab: input + submit → on success, show "You're now friends with {senderEmail}" and link to `/friend/{email}`.
- [ ] Step 23 — Add `/invites` route to `social.module.ts` and declare `InvitesComponent`.
- [ ] Step 24 — Add `InvitesComponent.spec.ts` covering list + accept + decline happy paths.
- [ ] Step 25 — Modify `src/app/pages/friends/friends.component.{ts,html}`: add "Invite a Friend" primary button at the top of the Friends tab that calls `invitesService.createInvite(currentEmail)` then invokes `shareService.share({ url: inviteUrl, title: 'Join me on Xomify', text: '...' })`. Toast confirms. No new page — reuses existing share-sheet flow.
- [ ] Step 26 — Create `src/app/services/notifications.service.ts`:
  - `unregisterDevice(email, deviceToken)` → POST `/notifications/unregister`.
  - `listDevices(email)` → GET (endpoint TBD — see Open Questions). If no list endpoint lands, skip list and scope this PR to a read-only "Notifications disabled on web — manage on iOS" placeholder with a manual unregister-by-token form. Flag to Dom.
- [ ] Step 27 — Create `src/app/pages/notification-settings/notification-settings.component.{ts,html,scss}`:
  - Header: "Push notifications" + explainer "Web browsers can't receive iOS push tokens. Manage your registered iOS devices here."
  - Body: list of registered devices (if backend list endpoint exists) with "Remove" button per row; otherwise a manual `deviceToken` unregister form behind an "Advanced" disclosure.
  - Show digest/queue preference toggles (read-only on web for v1 — note iOS owns writes).
- [ ] Step 28 — Add `/settings/notifications` route to `app-routing.module.ts` or the social module; add nav entry to `toolbar.component.html` user menu.
- [ ] Step 29 — Add filter chip row to Feed page:
  - Inject `GroupsService` into `FeedComponent`; fetch groups on init.
  - Render chips: `All Friends` + one chip per group.
  - On click, set `activeGroupId` and call `shareFeedService.getFeed(email, { groupId })`.
  - Pattern matches iOS Feed filter chips (see iOS epic).
- [ ] Step 30 — Add component + service specs for PR 2. Update any existing specs that import renamed symbols.
- [ ] Step 31 — Run `npm run test -- --watch=false` and `npm run build:prod`.
- [ ] Step 32 — Commit + push, open PR titled `feat: frontend parity — invites mgmt + notifications settings + feed group filter`. Do NOT add Co-Authored-By.
- [ ] Step 33 — Request `code-reviewer` agent pass; merge to `master`.

## Out of Scope

- Angular app cleanup of unused/broken top-nav tabs (tracked separately).
- Any iOS or backend work. Backend invite revoke / device-list endpoints may be surfaced as new backend work — see Open Questions.
- Groups UI redesign on web — keeps its existing shared-queue semantics; only gains filter chips on Feed.
- Server-sent events / realtime feed updates. Pull-refresh + "Load more" is enough.
- Progressive Web App push notifications. Deferred. Web notification UI is read-only/manage-only on day 1.
- Deep-link handler for `https://xomify.app/invite/<code>` landing page — owned separately once the domain is wired with AASA.

## Split strategy (answer to Dom's pre-flag)

Audit confirms **two PRs is the right call**. Files touched across both:

- PR 1 surface: ~8 files (share-feed.service, share-card.ts/html/scss, feed.ts/html, share-composer new set, social.module, 3 specs) — just over 10 if composer counts as 3. The type change alone is breaking enough to be its own reviewable diff.
- PR 2 surface: ~10 files (invites.service new, invites page set, notifications.service new, notification-settings page set, friends invite CTA, toolbar, social.module, feed filter chip additions, specs).

Single combined PR would be ~18 files and two independent concerns; reviewers would hate it. Split stands.

## Risks / Tradeoffs

- **Web Feed currently broken in prod**: legacy `type`/`payload` Share renders have no backend counterpart. Mitigation: ship PR 1 within the week. Low impact because Dom is effectively the only user.
- **Optimistic reaction rollback**: failures mid-POST leave counts visibly flicker. Accepted — same pattern as iOS.
- **Composer Spotify track source**: new composer relies on `PlayerService` current track + search fallback. If neither is populated (user just logged in, hasn't played anything), composer disables submit. Acceptable first pass.
- **Revoke own invite**: backend `invites_decline` blocks self-decline (line 87 of handler). UI workaround is client-local hide + rely on 30-day expiry. Flagged as open question; cleanest fix is a backend `invites_revoke`.
- **Notifications list**: no `/notifications/list` endpoint in backend reconnaissance. Without it the web settings page can only unregister by known token — weak UX. Flagged; decision to add endpoint is Dom's call.
- **TypeScript strict drift**: removing `ShareType`/`payload` may leak into other callers (e.g. `friend-profile.component.ts` if it renders shared items). Mitigation: run `ng build --configuration production` under strict mode before PR — will surface every call site.

## Open Questions

- [ ] **Revoke-own-invite flow**: backend forbids self-decline. Add `invites_revoke` lambda (sender-only delete) as a follow-up backend task, or settle for client-side hide + expiry? **Recommended**: add lightweight `invites_revoke` — it's ~40 lines and parallels `invites_decline`. Needs a one-line yes/no from Dom.
- [ ] **Notifications device list**: does a `/notifications/list?email=` endpoint exist or need to be added? Quick backend add (~30 lines — scan/query `device_tokens` by PK). Needed for a real notifications settings page; without it PR 2's notifications page ships as an "Advanced > unregister by token" form only.
- [ ] **Reactions behind a feature flag?** (Pre-flagged by Dom.) Web doesn't need APNs secrets so there's no technical reason to gate reactions. Recommendation: **no flag** — ship reactions inline with PR 1. If Dom wants one for parity with iOS, add a 5-line `environment.enableReactions` boolean and tack it onto the share-card template with `*ngIf`. Default on. Flag is redundant — confirm drop.
- [ ] **Composer FAB placement**: floating action button bottom-right (iOS parity) vs. inline header button. Minor, decide during UI review.

## Skills / Agents to Use

- **frontend-specialist agent** (or Angular-specialist): primary executor. Single pass per PR should be enough given the file list is concrete.
- **test-writer agent**: pair on Jasmine specs for the three new/rewritten services + three new components.
- **code-reviewer agent**: mandatory pass before merge on each PR.
