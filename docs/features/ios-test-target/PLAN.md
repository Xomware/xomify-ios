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

## The isolated-deinit crash — diagnosed and FIXED

The host app was aborting during teardown:

```
malloc: *** error for object 0x…: pointer being freed was not allocated
  SettingsViewModel.__deallocating_deinit
  swift_task_deinitOnExecutorMainActorBackDeploy
  swift_task_deinitOnExecutorImpl
  swift::TaskLocal::StopLookupScope::~StopLookupScope()
```

**Result: 8 crashes per run.** All 53 tests passed, but only across 8 forced relaunches, and
`xcodebuild` exited non-zero.

### Root cause

`@MainActor` classes get a synthesised **isolated deinit**, which back-deploys through
`swift_task_deinitOnExecutorMainActorBackDeploy`. That shim calls
`swift_task_deinitOnExecutorImpl`, which tears down a `TaskLocal::StopLookupScope` — and
that **assumes a surrounding task context**.

A synchronous `XCTest` method has none. It runs on the main thread inside an `NSInvocation`
with no task, so releasing a `@MainActor` view model at the end of the method corrupted the
heap.

The tell was that the crash was never class-specific: removing `@MainActor` from
`ShareCardViewModel` simply moved it to `SettingsViewModel`.

### Fix

**Make the test methods `async`.** That gives the deinit a task context to unwind in. 21
test methods converted across 6 suites.

| | Before | After |
|---|--------|-------|
| Crashes | 8 | **0** |
| Passing | 53 | **61** |
| Exit | `TEST EXECUTE FAILED` | **`TEST EXECUTE SUCCEEDED`** |

More tests pass afterwards because fewer suites were being aborted mid-run.

**No production code changed.** The view models keep their `@MainActor` isolation, which is
correct — the bug was in how the tests released them, not in the app.

### Ruled out along the way

| Hypothesis | Result |
|-----------|--------|
| `Starfield` static cache | Real data race, fixed — but not this crash |
| `@Observable` on `NotificationsService` | Crash persists without it |
| Test parallelism | `-parallel-testing-enabled NO`: persists |
| `ShareCardViewModel`'s `@MainActor` | Crash just moves to the next `@MainActor` class |
| Deployment target below iOS 18 | Raised to 18.0 with a clean build: persists |

### CI

`|| true` is now gone from **both** steps, and the failure-count workaround is deleted — a
non-zero exit is a real failure again.

## Caveat: new test files must be added to the target

The two app targets use Xcode 16 `PBXFileSystemSynchronizedRootGroup`, which picks files up
from disk automatically. The `xcodeproj` gem cannot create that group type, so the test
target uses classic explicit file references. **A newly added test file will not compile
until it is added to the target** (Xcode does this automatically when you create the file
inside the group).
