# Plan: Xomify Social Feed — ios-friends-management

**Epic**: [xomify-social-feed](../xomify-social-feed/PLAN.md)
**Sub-feature ID**: 7 (`ios-friends-management`)
**GitHub issue**: #30
**Status**: Ready
**Created**: 2026-04-22
**Last updated**: 2026-04-23
**Scope size**: M
**Repo(s) touched**: `xomify-ios`
**Depends on**: 2 (`ios-nav-shell`) merged, 8 (`ios-drawer-residents`) merged, 3 (`backend-shares`) deployed

---

## Summary

Harden the drawer-resident Friends screen into the epic's spec: keep the existing three-tab (Friends / Requests / Find) surface, add a confirm-then-remove flow, add an **Invite a Friend** CTA backed by `ShareLink` and a new pending-invites section that lists incoming deep-link invites with accept / decline actions. `XomifyService` already exposes `createInvite` / `acceptInvite`; incoming-invite listing needs either a new backend lambda (preferred) or a derived client surface (fallback, flagged). Success = Dom can open the drawer → Friends, hit "Invite a Friend", share `https://xomify.xomware.com/invite/<code>` via the iOS share sheet, and see inbound invites from other users with one-tap accept/decline.

## Approach

Drawer → FriendsView is **already wired** (see `Xomify-iOS/Views/Shell/DrawerView.swift` line 124) and the screen is **not** a placeholder — `Xomify-iOS/Views/FriendsView.swift` + `Xomify-iOS/ViewModels/FriendsViewModel.swift` cover friend requests / accepted / find. The epic language of "placeholder" is stale.

What this sub-feature actually needs on top of the existing implementation:

1. **Remove-friend confirmation** — current implementation removes on single tap. Wrap in a `.confirmationDialog` before calling `viewModel.remove`.
2. **Invite a Friend CTA** — add a prominent toolbar / header button on the Friends tab. Tapping it calls `XomifyService.createInvite` and presents a `ShareLink` with the minted `shareUrl` ("Join me on Xomify: https://xomify.xomware.com/invite/<code>"). Handle spinner + error state for the mint round-trip.
3. **Incoming Invites section** — new fourth segmented tab ("Invites") listing pending deep-link invites sent to the current user's email. Each row: sender label + time + Accept / Decline buttons. Accept calls `acceptInvite(email:, inviteCode:)`; decline is client-side dismissal unless backend exposes a decline endpoint (flag in Open Questions).
4. **Deep-link consumption** — when the app is opened via `https://xomify.xomware.com/invite/<code>`, route straight into the Friends screen's Invites tab with the code pre-filled and call `acceptInvite` once the user is authenticated. Requires a Universal Link handler at app-entry level.

Inherit MVVM pattern: `FriendsViewModel` holds all async state (list, isLoading, errors, in-flight Set); view layer stays declarative and never calls `XomifyService` directly.

Rationale for `ShareLink` over `UIActivityViewController`: `ShareLink` is the native SwiftUI API (iOS 16+) and composes cleanly with `@Observable` state. `UIActivityViewController` only justified if we need custom excluded activity types, which we don't for v1.

## Critical decisions inherited from epic (do not re-litigate)

- **Cold-start / invite flow is in scope** per epic Locked Answer #4.
- **`invite_create` / `invite_accept` lambdas ship in sub-feature 3** — already deployed; this sub-feature consumes them.
- **Lives in the drawer**, not the tab bar. Already wired in `DrawerView.swift`.
- **MVVM constraint**: views never touch `XomifyService` directly.
- **Deep link host**: the epic's working URL `https://xomify.app/invite/<code>` is superseded here by `https://xomify.xomware.com/invite/<code>` (pre-answered by Dom, subject to final sign-off — see Open Questions). Universal-link setup requires `apple-app-site-association` at that host.

## Affected Files / Components

| File / Component | Change | Why |
|-----------------|--------|-----|
| `Xomify-iOS/Views/FriendsView.swift` | modify | Add Invites tab, Invite-a-Friend toolbar CTA, remove-friend confirmation dialog |
| `Xomify-iOS/ViewModels/FriendsViewModel.swift` | modify | Add `incomingInvites: [PendingInvite]`, `createInviteLink() async -> URL?`, `acceptInvite(_:)`, `declineInvite(_:)`, `loadInvites(email:)` |
| `Xomify-iOS/Models/SocialModels.swift` | extend | Add `PendingInvite` (inviteCode, senderEmail, senderDisplayName, createdAt, expiresAt) and `PendingInvitesResponse` (`{invites: [PendingInvite]}`) |
| `Xomify-iOS/Services/XomifyService.swift` | extend | Add `listPendingInvites(email:)` → `PendingInvitesResponse`; add `declineInvite(email:, inviteCode:)` → `SuccessResponse` (gated on backend availability) |
| `Xomify-iOS/XomifyApp.swift` (app entry) | modify | `.onOpenURL` handler to parse `https://xomify.xomware.com/invite/<code>` and stash code for Friends screen consumption |
| `Xomify-iOS/Services/NavigationStore.swift` or new `InviteCoordinator` | modify / create | Hold "pending deep-link invite code" so the Friends screen can pick it up after auth |
| `Xomify-iOS/Tests/FriendsViewModelTests.swift` (new under `Xomify-iOS/Tests/`) | create | VM tests: load buckets, invite mint, invite accept/decline, remove confirmation gating |
| Info.plist / entitlements | modify | Associated Domains entitlement `applinks:xomify.xomware.com` (only if Universal Link path is chosen — flagged) |

