# Plan: Xomify Social Feed — repo-cleanup

**Epic**: [xomify-social-feed](../xomify-social-feed/PLAN.md)
**Sub-feature ID**: 1 (`repo-cleanup`)
**Status**: Done
**Created**: 2026-04-22
**Last updated**: 2026-04-22
**Scope size**: S
**Repo(s) touched**: `xomify-ios`
**Depends on**: none

---

## Summary

Purge the stray `Xomfit/` tree (a fitness-app sibling that has no business in this repo, ~40 staged files including tests, watchOS target, Lottie animations, and its own `.xcodeproj`) from both working tree and index, harden `.gitignore` so it cannot re-leak, and prove `Xomify-iOS.xcodeproj` still builds clean. Ships as a single PR to `master`. Blocks every other sub-feature in the epic.

## One-liner (from epic)

> Purge stray `Xomfit/` tree, unstage ~40 files, `.gitignore` hygiene.

## Approach

Straight delete + gitignore. No salvage — `Xomfit/` is tracked in its own `xomfit-ios` repo and nothing in `Xomify-iOS.xcodeproj` references it (verified: the xcodeproj uses a `PBXFileSystemSynchronizedRootGroup` scoped to `Xomify-iOS/` only). Execute as one branch, one commit, one PR.

## Critical decisions inherited from epic (do not re-litigate)

- **Scope override**: full-throttle delivery; this is the unblocking prerequisite for all parallel work downstream. See epic `Critical decisions already locked` #4.
- **File-level target set**: all of `Xomfit/` (~40 staged files) plus `.gitignore` entries. See epic `iOS file/folder changes → Files deleted (repo-cleanup)`.

## What's being deleted

Grounded in `git status --short` at planning time. All groups live under `Xomfit/`:

| Group | Path | Approx count | Notes |
|-------|------|--------------|-------|
| Sibling xcodeproj | `Xomfit/Xomfit.xcodeproj/project.pbxproj` | 1 | Shows as `AA` (add/add unmerged) in status — needs special handling |
| Watch app target | `Xomfit/XomFitWatch/` | 7 | `LogSetView.swift`, `RestTimerView.swift`, `WatchConnectivityManager.swift`, `WatchWorkoutManager.swift`, `WorkoutControlView.swift`, `XomFitComplication.swift`, `XomFitWatchApp.swift` |
| Unit tests | `Xomfit/XomFitTests/` | ~26 | `AICoachTests`, `AuthServiceTests`, `BodyCompositionTests`, `ChallengeTests`, `HealthKitTests`, `PRCalculatorTests`, `WatchConnectivity/WatchConnectivityManagerTests.swift`, etc. |
| UI tests | `Xomfit/XomFitUITests/` | 1+ | `AuthUITests.swift` (verify inside sub-feature whether more files exist) |
| Lottie animations | `Xomfit/Xomfit/Assets/Animations/` | 6+ visible | `barbell_row.json`, `bench_press.json`, `deadlift.json`, `dumbbell_bench_press.json`, `incline_dumbbell_press.json`, `lat_pulldown.j...` (list truncated in snapshot — enumerate full set at execute time) |
| Xomfit app source | `Xomfit/Xomfit/**` | unknown | Snapshot truncated; enumerate at execute time |

Total: ~40 staged files per the git-status header. Final tally to be confirmed with `git status --short | grep '^.. Xomfit/' | wc -l` as the first execute step.

## Affected Files / Components

| File / Component | Change | Why |
|-----------------|--------|-----|
| `Xomfit/**` (entire tree) | delete | unrelated fitness-app bleed-in, not referenced by `Xomify-iOS.xcodeproj` |
| `Xomfit/Xomfit.xcodeproj/project.pbxproj` | delete + resolve `AA` | shows as unmerged add/add; needs `git rm --force` or explicit stage-then-delete |
| `.gitignore` | append | prevent recurrence if sibling repo gets cloned into this tree |

## Implementation Steps

All steps run from repo root `/Users/dom/Code/xomify-ios`. Do NOT execute during planning — execute-only.

