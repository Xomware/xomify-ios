# C5 — iOS QA Pass

**Status**: Not started — this one genuinely needs a device.

Everything else in the relaunch epic was verified by builds and tests. This cannot be:
every item below is a judgement about how something *looks* or *feels*, and a compiler has
no opinion on either.

Work top to bottom; the sections are ordered by how likely they are to surface something.

---

## 1. The changes nobody has looked at

These shipped verified only by a build. They are the highest-risk items on this list.

- [ ] **Corner radii.** 206 sites were retokenised across two passes (114 labelled, then 92
      positional). The scale tightened — 10→8 and 20→12 touch a lot of cards. Look at:
      Feed cards, Top Items rows, Album and Artist headers, the Wrapped grid, sheets.
      *Question: does anything now read as too square, or inconsistent with its neighbour?*
- [ ] **Starfield.** `SpaceBackground` replaced the blob background. C3 shipped it crushed
      to ~10% by a leftover `.opacity(0.35)` in `MainShell`; C4 removed that, so it is now
      **substantially more visible than anything previously seen**.
      *Question: too loud behind dense screens — Wrapped, Playlist Analysis, Ratings?*
- [ ] **Header material.** `.ultraThinMaterial` replaced a flat fill.
      *Question: does content scrolling under it read as depth, or as mud?*

## 2. Haptics

Cannot be verified any other way. Each should fire **once**, at the moment the UI changes.

- [ ] Queue a track → success tap
- [ ] Play a track → success tap
- [ ] Queue while offline / no active device → error tap, **not** success
- [ ] Set a star rating → light selection tick **as the star fills**, not after the network
- [ ] Rating fails and springs back → error tap
- [ ] Send a share → success tap
- [ ] Open the drawer → light tap; pick a destination → selection tick
- [ ] **Navigate between screens → nothing.** Buzzing on every push is the failure mode.

## 3. Drawer motion

- [ ] Opens and closes on a spring, not a timed curve
- [ ] **Interrupt it mid-open with a drag.** A spring retargets from where it is; a timed
      curve snaps. This is the whole reason it changed.

## 4. Context menus

- [ ] Long-press a track row on: Album, Wrapped, Top Items, Artist, Mood Picks, Recently
      Played, Likes, Profile Recent
- [ ] Same actions as the ellipsis button, in the same order
- [ ] **The ellipsis button still works.** The context menu is additive — if it ever
      replaced the button, that is a bug.

## 5. Notifications — the full matrix

Needs two accounts (or a friend). Every kind, on hardware.

| Kind | How to trigger |
|------|----------------|
| `share_received` | B shares a song with A |
| `share_comment` | B comments on A's share |
| `share_reaction` | B reacts to A's share |
| `share_listened` | B plays a song A sent |
| `share_rated` | B rates a song A sent |
| `queue_threshold` | 3+ friends queue the same share |
| `friend_request` | B requests A |
| `friend_accepted` | B accepts A's request |
| `invite_accepted` | B accepts A's invite |
| `wrapped_drop` | 1st of the month, or invoke `cron_wrapped` |
| `release_radar_drop` | Saturday, or invoke `cron_release_radar` |
| `rate_reminder` | Leave a received share unplayed 24h, or invoke `cron_rate_reminder` |
| `favorites_reminder` | Invoke `cron_favorites_reminder` |
| `digest` | Invoke `cron_shares_digest` |
| `broadcast` | Post one from the Admin Portal |

For each:

- [ ] Arrives on the lock screen with sensible copy — **no `{placeholder}` left in the text**
- [ ] Tapping it lands on the right screen
- [ ] Arriving with the app OPEN: banner for social and drops; **silent** for digest,
      broadcast and favorites
- [ ] Appears in the inbox with an unread dot, and the bell badge increments
- [ ] Muting its toggle in Settings actually stops it
- [ ] **Muting it does NOT stop the inbox row.** Muting means "don't interrupt me", not
      "hide this from my history" — that is deliberate.

### Coalescing (the fiddly one)

- [ ] B plays *then* rates the same share within 10 minutes → A gets **ONE** push reading
      "listened and rated ★★★★", not two
- [ ] B plays and never rates → A gets a plain "listened" push, **within about 5 minutes**
      (the sweeper cron), not instantly and not never

### Things that should send nothing

- [ ] Commenting on your own share
- [ ] Rating your own share
- [ ] Un-reacting (removing a reaction)
- [ ] A friend request that fails to write

## 6. Accessibility

- [ ] **Dynamic Type at the largest accessibility size.** Does anything clip, overlap, or
      become unreachable? Feed cards and the notification rows are the likely casualties.
- [ ] **VoiceOver** through: Feed, a share card, Settings › Notifications, the inbox.
      Every toggle announces its label and state; the starfield is silent (it is
      `accessibilityHidden`).
- [ ] **Reduce Motion on**: no nebula drift, no spring on the drawer, no preview animation.
      Content still fully readable — the still version must be the informative one.
- [ ] **Dark mode.** The app is dark-only by design; confirm nothing renders light-on-light.

## 7. Still open, needing a decision rather than a test

- [ ] **`matchedGeometryEffect` on art → detail.** Not achievable on iOS 17: it needs source
      and destination in one hierarchy sharing a namespace, but this is a `NavigationStack`
      push where the source is torn down. The modern answer,
      `.navigationTransition(.zoom)`, is **iOS 18+**. Options: raise the deployment target
      (drops iOS 17 users), build a custom overlay transition, or drop the idea.
- [ ] **Xomtracks on iOS.** Web's `/shares` is a separate product on its own API; iOS has no
      client for it and still uses the native shares feed. The two clients diverge here on
      purpose — see `ios-ia-parity/PLAN.md`.

---

## Notes

- New test files must be added to the `Xomify-iOSTests` target — the app targets use Xcode
  16 synchronized groups, the test target does not (see `ios-test-target/PLAN.md`).
- `xcodebuild -scheme Xomify-iOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`
  → **83 passed, 0 failed, 0 crashes**. CI fails on a non-zero exit again.
