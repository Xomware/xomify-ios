# Plan: ios-ia-parity

**Epic**: [xomify-relaunch](https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md)
**Sub-feature ID**: C1 (`ios-ia-parity`)
**Track**: C — iOS Parity + Visual Overhaul
**Status**: Draft
**Created**: 2026-08-24
**Last updated**: 2026-08-24
**Scope size**: TBD — run `/plan ios-ia-parity` to size
**Repo(s) touched**: `xomify-ios`
**Branch**: `feature/ios-ia-parity`
**Wave**: 1
**Depends on**: _nothing — can start immediately_

---

## Summary

Align iOS information architecture with web commit ea5d391.

## Approach

Web's ea5d391 folded Xomtracks in and deleted Feed + Groups; iOS still ships both. CAREFUL: ShareComposerView and ShareDetailView are MOVED into a new Views/Shares/, not deleted — they are still needed. Remove Destination.feed and .groups; add Shares and Favorites (web has /favorites, iOS has nothing). Reconcile the drawer against web's real nav: Home / Music Taste (Songs, Artists, Genres, Likes) / Playlists (My Playlists, Builder, Analysis, Mood Picks) / Social (Friends, Invites, Shares) / Release Radar / Wrapped. groups_* lambdas stay deployed but unused — no backend change, no data migration.

## Affected Files / Components

- `Xomify-iOS/Views/Feed/ (DELETE 10, MOVE 2)`
- `Xomify-iOS/Views/Shares/ (new)`
- `Xomify-iOS/Views/GroupsView.swift (DELETE)`
- `Xomify-iOS/Views/GroupDetailView.swift (DELETE)`
- `Xomify-iOS/ViewModels/Feed/ (DELETE)`
- `Xomify-iOS/Services/FeedCacheService.swift (DELETE)`
- `Xomify-iOS/Navigation/NavigationStore.swift`

## Implementation Steps

_Stub — not yet planned. Run `/plan ios-ia-parity` to expand this into ordered, checkable steps._

- [ ] TBD

## Acceptance

_Stub — define with `/plan ios-ia-parity`._

---

## Epic context

Locked decisions live in the epic plan and must not be re-litigated here. See
`https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md` — decisions table, rows 1-11.
