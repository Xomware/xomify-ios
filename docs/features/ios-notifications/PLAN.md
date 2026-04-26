# Plan: Xomify Social Feed — ios-notifications

**Epic**: [xomify-social-feed](../xomify-social-feed/PLAN.md)
**Sub-feature ID**: 9 (`ios-notifications`)
**Issue**: #32
**Status**: Ready
**Created**: 2026-04-22
**Last updated**: 2026-04-23
**Scope size**: M
**Repo(s) touched**: `xomify-ios`
**Branch**: `feat/ios-notifications`
**Depends on**: 2 (`ios-nav-shell`), 4 (`backend-interactions-and-notifications`), 7 (`ios-friends-management` — provides `NavigationStore.requestDeepLink`), 8 (`ios-drawer-residents` — provides `@AppStorage` toggle stubs in Settings)

---

## Summary

Wire the iOS client into the already-shipped backend notifications surface: request APNs permission at a value-moment trigger (post-first-share or post-first-accepted-invite), register device tokens with `/notifications/register`, handle push-open deep links via the existing `NavigationStore.requestDeepLink` pipeline, and back the Settings-drawer toggles (`queueNotificationsEnabled` / `digestEnabled`) with real upsert calls. Unregister on sign-out. Success = a share-threshold push lands on a real device, tapping it routes to the share, and flipping the digest toggle in Settings patches the backend.

## Approach