Out-of-tree (flagged, not authored here):
- `apple-app-site-association` at `xomify.xomware.com/.well-known/` — hosted by xomify-frontend/AWS, not this repo.
- Backend `invites_pending` (GET list) and optionally `invites_decline` (POST) lambdas — land in a follow-up backend PR if not already deployed.

## Implementation Steps

- [ ] **Step 0 — confirm backend shape**: read `xomify-backend/api/invites_create/handler.py` and `invites_accept/handler.py` to verify request/response fields match `InviteCreateResponse` / `InviteAcceptResponse` in `SocialModels.swift`. Note gaps: no `GET /invites/pending`, no decline endpoint. Decide path (new backend lambda vs client-only decline) before coding.
- [ ] **Step 1 — model additions**: extend `Xomify-iOS/Models/SocialModels.swift` with `PendingInvite` struct (Codable, Sendable, Identifiable by `inviteCode`) and `PendingInvitesResponse`. camelCase to match backend convention.
- [ ] **Step 2 — service surface**: in `Xomify-iOS/Services/XomifyService.swift` under `// MARK: - Social`, add `listPendingInvites(email:) async throws -> PendingInvitesResponse` (GET `/invites/pending?email=`) and `declineInvite(email:, inviteCode:) async throws -> SuccessResponse` (POST `/invites/decline`). If the backend endpoints don't exist, stub to throw a clearly-named error and flag in Open Questions; do **not** fake the data.
- [ ] **Step 3 — VM state**: add to `FriendsViewModel`:
  - `@MainActor var incomingInvites: [PendingInvite] = []`
  - `@MainActor var lastMintedInvite: URL?`
  - `@MainActor var isMintingInvite = false`
  - Methods: `mintInvite() async`, `acceptInvite(_: PendingInvite) async`, `declineInvite(_: PendingInvite) async`, and load invites inside the existing `load(email:)` via `async let`.
- [ ] **Step 4 — remove-friend confirmation**: in `FriendsView.swift` friends list, replace the direct `Task { await viewModel.remove(friend) }` button action with `.confirmationDialog("Remove \(friend.label)?", ...)` that calls `viewModel.remove` only on confirm.
- [ ] **Step 5 — Invite a Friend CTA**: add a trailing toolbar `Menu` (or secondary button beside the refresh button) with label "Invite". Behavior: call `viewModel.mintInvite()`; once `lastMintedInvite` is set, present a `ShareLink(item: url, subject: Text("Join me on Xomify"), message: Text("..."))` programmatically. Use `.sheet(isPresented:)` gating for clean presentation state.
- [ ] **Step 6 — Invites tab**: extend `FriendsView.Tab` enum with `.invites = "Invites"`. Add `invitesList` view: empty state ("No pending invites"), loading state, and rows rendering `PendingInvite` with Accept (`Color.xomifyGreen`) / Decline buttons. Accept triggers `viewModel.acceptInvite(invite)`, which on success should optimistically move the sender into `accepted`.
- [ ] **Step 7 — badge counts**: update `badgedTitle(_:)` to show invite counts (e.g. `Invites (2)`).
- [ ] **Step 8 — deep-link handler**: in `XomifyApp.swift` (or the root scene), add `.onOpenURL { url in InviteCoordinator.shared.handle(url) }`. Implement `InviteCoordinator` (new file under `Services/` or `Utilities/`) to parse `/invite/<code>` from `xomify.xomware.com`; store `pendingInviteCode`. FriendsView listens (via `@Environment` or shared `@Observable`) and auto-routes to Invites tab + shows accept prompt once user is authenticated.
- [ ] **Step 9 — Universal Link entitlement** (if Universal Link path chosen): add `com.apple.developer.associated-domains` entitlement with `applinks:xomify.xomware.com` in `Xomify-iOS.entitlements`. Verify with `xcrun swcutil dl -d xomify.xomware.com`. If AASA hosting is not ready, fall back to a custom scheme `xomify://invite/<code>` with `CFBundleURLTypes` in Info.plist — flag the switch in Open Questions.
- [ ] **Step 10 — tests**: add `Xomify-iOS/Tests/FriendsViewModelTests.swift` (note new location — `XomFitTests/` is purged). Cover: `mintInvite` success + failure, `acceptInvite` moves invite to accepted list, `declineInvite` removes row, `load` populates invites bucket. Use a mock `XomifyService` via protocol extraction if VM currently hard-references the singleton (may require adding a `XomifyServicing` protocol — scope this small).
- [ ] **Step 11 — build + smoke**: `xcodebuild -scheme Xomify-iOS -sdk iphonesimulator build`, then launch sim and manually verify: drawer → Friends → Invite tap mints URL → share sheet appears → paste URL in Messages to self → tap link → app opens on Invites tab.
- [ ] **Step 12 — PR**: branch `feature/30-friends-management`, single PR to `master`, commits prefixed `#30 ...`, PR body includes `Closes #30`. No Co-Authored-By lines.
- [ ] **Step 13 — board update**: move XomBoard item #30 Up Next → In Progress at start, → In Review on PR, → Done on merge; post completion comment summarizing shipped surfaces.

