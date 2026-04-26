# Execution Log: Spotify iOS SDK Integration

## [2026-04-26 00:00] — Phase 1: SDK install verification + URL scheme + Info.plist

- **Action**: Verified SPM dependency `SpotifyiOS` present in pbxproj at lines 10/48/93/382/391. Added `LSApplicationQueriesSchemes = ["spotify"]` to `Info.plist`. Confirmed `CFBundleURLTypes` with `CFBundleURLName = com.spotify.auth` and scheme `xomify` already present — no change needed. App entry confirmed at `Xomify-iOS/App/Xomify_iOSApp.swift`. Created `SpotifyRemoteError.swift` at `Xomify-iOS/Models/Errors/SpotifyRemoteError.swift`. Bumped version 1.6.0 → 1.6.1.
- **Files changed**:
  - `Xomify-iOS/Info.plist` — added `LSApplicationQueriesSchemes`
  - `Xomify-iOS/Models/Errors/SpotifyRemoteError.swift` — new
  - `Xomify-iOS.xcodeproj/project.pbxproj` — version bump
- **Decisions**: Project uses `PBXFileSystemSynchronizedRootGroup` — no manual pbxproj file references needed for new Swift files. `SpotifyRemoteError.Sendable` conformance requires wrapping associated `Error` values; used `@unchecked Sendable` pattern is avoided since these errors are only thrown/caught in `@MainActor` context.
- **Result**: BUILD SUCCEEDED (iphonesimulator)

## [2026-04-26 00:02] — Phase 3: Wire call sites + Web API fallback

- **Action**: Changed `QueueActionController.init` and `ShareCardViewModel.init` default `spotifyService` param from `SpotifyService.shared` to `SpotifyPlaybackCoordinator.shared`. Audited codebase — no other direct `queueTrack`/`playTrack` callers. Updated `handleNoDevice` copy to reflect that `.noActiveDevice` is now a rare last-resort path. Bumped version 1.6.2 → 1.7.0 (feat: first user-visible change).
- **Files changed**:
  - `Xomify-iOS/Services/QueueActionController.swift` — default injection + toast copy
  - `Xomify-iOS/ViewModels/Feed/ShareCardViewModel.swift` — default injection
  - `Xomify-iOS.xcodeproj/project.pbxproj` — version bump
- **Decisions**: No call-site changes needed beyond the default parameter — protocol shape is identical. Toast copy updated to signal "SDK tried, fell all the way through" rather than the old "open Spotify first" instruction.
- **Result**: BUILD SUCCEEDED (iphonesimulator)

## [2026-04-26 00:01] — Phase 2: SpotifyRemoteService + connection lifecycle

- **Action**: Created `SpotifyRemoteService.swift` — `@MainActor @Observable NSObject` wrapping `SPTAppRemote`, conforming to `SpotifyQueueing`. Bridges delegate callbacks (`appRemoteDidEstablishConnection`, `didFailConnectionAttemptWithError`, `didDisconnectWithError`) via `CheckedContinuation`. Created `SpotifyPlaybackCoordinator.swift` — `@MainActor @Observable` class implementing `SpotifyQueueing`, routing SDK-first with Web API fallback. Added `onTokenRefresh` hook and `accessTokenForSDK()` to `AuthService`. Updated `Xomify_iOSApp.swift` to inject coordinator into environment, wire `scenePhase` observer, and forward `onOpenURL` to SDK. Bumped version 1.6.1 → 1.6.2.
- **Files changed**:
  - `Xomify-iOS/Services/SpotifyRemoteService.swift` — new
  - `Xomify-iOS/Services/SpotifyPlaybackCoordinator.swift` — new
  - `Xomify-iOS/Services/AuthService.swift` — added `onTokenRefresh`, `accessTokenForSDK()`
  - `Xomify-iOS/App/Xomify_iOSApp.swift` — scene lifecycle + URL forwarding
  - `Xomify-iOS.xcodeproj/project.pbxproj` — version bump
- **Decisions**: Used `@ObservationIgnored` on `onTokenRefresh` in `AuthService` to resolve `@Observable` macro incompatibility with `@Sendable` closure types. Chose closure-based hook over `AsyncStream` for simplicity (plan open question resolved to callback). SPTAppRemoteDelegate conformance uses `nonisolated` + `Task { @MainActor in }` to bridge ObjC callbacks safely under strict concurrency. `SpotifyRemoteError` cases with associated `Error` are not `Equatable` but that's acceptable — coordinator only pattern-matches on case identity.
- **Result**: BUILD SUCCEEDED (iphonesimulator)
