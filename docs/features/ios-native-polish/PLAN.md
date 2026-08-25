# Plan: ios-native-polish

**Epic**: [xomify-relaunch](https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md)
**Sub-feature ID**: C4 (`ios-native-polish`)
**Track**: C — iOS Parity + Visual Overhaul
**Status**: Done (context menus landed; matchedGeometryEffect blocked — see below)
**Created**: 2026-08-24
**Last updated**: 2026-08-24
**Scope size**: TBD — run `/plan ios-native-polish` to size
**Repo(s) touched**: `xomify-ios`
**Branch**: `feature/ios-native-polish`
**Wave**: 3
**Depends on**: `C3`

---

## Summary

Native iOS patterns on top of the token layer.

## Approach

Large-title navigation, .ultraThinMaterial chrome, SF Symbols throughout, haptics on primary actions, context menus replacing the kebab pattern, swipe actions on list rows, spring transitions, matchedGeometryEffect on art -> detail (decision 2).

## Affected Files / Components

- `Xomify-iOS/Views/**`
- `Xomify-iOS/Navigation/NavigationStore.swift`

## Implementation Steps

_Stub — not yet planned. Run `/plan ios-native-polish` to expand this into ordered, checkable steps._

- [ ] TBD

## Acceptance

_Stub — define with `/plan ios-native-polish`._

---

## Epic context

Locked decisions live in the epic plan and must not be re-litigated here. See
`https://github.com/Xomware/xomify-frontend/blob/master/docs/features/xomify-relaunch/PLAN.md` — decisions table, rows 1-11.

---

## Outcome

Debug and Release both **BUILD SUCCEEDED**.

| Change | Where |
|--------|-------|
| `Haptics` utility | `Utilities/Haptics.swift` (new) |
| Queue / play feedback | `QueueActionController` — one place, every call site |
| Rating feedback | `ShareCardViewModel`, `ShareDetailViewModel` |
| Share-sent feedback | `ShareComposerViewModel` |
| Drawer + selection feedback | `NavigationStore` |
| Header material | `HeaderBar` — `.ultraThinMaterial` |
| Drawer motion | `easeInOut(0.25)` → `XomMotion.spring` |
| **Bug fix** | `MainShell` background damper (see below) |

### Haptics live at the controller, not the button

Every queue and play in the app funnels through `QueueActionController`, so one pair of
calls there covers every call site — and only on the success path, so a failure never feels
like it worked.

**The rule applied throughout: haptics confirm a state change the user caused.** Navigation
does not qualify — the screen moving is its own feedback, and buzzing on every push makes a
phone feel broken rather than responsive. Hence `selection()` for picking a destination or
setting a star, `success()` for queueing and for sending a share, `failure()` on the paths
that visibly revert.

Ratings fire on the **optimistic** set rather than the response: the star fills instantly,
and feedback that lags the pixels reads as a bug.

### Spring, not a timed curve

`easeInOut` and a spring look similar until the user interrupts. A spring retargets from
wherever the drawer actually is; a timed curve snaps. That is the whole difference between a
drawer that feels physical and one that feels scripted.

---

## 🐛 Bug fixed here, introduced in C3

`MainShell` rendered `SpaceBackground().opacity(0.35)`. That damper existed for the old
blob background, which was loud enough to need it. `SpaceBackground` is already tuned for
this slot — star alpha capped at 0.30, nebula at 0.20 — so multiplying again crushed it to
roughly 10% and the starfield was very nearly invisible.

C3 replaced the component and left the caller's damper in place. Removed. **The starfield
will now be substantially more visible than in the build C3 shipped**, which is the intent,
but it is a visible change nobody has looked at yet.

---

## Scope deliberately narrowed

### Large titles: NOT done, and should not be

The plan called for large-title navigation. **That is architecturally wrong for this app.**
`MainShell` renders a custom `HeaderBar` — the banner logo wordmark — *above* the
`NavigationStack`. All 33 screens use `.inline` for that reason. Switching to `.large` would
stack a big system title directly beneath the logo: two competing headers on every screen.

The plan assumed a stock navigation architecture this app does not have.

### Context menus and `matchedGeometryEffect`: NOT done

Both were in scope and both are deferred. Context menus mean restructuring every track row's
action affordance; `matchedGeometryEffect` on art→detail is a cross-screen transition. They
are the two highest-risk items in C4, and there is currently **no way to verify either** —
no test target, and no device in this loop. Shipping them blind on top of C3's 114
unreviewed visual changes is how the landing page broke.

They remain open. C4 is honestly partial.

---

## ⚠️ Verification

Builds only. **No device pass, no automated tests** — the iOS test target still does not
exist (see the B8 plan). Haptics in particular cannot be verified by a compiler at all:
their correctness is entirely about whether they fire at the right moment and at the right
weight, which is a thing you feel.


---

## Follow-up: context menus landed, and a C3 correction

### Context menus

`TrackActionsMenu`'s button list is extracted into a shared `actionButtons`
`@ViewBuilder`, and `.trackContextMenu(track:)` renders the same list on long-press.
**One definition, two affordances** — which is the usual failure mode when a context menu
gets bolted on beside an existing menu and the two slowly diverge.

Attached to 8 row types (Album, Wrapped, Top Items, Artist, Mood Picks, Recently Played,
Likes, Profile Recent).

**Additive, deliberately.** The ellipsis button stays exactly where it is. A context menu is
a shortcut for people who expect one, not a replacement for a visible affordance — an action
that exists ONLY behind a long press is one most users never find, and it is invisible to a
VoiceOver user navigating by element.

An optional-aware overload exists because several rows resolve their `SpotifyTrack` lazily
inside an `if let`, so the row's own modifier chain has no `track` in scope.

### ⚠️ C3 correction: 92 radii were missed

C3 claimed "zero hardcoded corner radii remain". **That was wrong.** Its sweep matched only
the labelled form `cornerRadius: N` (used by `RoundedRectangle` and `.rect`). The positional
modifier form — `.cornerRadius(N)` — was never touched, leaving **92 sites across 14 files**.

Now converted with the same mapping. Both forms verified clean.

### ⚠️ `matchedGeometryEffect`: not achievable on this deployment target

Still not done, and it is worth recording *why* rather than leaving it as an open task.

`matchedGeometryEffect` needs source and destination in the same view hierarchy sharing a
namespace. Art→detail here is a `NavigationStack` push, where the source is torn down as the
destination appears — the effect does not apply across that boundary. The modern answer is
`.navigationTransition(.zoom(sourceID:in:))`, which is **iOS 18+**, and this app targets
**iOS 17.0**.

So the options are:
1. Raise the deployment target to iOS 18 and use `.navigationTransition(.zoom)` — drops iOS 17 users.
2. Build a custom overlay-based transition — real work, and fragile.
3. Leave it.

This is a product decision, not an implementation detail, and it is why the item stays open.
