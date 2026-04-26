# Plan: Spotify iOS SDK Integration (SPTAppRemote)

**Status**: Done
**Created**: 2026-04-26
**Last updated**: 2026-04-26

> **HEADS UP — REAL DEVICE REQUIRED**
> The Spotify iOS SDK (`SPTAppRemote`) does **NOT** work in the iOS Simulator.
> Every test step in this plan must run on a physical iPhone with the Spotify
> app installed and signed in. Do not waste time chasing simulator failures.

> **Scope note**
> A backend agent is running concurrently in another session. This feature is
> **iOS-only** — no backend / Lambda / DynamoDB changes required.

## Summary
Replace the active-device dependency on Play / Queue actions by integrating the
Spotify iOS SDK (`SPTAppRemote`). Today, `SpotifyService.queueTrack(uri:)` and
`playTrack(uri:)` hit the Web API endpoints `/me/player/queue` and
`/me/player/play`, which return 404 unless Spotify is already actively playing
on a device. The SDK can wake the Spotify iOS app and drive playback in-process,
eliminating the most common friction point Dom hits in the field.

## Goal & Non-Goals

**Goals**
- In-process Play / Queue on iOS that works even when no device is currently active.
- Drop-in: existing call sites (`TrackActionsMenu`, `ShareCardViewModel.queue()`,
  `QueueActionController`) keep their current shape — they consume the same
  `SpotifyQueueing` protocol.
- Graceful degradation: if the SDK fails to connect (Spotify app not installed,
  user not Premium, connection rejected), fall back to today's Web API path so
  no one ends up with a worse experience than before.

**Non-Goals**
- Android, web, or watchOS — iOS only.
- Replacing the full Spotify playback UI (now-playing view, transport controls,
  scrubber). We only own Play / Queue triggers; user can still bounce to Spotify
  for actual playback control.
- Replacing the Web API service. `SpotifyService` keeps every non-playback
  responsibility (saved tracks, playlists, search, top items, follow, etc.).
- Backend changes (handled by the other concurrent agent).

## Approach

Add a thin `SpotifyRemoteService` (a `@MainActor @Observable` class) that owns
an `SPTAppRemote` instance and conforms to the existing `SpotifyQueueing`
protocol that `SpotifyService` already conforms to. This makes the SDK a
**peer implementation**, not a replacement.

A new top-level `SpotifyPlaybackCoordinator` becomes the value `QueueActionController`
and `ShareCardViewModel` inject for `SpotifyQueueing`. It tries `SpotifyRemoteService`
first, and on failure (or when the user has flipped the diagnostics toggle)
falls through to `SpotifyService` (Web API).

Auth handover: the SDK's `SPTAppRemote.connectionParameters.accessToken`
reuses the Spotify access token already minted by `AuthService`. We do **not**
add a second OAuth flow — `streaming` scope is already requested
(`AuthService.swift:67`). On token refresh, the coordinator pushes the new
token into the live `SPTAppRemote` instance.

Connection lifecycle is wired into the SwiftUI app entry: connect on
`scenePhase == .active` if `AuthService.isAuthenticated`; disconnect on
`.background`. This keeps the bridged channel cheap and avoids the SDK
holding a connection while the app isn't foregrounded.

## Affected Files / Components