- [x] **Step 1 — snapshot baseline**. Capture `git status --short > /tmp/repo-cleanup-before.txt` so we can diff after. Record the exact Xomfit file count: `git status --short | grep ' Xomfit/' | wc -l`. Expect ~40.
- [x] **Step 2 — confirm no xcodeproj references**. Run `grep -rn "Xomfit" Xomify-iOS.xcodeproj/` and `grep -rn "XomFit" Xomify-iOS.xcodeproj/`. Expected: zero matches. If anything returns, stop and escalate before deleting.
- [x] **Step 3 — branch**. `git checkout -b chore/repo-cleanup-xomfit-purge` off `master`.
- [x] **Step 4 — resolve the `AA` (unmerged add/add) on the sibling pbxproj**. N/A — `Xomfit/` was entirely untracked on master; no git rm needed for pbxproj.
- [x] **Step 5 — remove the rest of the tree from the index and working copy**. N/A — all Xomfit files were untracked; no index entries to remove.
- [x] **Step 6 — belt-and-suspenders filesystem sweep**. `python3 shutil.rmtree('Xomfit/')` — removed 6 files (`.DS_Store` artifacts and Xcode workspace metadata).
- [x] **Step 7 — update `.gitignore`**. Append a new section at the end of `/Users/dom/Code/xomify-ios/.gitignore`:
  ```gitignore
  # Sibling project guard — never track XomFit (fitness app lives in xomfit-ios repo)
  Xomfit/
  XomFit/
  Xomfit.xcodeproj/
  XomFit.xcodeproj/
  XomFitWatch/
  XomFitTests/
  XomFitUITests/
  ```
  Stage with `git add .gitignore`.
- [x] **Step 8 — status check**. `git status --short` shows only `M .gitignore`. No `AA`, no `??`, no residual `Xomfit/` untracked files.
- [x] **Step 9 — build verification**. `xcodebuild -scheme Xomify-iOS clean build` — **BUILD SUCCEEDED** (12s).
- [x] **Step 10 — commit**. Single commit: `chore: purge stray Xomfit tree and harden gitignore` (SHA 6d97333).
- [x] **Step 11 — push + PR**. Pushed branch, opened PR #24: https://github.com/Xomware/xomify-ios/pull/24
- [x] **Step 12 — board hygiene**. No XomBoard issue exists for this task; no `Closes #N` added per plan instruction.

## Out of Scope

- Any changes to the Xomify-iOS source tree itself (handled by downstream sub-features `ios-nav-shell` and beyond).
- Any work in `xomify-backend` or `xomify-frontend`.
- Rewriting git history to expunge `Xomfit/` from prior commits. Deleted files remain retrievable from history; that's fine and matches epic risk note.
- Touching `xomfit-ios` (the sibling's actual home repo).

## Risks / Tradeoffs

- **Unmerged `AA` pbxproj requires explicit handling**: `git rm -r Xomfit/` alone won't resolve the unmerged add/add entry. Mitigated by step 4 (`git rm -f` on that specific path first).
- **Snapshot truncation at plan time**: `git status` in the planning context was cut at 2k chars, so the file list here under `Xomfit/Xomfit/` and `Xomfit/Xomfit/Assets/Animations/` is incomplete. Mitigated by step 1 (re-enumerate at execute time) and step 5 (`git rm -r Xomfit/` catches everything regardless of plan-time enumeration).
- **Hidden xcodeproj references**: risk that something inside `Xomify-iOS.xcodeproj` points at `Xomfit/`. Verified at plan time — `PBXFileSystemSynchronizedRootGroup` is scoped to `Xomify-iOS/` only, no `Xomfit` string appears in the pbxproj header. Step 2 re-verifies at execute time as a safety net.
- **Leaked build artifacts**: derived data / `*.xcuserstate` / `DerivedData/` are already gitignored (see existing `.gitignore` lines 12–15). Low risk.
- **Git history retention**: deleted files remain in prior commits. Acceptable — if the Xomfit project ever needs recovery, it's already in its own repo plus retrievable from this repo's history.
- **Build verification false-positive**: `xcodebuild clean build` passing proves compile but not runtime. Acceptable for a pure deletion PR — no behavior is changing.

## Open Questions

- [ ] Is there a tracking issue on XomBoard for this cleanup, or should the PR ship without `Closes #N`? Per org rules, don't invent an issue number — confirm with Dom during execute.
- [ ] Should we add a CODEOWNERS or pre-commit check to prevent any future `Xomfit/` or `XomFit/` paths from being committed? Out of scope for this sub-feature but worth capturing for a follow-up hygiene pass.

## Skills / Agents to Use

- **ios-engineer agent**: drive steps 1–9 (enumeration, deletion, gitignore edits, build verification). Low-complexity pass — no Swift changes, just repo hygiene.
- **code-reviewer agent**: run on the PR before merge. Confirm no `Xomfit/` paths remain, `.gitignore` patterns are sane and non-overreaching, and build log is attached.
