# Plan: ios-design-tokens

**Epic**: [xomify-relaunch](https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md)
**Sub-feature ID**: C2 (`ios-design-tokens`)
**Track**: C — iOS Parity + Visual Overhaul
**Status**: Done
**Created**: 2026-08-24
**Last updated**: 2026-08-24
**Scope size**: TBD — run `/plan ios-design-tokens` to size
**Repo(s) touched**: `xomify-ios`
**Branch**: `feature/ios-design-tokens`
**Wave**: 1
**Depends on**: _nothing — can start immediately_

---

## Summary

Port the Xomware token ramp into a Swift DesignTokens enum.

## Approach

Port `xomify-frontend/src/styles/_tokens.scss`: type ramp, 8px spacing grid, 3/6/8/12/16/pill radii, motion curves. ColorExtensions and FontExtensions already exist and stay as the colour/type source — tokens add the spacing and radius half that is currently ad-hoc. Generated port with the source hash in a header comment, same convention the SCSS file already carries. Sync stays one-directional from xomware-frontend.

## Affected Files / Components

- `Xomify-iOS/Utilities/DesignTokens.swift (new)`

## Implementation Steps

_Stub — not yet planned. Run `/plan ios-design-tokens` to expand this into ordered, checkable steps._

- [ ] TBD

## Acceptance

_Stub — define with `/plan ios-design-tokens`._

---

## Epic context

Locked decisions live in the epic plan and must not be re-litigated here. See
`https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md` — decisions table, rows 1-11.

---

## Outcome

`Xomify-iOS/Utilities/DesignTokens.swift` — ported from `_tokens.scss`, source hash
`201003166470` recorded in the header. Verified: `xcodebuild -scheme Xomify-iOS
-sdk iphonesimulator` **BUILD SUCCEEDED**.

Spacing, radius and breakpoint values are literal ports and cross-check exactly against
the SCSS. Colour and type deliberately stay where they already were
(`ColorExtensions.swift`, `FontExtensions.swift`) — the SCSS file keeps colour out too,
and duplicating the palette here would create a second source of truth.

**One non-literal port**: `$transition-spring` is a cubic-bezier with overshoot on the
web (`cubic-bezier(0.34, 1.56, 0.64, 1)`). `XomMotion.spring` is a SwiftUI spring instead.
Matching the numbers rather than the feel would be the wrong kind of fidelity — a timed
curve does not behave like a native spring under interruption.

Added `xomCard()` and `xomPill()` view modifiers so C3 has something to rebuild
components *onto*, rather than each call site re-deriving padding and radius.