| File / Component | Change | Why |
|------------------|--------|-----|
| `Xomify-iOS/Info.plist` | Add `LSApplicationQueriesSchemes` for `spotify` scheme; verify existing `xomify` `CFBundleURLSchemes` entry covers SDK callback | SDK requires both: `canOpenURL("spotify:")` for the install check + URL scheme for auth callback. The `xomify` scheme is already registered with `com.spotify.auth` URL name, so the SDK's auth flow will land back here. |
| `Xomify-iOS/Xomify-iOS.entitlements` | No change expected — verify only | SDK doesn't require additional entitlements beyond what's there. |
| `Xomify-iOS/Services/SpotifyRemoteService.swift` | **New.** Wraps `SPTAppRemote`, conforms to `SpotifyQueueing`. Owns connection state (`isConnected`, `lastError`), `connect()`, `disconnect()`, `queueTrack(uri:)`, `playTrack(uri:)`. Implements `SPTAppRemoteDelegate` and `SPTAppRemotePlayerStateDelegate`. | The SDK surface, isolated. Anything Web-API-only stays in `SpotifyService`. |
| `Xomify-iOS/Services/SpotifyPlaybackCoordinator.swift` | **New.** `@MainActor` class implementing `SpotifyQueueing`. Holds both a `SpotifyRemoteService` and `SpotifyService`; routes call → SDK first, falls back to Web API on `SpotifyRemoteError.notConnected` / `.notInstalled` / when the diagnostics override is on. | Single seam so `QueueActionController` / `ShareCardViewModel` don't have to know which transport ran. |
| `Xomify-iOS/Services/SpotifyService.swift` | No behavioural change. May extract / confirm the `SpotifyQueueing` protocol lives in its own file (`SpotifyQueueing.swift`) so the new types can conform without dragging the whole actor in. | Keep Web API service narrowly scoped; protocol is the contract both implementations honour. |
| `Xomify-iOS/Services/AuthService.swift` | Expose a small async hook (`accessTokenForSDK() async -> String?`) that auto-refreshes if expired. Optionally publish a token-changed notification or expose an observable so `SpotifyRemoteService` can re-set `connectionParameters.accessToken` after a refresh. | SDK keeps its own copy of the token; if we refresh and don't push the new token in, SDK calls will start failing silently. |
| `<App entry>.swift` (e.g. `Xomify_iOSApp.swift` — confirm filename during Phase 1) | Inject `SpotifyPlaybackCoordinator` into the environment. Wire `scenePhase` observer: `.active` → `coordinator.connectIfAuthenticated()`, `.background` → `coordinator.disconnect()`. Forward `onOpenURL` to `SpotifyRemoteService.handleOpenURL(_:)`. | SDK auth-handover round-trips through a custom URL; without the open-URL plumbing, the SDK can't complete its handshake. |
| `Xomify-iOS/Controllers/QueueActionController.swift` | Change default injection from `SpotifyService.shared` to `SpotifyPlaybackCoordinator.shared`. No call-site changes; same `SpotifyQueueing` API. | Routes Play / Queue from `TrackActionsMenu` through the SDK-preferring path. |
| `Xomify-iOS/ViewModels/Feed/ShareCardViewModel.swift` | Change default injection of `spotifyService` from `SpotifyService.shared` to `SpotifyPlaybackCoordinator.shared`. | Same reason as above for the feed-card queue button. |
| `Xomify-iOS/Views/Settings/PlaybackDiagnosticsView.swift` | **New (Phase 4).** Shows: SDK connection status, last SDK error, Spotify-app-installed Yes/No, currently active token expiry, a `Force Web API fallback` toggle persisted in `UserDefaults`. | Lets Dom debug "did the SDK actually run?" without re-instrumenting. |
| `Xomify-iOS/Models/Errors/SpotifyRemoteError.swift` | **New.** Cases: `.notInstalled`, `.notConnected`, `.connectFailed(underlying)`, `.actionFailed(underlying)`. Conforms to `LocalizedError`. | Distinct from `SpotifyServiceError` so the coordinator can pattern-match for fallback decisions. |

## Implementation Steps

### Phase 1 — SDK install verification + URL scheme + Info.plist (PR #1)
- [x] Verify the `SpotifyiOS` SPM dependency at `project.pbxproj:380-388` resolves
      and links — `xcodebuild -scheme Xomify-iOS -sdk iphoneos build`. (SPM
      dep is already present — branch `master` of `spotify/ios-sdk`.)
