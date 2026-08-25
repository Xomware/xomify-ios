# Plan: ios-component-rebuild

**Epic**: [xomify-relaunch](https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md)
**Sub-feature ID**: C3 (`ios-component-rebuild`)
**Track**: C — iOS Parity + Visual Overhaul
**Status**: Done (builds Debug + Release; visually unverified)
**Created**: 2026-08-24
**Last updated**: 2026-08-24
**Scope size**: TBD — run `/plan ios-component-rebuild` to size
**Repo(s) touched**: `xomify-ios`
**Branch**: `feature/ios-component-rebuild`
**Wave**: 2
**Depends on**: `C1`, `C2`

---

## Summary

Rebuild shared components against the token layer.

## Approach

Cards, chips, sheets, list rows, buttons, empty states, loaders. Kill hardcoded corner radii and paddings. AmbientBackground.swift becomes a space background matching web A1. Depends on C1 — do not restyle components you are about to delete.

## Affected Files / Components

- `Xomify-iOS/Views/Shared/`
- `Xomify-iOS/Views/Shared/AmbientBackground.swift`

## Implementation Steps

_Stub — not yet planned. Run `/plan ios-component-rebuild` to expand this into ordered, checkable steps._

- [ ] TBD

## Acceptance

_Stub — define with `/plan ios-component-rebuild`._

---

## Epic context

Locked decisions live in the epic plan and must not be re-litigated here. See
`https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md` — decisions table, rows 1-11.

---

## Outcome

Debug and Release both **BUILD SUCCEEDED**. **Zero hardcoded corner radii remain** anywhere
in `Xomify-iOS/`.

| Change | Scope |
|--------|-------|
| `AmbientBackground` → `SpaceBackground` | replaced, matching web A1's `ambient` intensity |
| Radius tokens applied | 32 files, 114 lines |
| Shared components on spacing tokens | `Views/Shared/` |

### SpaceBackground

Mirrors the web component's **`ambient`** variant only. The `full` variant — parallax
layers, shooting stars — belongs to the signed-out landing page, which has no iOS
counterpart.

Cheap by construction: the starfield is a single `Canvas` drawn from a deterministic seed.
One draw pass, no per-star views, and **no `TimelineView`** redrawing behind the entire app.
Only the two nebula clouds animate, on 42- and 55-second cycles.

**The seeded PRNG is load-bearing, not tidiness.** `Canvas` redraws on every layout pass, so
`Double.random` inside the draw closure would reshuffle the whole sky each time — the
background would visibly twitch whenever anything above it resized. Foundation has no
seedable generator, hence the small SplitMix64.

Star alpha is capped at 0.30. This layer sits behind list rows and dense stats screens; the
moment it reads as "stars" rather than texture, it is competing with the content.

### Radius mapping

Derived from `_tokens.scss`'s own note that the ramp went 4/8/12/20/24 → 3/6/8/12/16.
Off-scale values round to the nearest **new** rung rather than inventing one:

| Was | Now | | Was | Now |
|-----|-----|-|-----|-----|
| 3, 4 | `sm` (3) | | 16, 18, 24 | `xxl` (16) |
| 6, 8 | `md` (6) | | 22, 25, 26, 28, 30, 999 | `pill` |
| 10 | `lg` (8) | | | |
| 12, 14, 20 | `xl` (12) | | | |

Button-sized values (22–30) map to `pill` rather than a corner rung — a pill is a shape, not
a corner treatment, which is why `_tokens.scss` left it out of the tightening.

Every radius in the codebase was covered; nothing was left unmapped.

---

## ⚠️ Visually unverified

**The corner tightening is a deliberate, app-wide visual change across 114 sites, and a
green build says nothing about whether it looks right.** Web shipped the same tightening
(`b491175 sync tightened radius scale`), so the direction is consistent — but iOS had far
more off-scale values than web did, and the 10 → 8 and 20 → 12 moves in particular touch a
lot of cards.

`SpaceBackground` is likewise unverified on a device: star density, alpha ceiling and nebula
opacity were chosen against the web values and reasoning, not against a screen.

This needs a real device pass, which is C5.