Backend endpoints are live (PR #131 + infra PR #70 merged). The iOS work is the client half: permission, registration, delegate plumbing, deep-link dispatch, and settings parity. No silent-push or badge-count complexity in v1 — keep the surface small.

Key moves:

1. Introduce an `AppDelegate` via `@UIApplicationDelegateAdaptor` on `Xomify_iOSApp` (the app currently has no delegate) so we can hook `didRegisterForRemoteNotificationsWithDeviceToken`, `didFailToRegisterForRemoteNotificationsWithError`, and `didReceiveRemoteNotification` (for future silent pushes — not wired v1).
2. Create a `NotificationsService` actor that owns the permission flow, token hex encoding, register/unregister calls, and foreground/didReceive handlers. It conforms to `UNUserNotificationCenterDelegate`.
3. Extend `XomifyServicing` + `XomifyService` with `registerPushToken` / `unregisterPushToken` that POST to `/notifications/register` and `/notifications/unregister` with the payload the backend lambda expects.
4. Trigger the permission prompt from two value-moment call sites — first successful `createShare` and first `acceptInvite` / first accepted friend request — gated by a `@AppStorage("hasPromptedForPush")` flag so we only ever prompt once.
5. Bind Settings-drawer toggles (`queueNotificationsEnabled`, `digestEnabled`, already stubbed in `@AppStorage`) to a `SettingsViewModel` method that calls `registerPushToken` (upsert) with the updated flags whenever either changes.
6. On sign-out, call `unregisterPushToken` before clearing local auth state.
7. Handle push-open payloads in `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)`: parse `customData.route`, pass the raw string to `NavigationStore.requestDeepLink`. The existing pipeline (from ios-friends-management) already knows how to parse `"share:<id>"` and `"invite:<code>"`.
8. Foreground presentation: `willPresent` inspects the payload's push type. Queue-threshold pushes → `[.banner, .sound]`. Digest pushes → `[]` (silent in-app). Use a `customData.pushType` string (`"queueThreshold"` | `"digest"`), fallback to `[.banner, .sound]` if unrecognized.
9. Add APNs capability to the project: flip on **Push Notifications** in Xcode Signing & Capabilities (writes to pbxproj automatically via Xcode UI — no manual edits), add `aps-environment` to `Xomify-iOS.entitlements` with value `$(APS_ENVIRONMENT)`, and add a build setting `APS_ENVIRONMENT` = `development` for Debug, `production` for Release.
10. Defer: silent pushes (`remote-notification` background mode), badges.

## Critical decisions inherited from epic (do not re-litigate)

- **APNs cert model**: Auth Key lives in AWS Secrets Manager on the backend (actually SSM SecureString at `/xomify/apns/*`, populated by Dom via `APNS_SIGNING_KEY_P8` / `APNS_KEY_ID` / `APNS_TEAM_ID` repo secrets — client-side doesn't care).
- **Weekly fixed-UTC digest**: client does not collect `digestTime`; `DigestPreferences` is `digestEnabled` + `queueNotificationsEnabled` only.
- **MVVM constraint**: views never touch `XomifyService` directly — `SettingsViewModel` mediates.
- **No Co-Authored-By** in commits. Single PR to master from `feat/ios-notifications`.

## Pre-answered open questions (flag for Dom, ready to proceed unless overridden)

1. **Permission prompt trigger timing** — **after first completed share OR first accepted friend invite**, whichever comes first. Gated by `@AppStorage("hasPromptedForPush")`. Rationale: user sees product value before we ask. Prompt at first-launch = reflexive deny. Flag.
2. **`aps-environment` strategy** — single `Xomify-iOS.entitlements` file with `$(APS_ENVIRONMENT)` variable + per-configuration build settings (`APS_ENVIRONMENT` = `development` for Debug, `production` for Release). Avoids maintaining two entitlements files; Apple's APNs infrastructure accepts the matching environment per build config. Flag.
3. **Silent pushes (content-available) in v1** — **no**. No `remote-notification` background mode. Digest is visible user-facing push only. Defer silent-push infra until we have a real use case (e.g. badge refresh or background feed prefetch). Flag.
4. **Badge count strategy v1** — **no badges**. Backend isn't tracking unread counts; implementing client-only badges leads to drift. Defer until backend exposes an unread counter. Flag.

## Affected Files / Components

| File / Component | Change | Why |
|-----------------|--------|-----|
| `Xomify-iOS/App/Xomify_iOSApp.swift` | modify | add `@UIApplicationDelegateAdaptor(XomifyAppDelegate.self)`, inject `NotificationsService` into environment |
| `Xomify-iOS/App/XomifyAppDelegate.swift` | new | `UIApplicationDelegate` — forwards APNs token / registration errors to `NotificationsService`; sets `UNUserNotificationCenter.current().delegate` |
| `Xomify-iOS/Services/NotificationsService.swift` | new | `@MainActor` class conforming to `NSObject, UNUserNotificationCenterDelegate`. Owns permission request, token lifecycle, foreground handling, push-open dispatch into `NavigationStore.requestDeepLink` |
| `Xomify-iOS/Services/XomifyService.swift` | extend | add `registerPushToken(email:deviceToken:queueNotificationsEnabled:digestEnabled:)` and `unregisterPushToken(email:deviceToken:)` |
| `Xomify-iOS/Services/XomifyServicing.swift` | extend | protocol signatures for the two new methods, to keep mockability |
| `Xomify-iOS/Models/XomifyModels.swift` (or `Models/NotificationModels.swift`) | extend | `DeviceTokenRegistration` (request body), `DeviceTokenUnregister`, `DigestPreferences`, `PushPayload` (for decoding `customData`) |
| `Xomify-iOS/Views/Social/ShareComposerView.swift` (or its VM) | extend | on successful `createShare`, invoke `NotificationsService.requestPermissionIfNeeded()` if `hasPromptedForPush == false` |
| `Xomify-iOS/Views/Social/FriendsView.swift` + friends/invite acceptance flow | extend | on first accepted invite / first accepted friend request, invoke `NotificationsService.requestPermissionIfNeeded()` (same gate) |
| `Xomify-iOS/ViewModels/SettingsViewModel.swift` (new or extend existing) | new/extend | binds `@AppStorage` toggles to `registerPushToken` upsert calls |
| `Xomify-iOS/Views/Settings/SettingsView.swift` | modify | wire existing stubbed toggles through `SettingsViewModel`; show permission-denied affordance ("Open system settings") when `UNAuthorizationStatus == .denied` |
| `Xomify-iOS/Auth/AuthService.swift` (sign-out path) | modify | call `NotificationsService.unregister()` before clearing credentials |
| `Xomify-iOS/Navigation/NavigationStore.swift` | read-only | consumes `requestDeepLink(_:)` from ios-friends-management; no changes |
| `Xomify-iOS/Xomify-iOS.entitlements` | modify | add `aps-environment` = `$(APS_ENVIRONMENT)` |
| Xcode project (Signing & Capabilities, build settings) | modify via Xcode UI | enable Push Notifications capability; add `APS_ENVIRONMENT` user-defined build setting (Debug=`development`, Release=`production`) |
| `XomFitTests` → `XomifyTests/NotificationsServiceTests.swift` | new | unit tests for token hex, payload parsing, permission-prompt gate, register/unregister call shapes |
| `XomifyTests/SettingsViewModelTests.swift` | new | toggle flip triggers `registerPushToken` with correct flags |

## Implementation Steps

Ordered. Each step is self-contained enough to commit individually if we want granular history.

### Phase 1 — Project capability + entitlements

- [ ] Step 1 — In Xcode, select the `Xomify-iOS` target → Signing & Capabilities → click `+ Capability` → add **Push Notifications**. Verify `Xomify-iOS.entitlements` is created/updated with `aps-environment` key.
- [ ] Step 2 — Open `Xomify-iOS.entitlements` in source view. Replace the hard-coded `aps-environment` string value with `$(APS_ENVIRONMENT)`. Commit the file.
- [ ] Step 3 — In Build Settings → User-Defined, add `APS_ENVIRONMENT`. Set `Debug` = `development`, `Release` = `production`. Screenshot the settings for the PR description.
- [ ] Step 4 — Verify build succeeds for both Debug and Release on simulator and device: `xcodebuild -scheme Xomify-iOS -sdk iphonesimulator -configuration Debug build` and `... -configuration Release build`.

### Phase 2 — AppDelegate wiring

- [ ] Step 5 — Create `Xomify-iOS/App/XomifyAppDelegate.swift`. Implement `UIApplicationDelegate` with `application(_:didFinishLaunchingWithOptions:)` (set `UNUserNotificationCenter.current().delegate = NotificationsService.shared`) and `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` + `application(_:didFailToRegisterForRemoteNotificationsWithError:)` forwarding to `NotificationsService`.
- [ ] Step 6 — In `Xomify_iOSApp`, add `@UIApplicationDelegateAdaptor(XomifyAppDelegate.self) var appDelegate`. Inject `NotificationsService.shared` and `NavigationStore` into the environment.

### Phase 3 — Models

- [ ] Step 7 — Add `DeviceTokenRegistration`, `DeviceTokenUnregister`, `DigestPreferences` Codable structs. `DeviceTokenRegistration = { email, deviceToken, queueNotificationsEnabled, digestEnabled }`.
- [ ] Step 8 — Add `PushPayload` Codable with nested `customData: { route: String?, pushType: String? }` — tolerate missing fields. Route strings: `"share:<shareId>"`, `"invite:<code>"`. `pushType` values: `"queueThreshold"`, `"digest"`.

### Phase 4 — Service surface

- [ ] Step 9 — Extend `XomifyServicing` protocol with `registerPushToken(email:deviceToken:queueNotificationsEnabled:digestEnabled:) async throws -> SuccessResponse` and `unregisterPushToken(email:deviceToken:) async throws -> SuccessResponse`.
- [ ] Step 10 — Implement both in `XomifyService` hitting `POST /notifications/register` and `POST /notifications/unregister`. Mirror body shape in `notifications_register/handler.py` (confirm before merging — TODO note in PR description).
- [ ] Step 11 — Mirror in `MockXomifyService` so VM tests can observe calls.

### Phase 5 — NotificationsService

- [ ] Step 12 — Create `Xomify-iOS/Services/NotificationsService.swift`. `@MainActor final class NotificationsService: NSObject, UNUserNotificationCenterDelegate`. Singleton `shared`. Dependencies: `XomifyServicing`, `NavigationStore`, `AuthServicing` (for current email), `UserDefaults` (for `hasPromptedForPush` + cached token).
- [ ] Step 13 — `requestPermissionIfNeeded() async` — reads `UserDefaults.hasPromptedForPush`; if true, no-op. Else calls `UNUserNotificationCenter.requestAuthorization(options: [.alert, .sound])`, sets flag regardless of grant, and if granted calls `UIApplication.shared.registerForRemoteNotifications()` on main.
- [ ] Step 14 — `handleDeviceToken(_ data: Data) async` — hex-encode token, cache in UserDefaults, fetch current email + prefs, call `registerPushToken`. Retry once on network failure, then give up silently (not fatal).
- [ ] Step 15 — `handleRegistrationFailure(_ error: Error)` — log via existing logger, do not surface to user.
- [ ] Step 16 — `updatePreferences(queueNotificationsEnabled:digestEnabled:) async` — re-POSTs to `/notifications/register` (upsert) using cached token + current email. Called from `SettingsViewModel`.
- [ ] Step 17 — `unregister() async` — called on sign-out. Uses cached token + email, calls `unregisterPushToken`, clears cached token from UserDefaults. Swallow errors (user is leaving anyway).
- [ ] Step 18 — Implement `userNotificationCenter(_:willPresent:withCompletionHandler:)`. Parse `PushPayload`. If `pushType == "digest"`, return `[]`. Else return `[.banner, .sound]`.
- [ ] Step 19 — Implement `userNotificationCenter(_:didReceive:withCompletionHandler:)`. Parse `customData.route`. Pass string to `NavigationStore.requestDeepLink`. Call completion handler unconditionally.

### Phase 6 — Trigger points

- [ ] Step 20 — In the share-composer flow (likely `ShareComposerViewModel` from sub-feature 5) after successful `createShare`, fire-and-forget `Task { await NotificationsService.shared.requestPermissionIfNeeded() }`.
- [ ] Step 21 — In the friends-accept flow (from sub-feature 7) after a successful `acceptInvite` / `acceptFriend`, fire the same `requestPermissionIfNeeded()` call. The shared `@AppStorage` flag prevents double-prompting.
- [ ] Step 22 — In `AuthService.signOut()`, call `await NotificationsService.shared.unregister()` before clearing tokens / user defaults.

### Phase 7 — Settings integration

- [ ] Step 23 — Create `SettingsViewModel` (or extend existing). Expose `queueNotificationsEnabled` and `digestEnabled` as `@AppStorage`-backed state mirrored onto `@Observable` fields. On either flip, call `NotificationsService.shared.updatePreferences(...)`.
- [ ] Step 24 — Update `SettingsView` to bind its toggles to the VM (remove direct `@AppStorage` usage from the view per MVVM rule).
- [ ] Step 25 — Add a "Notifications permission" row in Settings. When `UNAuthorizationStatus == .denied`, show "Open System Settings" button that deep-links to `UIApplication.openSettingsURLString`. When `.notDetermined`, hide the toggles or show a "Enable notifications to use these" disabled state. When `.authorized`, show toggles live.

### Phase 8 — Tests

- [ ] Step 26 — `NotificationsServiceTests`: token hex encoding (known bytes → known hex string), `PushPayload` decoding for both route shapes and both push types, `requestPermissionIfNeeded` gate (only prompts once).
- [ ] Step 27 — `SettingsViewModelTests`: toggling `queueNotificationsEnabled` calls `updatePreferences` on the mock, `digestEnabled` same.
- [ ] Step 28 — `XomifyServiceTests` (extend existing pattern): `registerPushToken` hits correct path with correct body keys; `unregisterPushToken` same.
- [ ] Step 29 — Confirm full suite: `xcodebuild -scheme Xomify-iOS -sdk iphonesimulator test`.

### Phase 9 — Manual verification (post-merge, before release)

- [ ] Step 30 — On a real device (simulator cannot receive real APNs): build Debug, grant permission, verify `/notifications/register` returns 200 via Charles/backend logs.
- [ ] Step 31 — Have a friend-cohort member hit queue-threshold on one of your shares; verify push arrives within ~1 minute; tap it; verify app lands on the correct share.
- [ ] Step 32 — Toggle `digestEnabled` off in Settings; verify the Sunday 18:00 UTC digest does not fire to that device.
- [ ] Step 33 — Sign out; verify `/notifications/unregister` returns 200 and no further pushes arrive.

## Out of Scope

- Backend APNs send / threshold / cron — sub-feature 4 (already live).
- APNs auth key / Secrets population — Dom handles via repo secrets; iOS client does not read APNs secrets.
- The "queued by N" chip rendering on share cards — sub-feature 5.
- Universal-link invite consumption flow — sub-feature 7.
- Silent pushes (`content-available` / `remote-notification` background mode) — deferred, see Open Questions.
- Badge counts — deferred, no backend counter.
- Android / other platforms — this app is iOS-only.
- Per-user digest time selection — epic locked answer, weekly fixed UTC only.
- Notification settings view for individual categories (future UNNotificationCategory work).

## Risks / Tradeoffs

- **Permission denial blocks the whole feature**: if user denies, we cannot re-prompt. Mitigation: Settings shows a "Open System Settings" button when `.denied`. Toggles visually disabled.
- **Token rotation**: APNs tokens rotate on app reinstall, device restore, or Apple's schedule. Since `didRegisterForRemoteNotificationsWithDeviceToken` fires on every launch where remote notifications are registered, we upsert on every cold launch when signed-in. Accepted cost: one extra POST per launch. Backend `notifications_register` is idempotent upsert.
- **AppDelegate introduction**: swapping from pure SwiftUI lifecycle to a hybrid `UIApplicationDelegateAdaptor` increases surface area. Mitigation: keep `XomifyAppDelegate` tiny — forward-only, no business logic.
- **Deep-link coupling to ios-friends-management**: this sub-feature depends on `NavigationStore.requestDeepLink` shipping in sub-feature 7. If 7 slips, we either ship a stub `requestDeepLink` here or block. Mitigation: confirm 7 has merged before starting.
- **Sign-out race**: if `unregisterPushToken` fails (network down), we leave a stale token on the backend. Accepted: backend token expires when APNs reports it invalid on next send attempt.
- **Entitlement environment mismatch**: if `APS_ENVIRONMENT` is wrong for the build (e.g. `production` on a sandbox build), APNs silently fails. Mitigation: Phase 1 Step 4 build both configs; document in PR.
- **No silent-push v1**: means the digest arrives only when the user opens the app or as a visible banner. Accepted — simpler MVP.

## Open Questions

All four are pre-answered above; they are surfaced here so Dom can veto before execution.

- [ ] Confirm permission trigger = first-share OR first-accepted-invite. Alternative: prompt from Settings first time user taps the notifications section.
- [ ] Confirm `$(APS_ENVIRONMENT)` single-entitlements-file approach vs per-configuration entitlements files.
- [ ] Confirm silent pushes are out of scope v1.
- [ ] Confirm no badge counts v1.
- [ ] Verify `NavigationStore.requestDeepLink(_:)` signature is stable in the ios-friends-management PR before implementing Phase 5 Step 19 — if the signature takes a typed enum instead of a raw string, adjust Step 8's `PushPayload` parsing accordingly.
- [ ] Confirm exact `/notifications/register` + `/notifications/unregister` request body keys against `/Users/dom/Code/xomify-backend/lambdas/notifications_register/handler.py` before merging — key casing (camelCase vs snake_case) must match.

## Skills / Agents to Use

- **ios-engineer**: core implementation (AppDelegate, NotificationsService, service extensions, Settings wiring).
- **test-writer**: XCTest coverage for `NotificationsServiceTests`, `SettingsViewModelTests`, `XomifyServiceTests` extensions.
- **code-reviewer**: pre-merge pass on the single PR — focus areas are the AppDelegate ↔ SwiftUI integration, the token-lifecycle happy + error paths, and the entitlements/build-setting changes.
