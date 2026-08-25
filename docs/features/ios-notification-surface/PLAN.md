# Plan: ios-notification-surface

**Epic**: [xomify-relaunch](https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md)
**Sub-feature ID**: B8 (`ios-notification-surface`)
**Track**: B — Notifications Platform
**Status**: Done (builds Debug + Release; see the CI finding below)
**Created**: 2026-08-24
**Last updated**: 2026-08-24
**Scope size**: TBD — run `/plan ios-notification-surface` to size
**Repo(s) touched**: `xomify-ios`
**Branch**: `feature/ios-notification-surface`
**Wave**: 4
**Depends on**: `B2`, `B3`, `C1`

---

## Summary

Extend PushKind to all 14, repoint the inbox at the backend feed, rebuild Settings.

## Approach

Per-kind foreground presentation and deep-link routes. NotificationsInboxView currently reads UNUserNotificationCenter.getDeliveredNotifications and empties the moment the user clears their tray — repoint at GET /notifications with unread badge and mark-read. Settings: three sections, per-type rows, permission-denied affordance retained. Depends on C1 because deep-link routes cannot be settled until the iOS destinations are.

## Affected Files / Components

- `Xomify-iOS/Services/NotificationsService.swift`
- `Xomify-iOS/Views/Shell/NotificationsInboxView.swift`
- `Xomify-iOS/ViewModels/SettingsViewModel.swift`
- `Xomify-iOS/Views/Shell/Destinations/SettingsView.swift`

## Implementation Steps

_Stub — not yet planned. Run `/plan ios-notification-surface` to expand this into ordered, checkable steps._

- [ ] TBD

## Acceptance

_Stub — define with `/plan ios-notification-surface`._

---

## Epic context

Locked decisions live in the epic plan and must not be re-litigated here. See
`https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md` — decisions table, rows 1-11.

---

## Outcome

`PushKind` goes from 3 cases to 17. Inbox repointed at the backend. Settings gains a
per-kind screen. **BUILD SUCCEEDED** on Debug and Release.

| File | Change |
|------|--------|
| `Models/NotificationModels.swift` | 16 kinds, `route`, preference catalog, inbox models |
| `Services/NotificationsService.swift` | observable state, per-kind prefs, inbox, routing |
| `Services/XomifyService(.swift/Servicing)` | prefs map + 4 inbox methods |
| `Views/Shell/NotificationsInboxView.swift` | rewritten against `GET /notifications/feed` |
| `Views/Settings/NotificationPreferencesView.swift` | new — 16 toggles in 3 sections |
| `Views/Shell/HeaderBar.swift` | badge reads server state |
| `ViewModels/SettingsViewModel.swift` | legacy toggles route through `setPreference` |

### Decisions

- **`pushType` replaces shape inference.** The old `PushPayload` guessed the kind from
  payload shape — "has shareId, therefore queue threshold". That worked with two kinds and
  cannot work with sixteen, since most carry a shareId. B1 now sends the registry key
  explicitly. Shape inference is kept **only** as a fallback for payloads already in flight.
- **Raw values are the backend's snake_case keys**, not Swift-idiomatic camelCase. They are
  the wire contract.
- **Foreground presentation is per kind.** If the user is already in the app, anything they
  can see for themselves is noise — digest, broadcasts and the yearly favorites nudge stay
  silent; social events and drops still earn a banner.
- **Preferences are a dictionary, not sixteen properties.** The backend registry owns the
  list; a struct here would need editing for every new kind — a second source of truth that
  silently drifts.
- **Sparse writes.** Only flags the user has touched are sent, matching B2's contract.
  Sending all sixteen would freeze today's defaults onto the device row.
- **The badge reads server state, not the OS tray.** It used to count
  `deliveredNotifications()`, so it dropped to zero when the user cleared their tray, showed
  nothing for a denied user, and never reflected anything that arrived while push was muted.
- **Toggles are disabled when permission is denied** — writing a preference that can never
  take effect is misleading. The permission row says why.
- **Migration from the two-flag era**: the old `queueEnabledKey` / `digestEnabledKey`
  defaults are carried into the new map on first load, so someone who had already turned the
  digest off does not silently get it back.

---

## ⚠️ FINDING: iOS unit tests have never run

`Xomify-iOSTests/` contains 10 test files. **None of them are in the Xcode project.**
`project.pbxproj` has exactly two targets — `Xomify-iOS` and `XomifyShareExtension` — and
two `PBXFileSystemSynchronizedRootGroup` entries, neither covering the tests directory.

CI reports green anyway:

- `build-for-testing` succeeds because there are no tests to build.
- `test-without-building -testPlan UnitTests` fails immediately — the scheme has no test
  action and **no `UnitTests.xctestplan` exists anywhere in the repo** — but the step ends
  with `|| true`, so the job passes regardless.

So "Build & Test → success" on every iOS PR, including #121, has said nothing about tests.
Evidence: `MockXomifyServicing` still carried a `registerPushToken(email:...)` signature
that the protocol dropped generations ago. Dead code cannot drift unnoticed if it compiles.

**Not fixed here, deliberately.** Adding a test target means hand-editing `project.pbxproj`
for a new native target plus build phases, on a project that currently ships to TestFlight.
That is an Xcode UI operation, not a text edit to make blind.

**Recommended, in order:**
1. In Xcode, add a Unit Testing Bundle target pointing at `Xomify-iOSTests/`.
2. Create `UnitTests.xctestplan` and share the scheme (`xcshareddata/xcschemes/`) — CI
   already references both by name.
3. **Remove `|| true` from the two steps in `pr-checks.yml`.** Until that goes, the job
   cannot fail and none of the above is enforced.

`MockXomifyServicing` has been extended for the new protocol surface so it is ready when a
target exists — but it is **unverified**, because nothing compiles it.

## Consequence for this sub-feature

**B8 has no automated test coverage.** Verification is the Debug and Release builds plus the
backend's own 60 tests covering the contract this client consumes. The client half — routing,
foreground rules, sparse preference writes — is unverified until the test target exists.
