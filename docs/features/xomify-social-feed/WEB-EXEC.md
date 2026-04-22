# Web Execution Plan — xomify-social-feed (web-first phase)

> Tactical order-of-operations for the web side. iOS port follows.
> Parent: PLAN.md · BRAINSTORM.md

## Goal
Ship clean web app with (1) only-working tabs, (2) fixed Wrapped + Release Radar for user, (3) salvaged Playlist Analysis / Mood Picks / Compare, (4) Share exports, (5) Feed + Friends + Groups. Deploy. Then mirror to iOS.

## Guiding rules
- Smallest reversible diffs per PR. No big-bangs.
- Verify each phase locally with `ng serve` before the next.
- Never `--no-verify`. Never force-push. No Co-Author lines.
- Branch: `feature/web-cleanup-and-feed` (frontend) · `feature/shares-and-salvage` (backend).

## Phase 0 — Nav slop cleanup (frontend-only, no backend risk)
**Goal**: delete the 9 broken items from `toolbar.component.ts` navLinks.

Delete (positions 11-19 in navLinks):
- `/recently-played` (History)
- `/new-releases`
- `/discover-artists`
- `/playlist-analysis`
- `/mood-recommendations`
- `/collaborative-playlists`
- `/share`
- `/streaming-stats`
- `/compare`

Also delete the routes from `app-routing.module.ts` for these paths (or redirect to `/my-profile` if external links exist).
Delete the orphaned page folders under `src/app/pages/` for deleted routes that we WON'T salvage: `recently-played`, `new-releases`, `discover-artists`, `collaborative-playlists`, `streaming-stats`.
**Keep folders (will salvage)**: `playlist-analysis`, `mood-recommendations`, `share`, `compare` — but unwire from nav until salvaged.

Verify: `ng build --configuration production` passes. Commit. PR.

## Phase 1 — Fix Wrapped + Release Radar data bug
**Goal**: user sees their own data on both pages.

Suspects in priority order:
1. Stale `sessionStorage` cache not keyed by email → if user switches accounts or prior load failed, cache poisoned.
2. UserService's cached user record missing `activeWrapped` / `activeReleaseRadar` flags, hiding UI even when data would load.
3. API responding correctly but frontend filter (e.g., week-key mismatch) swallowing results.

Fixes to apply:
- Change `ReleaseRadarService` cache key from `xomify_release_radar_history` → `xomify_release_radar_history:<email>` so accounts don't cross-pollute.
- Add same cache-key-per-email pattern to any other service caches.
- In `release-radar.component` and `wrapped.component`, log the API response to console (temporary, behind `if (!environment.production)`) so we can see raw shape in devtools.
- If user still sees no data after cache clear, add a "Force refresh" button (already exists on release-radar → verify it's visible and wired).

Verify: `ng serve`, hard-refresh browser (clear sessionStorage), log in as `dominickj.giordano@gmail.com`, hit both pages. Both should render weeks / months. Commit. PR.

## Phase 2 — Salvage: Playlist Analysis
**Goal**: rebuild without deprecated `audio-features`.

New approach (no audio-features needed):
- Track count, total duration, avg popularity
- Top artists in playlist (count of appearances)
- Decade breakdown (from `album.release_date`)
- Explicit track count
- Artist genre distribution (already have artist IDs → fetch genres)

Update `playlist-analysis.component.ts` to use only these. Delete any `audio-features` calls. Re-add to nav as submenu or chip under Builder/Playlists.

## Phase 3 — Salvage: Mood Picks
**Goal**: user-picked mood → Spotify recommendations.

Stack: user selects mood chip (Chill / Hype / Focus / Sad / Party / Workout) → map mood → seed params for Spotify `/recommendations` endpoint (still live) using seed artists from user's top artists. Display recommendations.

No AI needed. No audio-features needed. Deterministic seed mapping table lives in `mood-recommendations.component.ts`.

## Phase 4 — Salvage: Compare
**Goal**: Jaccard similarity between two real users (fixed dataset, not random).

Needs backend: `POST /compare-users` lambda taking two emails → returns Jaccard scores for (top tracks, top artists, top genres, recent releases). Deterministic — same inputs give same output.

Frontend `compare.component.ts` calls this endpoint. Remove any `Math.random()` calls.

## Phase 5 — Share exports
**Goal**: export image/card to share to socials.

Use `html2canvas` or native `canvas` to render a share card (top tracks, wrapped month, release week) to PNG. Trigger download or Web Share API. Wire `/share` route as a modal/flow from Wrapped + Release Radar "Share" buttons (not a standalone page).

## Phase 6 — Backend: shares + interactions + invites + friends + groups
**Goal**: DynamoDB tables + lambdas for Feed.

From PLAN.md: `xomify-shares`, `xomify-share-interactions`, `xomify-friends`, `xomify-groups`, `xomify-invites`.
Lambdas: `create_share`, `get_feed`, `react_to_share`, `add_friend`, `accept_friend`, `create_group`, `add_to_group`, `generate_invite`, `accept_invite`.

Deploy via Terraform. Test each endpoint in isolation before wiring frontend.

## Phase 7 — Web Feed + Friends + Groups UI
**Goal**: new top-level `/feed` route with Friends/Groups panels.

Friends/Groups live inside Profile tabs AND as collapsible side panels on Feed (filterable by group).

Feed card = track art + caption + mood tag + genre tags + user avatar + actions (queue/rate/react).

## Phase 8 — Deploy web + backend
- Backend: `terraform apply` in prod workspace.
- Frontend: push to `master`, CI deploys to S3+CloudFront.
- Smoke test live site end-to-end.

## Phase 9 — iOS port
Separate session. Mirror every web feature to SwiftUI respecting MVVM. Reuse all backend lambdas as-is.

## Current status
- [x] Branches resolved
- [x] Data exists in DynamoDB (confirmed via AWS CLI)
- [ ] Phase 0 — nav slop cleanup ← **next**
- [ ] Phase 1 — Wrapped + RR data bug
- [ ] Phase 2 — Playlist Analysis salvage
- [ ] Phase 3 — Mood Picks salvage
- [ ] Phase 4 — Compare salvage
- [ ] Phase 5 — Share exports
- [ ] Phase 6 — Backend social tables
- [ ] Phase 7 — Feed + Friends + Groups UI
- [ ] Phase 8 — Deploy
- [ ] Phase 9 — iOS port