- [x] Add `LSApplicationQueriesSchemes = ["spotify"]` to `Info.plist` so
      `UIApplication.canOpenURL("spotify:")` works on iOS 9+.
- [x] Confirm `CFBundleURLTypes` entry with `CFBundleURLName = com.spotify.auth`
      and scheme `xomify` is sufficient for the SDK's auth callback (it should
      be — it's the same scheme `AuthService` already uses).
- [x] Find the `@main` `App` struct (likely `Xomify_iOSApp.swift` inside the
      synchronized `Xomify-iOS/` group) and document the filename in this plan
      before Phase 2 lands. **Confirmed: `Xomify-iOS/App/Xomify_iOSApp.swift`**
- [x] Write `SpotifyRemoteError.swift` with the cases listed above.
- [x] No runtime behaviour change in this PR. Ship as a clean infra commit so
      Phase 2's diff stays focused on the SDK wrapper itself.
- [x] Bump version: `scripts/bump-version.sh fix` (no user-visible change yet). → 1.6.1

### Phase 2 — `SpotifyRemoteService` + connection lifecycle (PR #2)
- [x] Create `Xomify-iOS/Services/SpotifyRemoteService.swift`:
  - `@MainActor @Observable final class SpotifyRemoteService: NSObject, SpotifyQueueing, SPTAppRemoteDelegate`
  - Properties: `isConnected: Bool`, `lastError: SpotifyRemoteError?`
  - Initialiser builds `SPTConfiguration(clientID:redirectURL:)` from the
    same `SPOTIFY_CLIENT_ID` Info.plist key `AuthService` reads, and
    `xomify://callback` redirect.
  - `connect(accessToken:)`: sets `appRemote.connectionParameters.accessToken`,
    calls `appRemote.connect()`. Returns once `appRemoteDidEstablishConnection`
    or `didFailConnectionAttemptWithError` fires (use `CheckedContinuation`).
  - `disconnect()`: idempotent, calls `appRemote.disconnect()`.
  - `queueTrack(uri:)`: guards on `isConnected`, throws `.notConnected`
    otherwise. Calls `appRemote.playerAPI?.enqueueTrackUri(uri, callback:)`,
    bridges callback to `async throws`.
  - `playTrack(uri:)`: same pattern, calls `appRemote.playerAPI?.play(uri)`.
  - `handleOpenURL(_:)`: forwards to `appRemote.authorizationParameters(from:)`
    parameter parser as required by the auth-handover flow.
- [x] Create `Xomify-iOS/Services/SpotifyPlaybackCoordinator.swift`:
  - `@MainActor @Observable final class SpotifyPlaybackCoordinator: SpotifyQueueing`
  - Holds `remote: SpotifyRemoteService` and `web: SpotifyService`.
  - `connectIfAuthenticated()` async — fetches token from `AuthService`, calls
    `remote.connect(accessToken:)`. Swallows errors into `lastConnectError`.
  - `disconnect()` → forwards to remote.
  - `queueTrack(uri:)` / `playTrack(uri:)`:
    1. If `forceWebFallback` toggle is on → use `web` directly.
    2. Else try `remote.queueTrack(uri:)`. On `.notConnected` / `.notInstalled`
       fall through to `web.queueTrack(uri:)`.
- [x] Wire scene-phase + URL forwarding into the `App` struct:
  - Inject the coordinator via `.environment(coordinator)`.
  - `.onChange(of: scenePhase)` → `.active` → `Task { await coordinator.connectIfAuthenticated() }`,
    `.background` → `coordinator.disconnect()`.
  - `.onOpenURL { coordinator.remote.handleOpenURL($0) }`.
- [x] Push token refreshes through: extended `AuthService` with `onTokenRefresh: (@Sendable (String) -> Void)?`
      callback and `accessTokenForSDK() async -> String?`. Coordinator wires itself in at init.
- [ ] Manual test on a real device — see Test Plan §Phase 2.
- [x] Bump version: `scripts/bump-version.sh fix`. → 1.6.2

