# Plan: ios-component-rebuild

**Epic**: [xomify-relaunch](https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md)
**Sub-feature ID**: C3 (`ios-component-rebuild`)
**Track**: C — iOS Parity + Visual Overhaul
**Status**: Draft
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