## Out of Scope

- Backend `invite_create` / `invite_accept` lambda implementation — epic sub-feature 3. (If `invites_pending` / `invites_decline` need authoring, it's a follow-up backend PR tracked separately — do **not** bundle here.)
- Feed empty-state "Invite a friend" CTA — lives in sub-feature 5 (`ios-feed`) and reuses this `XomifyService.createInvite` surface.
- Angular parity on invites flow — sub-feature 10.
- Per-invite expiry countdown UI, resend, revoke — post-launch hardening.
- Push notification on invite accept — epic sub-feature 4 covers notifications generally.
- Bulk invite, contact-picker integration — deferred.
- Search-by-phone / SMS invite channel — deferred; share sheet already covers SMS implicitly.

## Risks / Tradeoffs

- **Universal Link hosting dependency**: if `apple-app-site-association` is not live at `xomify.xomware.com`, invite URLs open in the browser instead of the app. Mitigation: ship custom-scheme fallback (`xomify://invite/<code>`) behind a compile-time check; promote to Universal Links once AASA is verified. Accept one-TestFlight-build lag.
- **`invite_accept` idempotency unknown**: if the backend returns 409 on already-friends, client must gracefully treat as success and still remove the invite row. If it's idempotent, no extra work. Flagged.
- **No backend "list pending invites" endpoint confirmed**: if the backend only has `create` + `accept`, we cannot render an inbound invites list without a new lambda. Two paths: (a) add `invites_pending` lambda in a parallel backend PR (preferred, cleanest), (b) derive "pending invites" as "friend requests" via the existing `friends_pending` endpoint (fallback, but it confuses the "deep-link invite" vs "in-app friend request" mental model). Flagged.
- **Stale epic language**: epic PLAN.md describes `FriendsView` as a placeholder. It isn't. Risk: future contributors re-read the epic and rebuild what exists. Mitigation: this sub-feature's PR updates the epic's sub-feature #7 description once merged.
- **Sharing a URL before the app handles it**: if a user invites a friend before AASA/custom-scheme is wired, the friend lands on a 404. Mitigation: backend-shares sub-feature should ship a lightweight landing page at the invite URL ("Open in Xomify / Download on the App Store"). Track separately; flag as dependency.
- **Share sheet cancellation UX**: if user dismisses the share sheet, the invite code is still minted server-side and persists for 30 days. Accepted cost; don't attempt to revoke on dismiss.

## Open Questions

- [ ] **Final invite URL scheme** — `https://xomify.xomware.com/invite/<code>` (tentative, pending Dom sign-off). Confirm domain choice vs the epic's prior `https://xomify.app/invite/<code>` — which host will actually serve the AASA file? Blocks Step 9.
- [ ] **Universal Link vs custom scheme** — does `xomify.xomware.com` have `apple-app-site-association` published? If no, do we block this sub-feature on getting it served, or ship custom-scheme first and upgrade later?
- [ ] **`invites_accept` semantics on already-friends** — does the backend return 409 / raise an error, or idempotent no-op? Affects `FriendsViewModel.acceptInvite` error handling (should-we-toast vs silently-dedupe).
- [ ] **Backend list-pending-invites endpoint** — does it exist? If not, are we authorized to author `invites_pending` in a parallel backend PR, or must we derive from `friends_pending`? Blocks Step 2, Step 6.
- [ ] **Backend decline-invite endpoint** — is `POST /invites/decline` deployed or does decline stay client-side (just drops from local list; invite code remains valid until expiry)? Affects Step 2.
- [ ] **Invite landing page** — if the recipient doesn't have the app installed, what does the invite URL render? Out of scope to build here but needs to exist before we ship the share CTA to real users. Coordinate with xomify-frontend or backend-shares.

## Skills / Agents to Use

- **ios-engineer**: primary authoring of view / VM / service / coordinator changes. Knows the `@Observable` + `@MainActor` + async/await conventions per `.claude/rules/ios.md`.
- **test-writer**: pair on `FriendsViewModelTests.swift`, especially protocol extraction for `XomifyServicing` to enable mocking.
- **code-reviewer**: run on the PR before merge; pay attention to strict-concurrency warnings and force-unwrap avoidance.
- **backend-engineer**: consult (not author here) if `invites_pending` / `invites_decline` need adding to xomify-backend — they'd be a separate PR blocking Step 2.