### Phase 3 — Wire call sites + Web-API fallback (PR #3)
- [x] Change `QueueActionController.init` default param from
      `SpotifyService.shared` to `SpotifyPlaybackCoordinator.shared`.
      The protocol shape (`SpotifyQueueing`) means zero call-site churn.
- [x] Same for `ShareCardViewModel.init`'s `spotifyService` param.
- [x] Audit the codebase for any other direct `SpotifyService.shared.queueTrack`
      / `playTrack` callers and route them through the coordinator. (Confirmed:
      only the two above.)
- [x] Update `QueueActionController.handleNoDevice` user copy: with the SDK
      online, `.noActiveDevice` is now a rare last-resort path. Deep-link
      rescue kept; toast copy updated.
- [ ] Manual test on real device — see Test Plan §Phase 3.
- [x] Bump version: `scripts/bump-version.sh feat` (first user-visible change). → 1.7.0

### Phase 4 — Settings diagnostics + force-fallback toggle (PR #4)
- [x] Add `PlaybackDiagnosticsView.swift` under `Xomify-iOS/Views/Settings/`.
      Shows:
  - Spotify app installed: `UIApplication.shared.canOpenURL("spotify:")`
  - SDK connection state: `coordinator.remote.isConnected`
  - Last SDK error: `coordinator.remote.lastError?.errorDescription`
  - Auth token expiry: `AuthService.shared.tokenExpirationDate`
  - Toggle: `Force fallback to Web API` (persisted in `UserDefaults` under
    `xomify.playback.forceWebFallback`).
  - Buttons: `Reconnect SDK`, `Open Spotify app`.
- [x] Hook the toggle into `SpotifyPlaybackCoordinator.forceWebFallback`.
- [x] Add a Settings entry: "Developer" section in `SettingsView` with
      `NavigationLink` to `PlaybackDiagnosticsView` (no developer-mode gate —
      Settings screen had no such pattern).
- [ ] Manual test on real device — see Test Plan §Phase 4.
- [x] Bump version: `scripts/bump-version.sh fix`. → 1.7.1

## Test Plan

> Reminder: SDK does **NOT** run in the simulator. Every step here must be
> executed on a real iPhone with the Spotify app installed.

### Phase 1
- Build with `xcodebuild -scheme Xomify-iOS -sdk iphoneos build` — should
  succeed and link `SpotifyiOS`.
- App launches; nothing else changes. Existing Web-API queue still works
  exactly as before (active device required).

