# Plan: ios-ia-parity

**Epic**: [xomify-relaunch](https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md)
**Sub-feature ID**: C1 (`ios-ia-parity`)
**Track**: C — iOS Parity + Visual Overhaul
**Status**: BLOCKED — premise is wrong, do not execute as written
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

---

## BLOCKED — the plan's premise does not survive contact with the code

**Do not run the deletions in this plan.** They were derived from web commit `ea5d391`
("Fold Xomtracks into xomify, replacing feed + groups") on the assumption that iOS's Feed
and web's deleted feed were the same feature. They are not.

### What is actually true

| | Web | iOS |
|---|---|---|
| Native xomify shares API (`shares_create`, `shares_feed`, `shares_react`, `shares_comments_*`) | still used — `share-feed.service.ts`, `share-card`, `comment-thread`, `/share/:shareId`, `my-profile` | used by the whole Feed feature |
| A page that BROWSES native shares | **none.** `ShareFeedService.getFeed()` exists but no component calls it | `FeedView` |
| Xomtracks (`api.xomtracks.xomware.com`, `GET /shares/list`) | `/shares` — a **separate product**, own API, own models, own services | **does not exist** — no client, and `Config.swift` knows only `XOMIFY_API_URL` |

So `ea5d391` removed web's native *browsing surface* and gave the "Shares" nav slot to
Xomtracks, a different backend. It did **not** delete the native share primitives.

### Why executing this plan would be destructive

Deleting `FeedView` for "parity" removes iOS's only surface for browsing native shares,
and iOS has nothing to replace it with. Web at least still reaches individual shares via
`/share/:shareId` and a user's own posts via `my-profile`. iOS would simply lose the
feature — the opposite of "take iOS to the next level".

### Knock-on effects

- **C3, C4, C5** all depend on C1 and are therefore blocked behind this decision.
- **B8** lists C1 as a dependency (deep-link routes need settled destinations). The routes
  themselves are fine — `share:<id>` resolves on both clients — but B8 cannot finalise the
  iOS destination list until this is settled.
- **Track B is unaffected in substance.** All the share notification kinds target the
  *native* shares API, which both clients still use. Web deep links land on
  `/share/:shareId`, which exists.

### Options (needs a decision)

1. **Delete Groups only; keep FeedView.** iOS keeps native-shares browsing. Accepts that
   iOS and web diverge on this one surface, which they already do in fact.
2. **Delete Feed and port Xomtracks to iOS.** True parity, but it is a new feature build
   against a second backend — its own epic, not a parity edit.
3. **Delete Feed, replace with a profile-scoped shares surface** mirroring what web's
   `my-profile` actually shows. Smaller than 2, and closes the gap without a second API.
