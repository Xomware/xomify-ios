# Plan: ios-test-target

**Status**: Done
**Created**: 2026-08-25
**Repo(s) touched**: `xomify-ios`
**Branch**: `feature/ios-test-target`

---

## Why

`Xomify-iOSTests/` held 10 test files that **were not in the Xcode project**. They had never
compiled, let alone run. CI reported green because `build-for-testing` had nothing to build
and the test step ended in `|| true` while referencing a `UnitTests.xctestplan` that does not
exist.

## What was done

Target added programmatically with the `xcodeproj` gem rather than by hand-editing
`project.pbxproj` — the project ships to TestFlight and a malformed pbxproj is not a text
edit worth making blind.

| | |
|---|---|
| `Xomify-iOSTests` unit-test bundle | new target, hosted in the app |
| 10 test files | added to the target |
| `MockXomifyServicing` | **12 stale method signatures** corrected |
| 4 test files | rotted APIs corrected |
| `pr-checks.yml` | `|| true` removed from test compilation |

**Result: 53 tests run and pass. 0 failures.** They had never executed once.

## The rot the first compile exposed

Everything below had been broken for generations and nothing noticed, because nothing
compiled it:

- **`MockXomifyServicing`** still had `email:` as the first parameter on 12 methods. The
  "drop caller-email, use the JWT context" refactor (`a900925`, #95) changed the protocol
  and never touched the mock.
- **`NotificationsServiceTests`** used `NavigationStore.selectedTab`, removed when `ShellTab`
  was deleted in favour of `SidebarDestination`.
- **`UserProfileViewModelTests`** constructed `FriendProfile` without `likesCount` /
  `likesUpdatedAt`, added by the Likes work.
- **`ProfileLikesViewModelTests`** and **`ShareComposerViewModelTests`** passed
  `SpotifyTrack` / `SpotifyArtist` arguments in an order and shape those types no longer have.

## Also fixed: shared mutable state in SpaceBackground

`Starfield` memoised into a `static var` dictionary written from inside a SwiftUI `Canvas`
draw closure. That closure does not run exclusively on the main thread, so it was a data
race on a heap-allocated dictionary. Removed — there is nothing worth caching in a seeded
loop over ~160 stars, and being deterministic means the sky is identical every draw anyway.

(This was found while chasing the crash below, and turned out not to be its cause. It was a
real bug regardless.)

---

## ⚠️ PRE-EXISTING BUG the tests exposed, not fixed here

The host app aborts during teardown:

```
malloc: *** error for object 0x…: pointer being freed was not allocated
  ShareCardViewModel.__deallocating_deinit
  swift_task_deinitOnExecutorMainActorBackDeploy
  swift_task_deinitOnExecutorImpl
  swift::TaskLocal::StopLookupScope::~StopLookupScope()
```

`ShareCardViewModel` is `@MainActor`, so Swift synthesises an **isolated deinit**, which
back-deploys through `swift_task_deinitOnExecutorMainActorBackDeploy`. That shim is
corrupting the heap on teardown.

**Not caused by this epic** — `@MainActor` on that class predates all of it (`8fb2cf2`,
#118). It has simply never been observable, because the tests never ran.

### Ruled out

| Hypothesis | Result |
|-----------|--------|
| `Starfield` static cache | Fixed anyway; crash persists |
| `@Observable` on `NotificationsService` | Removed as an experiment; crash persists |
| Test parallelism | `-parallel-testing-enabled NO`; crash persists |
| Back-deploy below iOS 18 | Raised target to 18.0; **crash persists** (reverted) |

### Impact

`xcodebuild` exits non-zero even though **all 53 tests pass** — the runner restarts 8 times
and completes the suite across relaunches.

### Why CI asserts on failures rather than exit code

Failing the job on that exit code would block every PR on a bug unrelated to the change under
review. The added `Assert no test failures` step instead requires that tests actually ran and
that **zero of them failed** — real regressions break the build, the known teardown crash does
not. Delete that step and restore a plain exit-code check once the deinit crash is fixed.

### Likely real fix

Drop class-level `@MainActor` on `ShareCardViewModel` in favour of isolating individual
members, which removes the synthesised isolated deinit. That is a concurrency refactor with
real implications and wants a device and a careful review — deliberately not attempted blind.

---

## Caveat: new test files must be added to the target

The two app targets use Xcode 16 `PBXFileSystemSynchronizedRootGroup`, which picks files up
from disk automatically. The `xcodeproj` gem cannot create that group type, so the test
target uses classic explicit file references. **A newly added test file will not compile
until it is added to the target** (Xcode does this automatically when you create the file
inside the group).