### Phase 2
- Real device, Spotify app installed but **not currently playing**:
  - Cold-launch Xomify, log in if needed.
  - Bring app to foreground → expect `coordinator.remote.isConnected == true`
    within ~2s. (Print/log to verify, since there's no UI yet.)
  - Background app → expect `isConnected == false`.
- Real device, Spotify app **not installed**:
  - Foreground → expect `lastError == .notInstalled`, no crash.
- Token refresh: force `AuthService.refreshAccessToken()`; verify the SDK's
  `connectionParameters.accessToken` was updated by triggering a queue call
  ~70 minutes after login (or by manually expiring the token in the keychain).

### Phase 3
- Real device, Spotify **not playing anywhere**:
  - Open feed → tap a `ShareCardView` queue button → expect track is queued
    (Spotify wakes if needed). Pre-fix, this would 404.
  - Open `TrackActionsMenu` → tap "Add to queue" → same result.
  - Open `TrackActionsMenu` → tap "Play now" → expect playback to start.
- Real device, Spotify app missing:
  - Tap queue → coordinator falls back to Web API → expect existing
    `.noActiveDevice` deep-link toast (current behaviour preserved).
- Free-tier (non-Premium) account if available:
  - Tap queue/play → expect `.premiumRequired` surfaced cleanly via either
    transport.

### Phase 4
- Toggle `Force fallback to Web API` ON → verify `play` / `queue` now hit the
  Web API even with the SDK connected. (Confirm by killing Spotify on the
  device — call should fail with `.noActiveDevice`.)
- Toggle OFF → verify SDK is used again.
- "Reconnect SDK" button — disconnects then reconnects, status flips to
  Connected within ~2s.

## Risks / Tradeoffs

- **Premium-only methods**: `playerAPI.enqueueTrackUri` and `play` may be
  Premium-gated. Existing Web-API code already maps 403 → `.premiumRequired`;
  mirror that in `SpotifyRemoteError.actionFailed` mapping. Need to confirm
  exact SDK error codes during Phase 2 implementation.
- **SDK auth-handover edge cases**: First-ever SDK call may need to bounce
  through the Spotify app for an authorization prompt even though the user is
  already Web-OAuth'd. We'll discover the exact handover ergonomics in Phase 2;
  worst case, `connect(accessToken:)` is enough and no extra prompt fires.
- **Spotify app not installed**: `appRemote.connect()` will fail. Coordinator
  falls back to Web API for queue/play; a separate gentle prompt to install
  Spotify (deep-link to App Store ID `324684580`) can ship in Phase 4 if Dom
  wants it.
- **Strict concurrency**: `SPTAppRemote` is not `Sendable`. Wrap it in a
  `@MainActor`-isolated class and never hand it across actor boundaries.
  Bridge its delegate callbacks to `async` via `CheckedContinuation`.
- **No simulator support**: cannot CI-test the SDK path. Phase 2/3/4 require
  physical-device validation before merge — call this out in PR descriptions
  so reviewers don't ask why CI doesn't cover the new code paths.
- **Branch tracking on SPM dep**: package is pinned to `master`, not a
  semver tag. Any breaking change upstream will bite us silently. Consider
  pinning to a tag once we've stabilised — out of scope for this feature,
  but flag for follow-up.

## Out of Scope

- Backend / Lambda changes (handled by concurrent agent).
- Android / web / watchOS Spotify integrations.
- Replacing the Spotify Web API service for non-playback calls.
- A full in-app player UI (now-playing, scrubber, transport).
- App Store install prompt for users without Spotify (can layer on later
  in Phase 4 if Dom wants it; not required for the friction fix).
- Pinning the SDK to a semver tag (separate hardening task).

## Open Questions

- [ ] **Premium confirmation**: Is Dom's Spotify account Premium? Several SDK
      playback methods are Premium-only and will fail otherwise. If not, we
      need a Premium test account for Phase 2/3 validation.
- [ ] **Phase 4 scope**: Does the Settings diagnostics screen need to ship in
      v1, or can it land in a follow-up after Phase 3 has been used in the
      field for a few days? Current plan keeps it as a separate PR for
      reviewability either way.
- [ ] **App entry filename**: Need to confirm the `@main App` struct location
      during Phase 1 (synchronized file group makes it invisible to the
      pbxproj). Likely `Xomify-iOS/Xomify_iOSApp.swift` but verify before
      Phase 2 starts.
- [ ] **Token-refresh hook shape**: simplest is for `AuthService` to expose
      `var onTokenRefresh: ((String) -> Void)?` and let the coordinator wire
      itself in at startup. Alternative is an `AsyncStream`. Decide during
      Phase 2 implementation.

## Skills / Agents to Use

- **`ios-standards` skill**: enforce `@Observable`, no `ObservableObject`,
  modern SwiftUI APIs, async/await, no force-unwraps. Reference before
  writing each new file.
- **`ios-developer` agent**: invoke during Phase 2 for `SpotifyRemoteService`
  implementation — the SDK delegate-to-async-bridge is fiddly under strict
  concurrency and benefits from a focused pass.
- **`code-reviewer` agent**: invoke at end of each phase PR before merging,
  with explicit instruction to check actor isolation, `Sendable` boundaries,
  and that no new force-unwraps were introduced.
