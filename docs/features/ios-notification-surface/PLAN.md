# Plan: ios-notification-surface

**Epic**: [xomify-relaunch](https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md)
**Sub-feature ID**: B8 (`ios-notification-surface`)
**Track**: B — Notifications Platform
**Status**: Draft
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
