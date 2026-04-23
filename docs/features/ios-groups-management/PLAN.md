# Plan: Xomify Social Feed — ios-groups-management

**Epic**: [xomify-social-feed](../xomify-social-feed/PLAN.md)
**Sub-feature ID**: 6 (`ios-groups-management`)
**Status**: Ready
**Created**: 2026-04-22
**Last updated**: 2026-04-22
**Scope size**: M
**Repo(s) touched**: `xomify-ios`
**Depends on**: 2 (`ios-nav-shell`) — merged

---

## Summary

Polish the drawer-resident Groups screen into a first-class management surface: pick members from the accepted-friends graph (instead of typing raw emails), surface an OWNER badge on the list, add destructive owner/non-owner actions (delete vs leave) on the detail screen, and hard-gate remove-member + delete-group on ownership. The Groups view already exists from previous work — this sub-feature refines UX, wires to the friends picker, and closes the loop on the epic's "no iOS UI for shared-queue" boundary by keeping the existing tracks tab untouched.

## One-liner (from epic)

> Drawer-resident Groups screen: list / create / add-member / remove-member. Wires to existing `groups_*` lambdas.

---

## Critical decisions inherited from epic (do not re-litigate)

- **Groups = filter layer on iOS** (epic decision #7). Existing `groups_add_song` / `groups_song_status` / tracks tab **stays** — already shipped — but no new shared-queue surfaces get added in this PR.
- **No new backend work.** Every endpoint this PR needs is already live and already wired in `XomifyService`.
- **Lives in the drawer**, not the tab bar. Drawer destination `.groups` already routes to `GroupsView()` (see `DrawerView.swift:126`).
- **MVVM constraint**: views never touch `XomifyService` directly — go through a VM. Already honored by `GroupsViewModel` / `GroupDetailViewModel`.

---

## Investigation findings

Verified against the tree under `Xomify-iOS/` on `master` (post-nav-shell merge):

- **Drawer wiring is live**: `Xomify-iOS/Views/Shell/DrawerView.swift:126` — `case .groups: GroupsView()` inside `.navigationDestination(for: DrawerDestination.self)`. No shell-level change needed. `DrawerDestination.groups` already exists in `NavigationStore.swift`.
- **GroupsView already exists** at `Xomify-iOS/Views/GroupsView.swift` — list + create sheet + navigation to detail. Uses `GroupsViewModel`. Shows member count + track count but **does not display an owner badge** on the list row.
- **GroupDetailView already exists** at `Xomify-iOS/Views/GroupDetailView.swift` — segmented Tracks / Members tabs, member add via typed email, owner-only remove button on members. **No leave-group / delete-group actions on the screen**; VM only has leave in the list VM (`GroupsViewModel.leave`).
- **GroupsViewModel** at `Xomify-iOS/ViewModels/GroupsViewModel.swift` — `load`, `refresh`, `create`, `leave`. **Missing**: `delete` (owner), friends list for picker.
- **GroupDetailViewModel** at `Xomify-iOS/ViewModels/GroupDetailViewModel.swift` — `load`, `refresh`, `addMember`, `removeMember`, plus song CRUD (out of scope for this PR). **Missing**: `leave`, `delete`, friends list for picker.
- **XomifyService** is already an `actor` at `Xomify-iOS/Services/XomifyService.swift` and **has every endpoint we need**: `listGroups`, `createGroup`, `getGroupInfo`, `addMember`, `removeMember`, `leaveGroup`, `removeGroup` (delete), plus `getAllFriends` for the picker. Also has `updateGroup` if we want rename in the future.
- **Models** are complete at `Xomify-iOS/Models/SocialModels.swift`: `XomifyGroup` (has `ownerEmail`), `GroupMember` (has `isOwner`), `GroupsListResponse`, `GroupInfo`, `GroupCreateResponse`, `SuccessResponse`, and `Friend` / `FriendsAllResponse` for the picker.
- **Project layout**: `PBXFileSystemSynchronizedRootGroup` — adding `.swift` files under `Xomify-iOS/` needs no pbxproj edits.
- **Build scheme**: `Xomify-iOS` against `Xomify-iOS.xcodeproj`.

### Backend endpoint shapes — no mismatches

Every endpoint the epic assumed exists and matches the service call. The epic spec listed `GET /groups/detail`; the actual path is `GET /groups/info`. Already reflected in `XomifyService.getGroupInfo`. The epic spec listed `DELETE /groups/delete`; the actual call is `POST /groups/remove`. Already reflected in `XomifyService.removeGroup`. **No backend PR required.**

---

## Approach

Minimum-delta refinement. The surfaces already exist — we add (a) friend-picker sheets that replace the typed-email flows, (b) an owner badge on the list, (c) `delete` to `GroupsViewModel`, and (d) `leave` / `delete` toolbar actions to `GroupDetailView` with `.confirmationDialog`s. The friends list for pickers is loaded lazily on sheet open via `xomify.getAllFriends(email:)` → `.accepted`.

**Optimistic UI** for member add / remove on detail: mutate `members` locally first, roll back on throw. Create-group stays pessimistic (we need the server's generated `groupId` back). Leave / delete are pessimistic — we wait on success before navigating out.

---

## Target screens

| Screen | Route | Status |
|--------|-------|--------|
| `GroupsListView` (`GroupsView.swift`) | Drawer `.groups` destination | **Exists** — add owner badge on rows. |
| `GroupDetailView` | Pushed from list | **Exists** — add leave + delete toolbar actions. |
| `CreateGroupSheet` | Modal from `GroupsView` + | **Exists** — extend with friend-picker step (name first, then pick members). |
| `AddMemberSheet` (new) | Modal from `GroupDetailView` `person.badge.plus` | **New** — replaces inline typed-email row on the Members tab. |
| `FriendPickerView` (new, shared) | Used by both sheets | **New** — multi-select (create) or single-select (add) friend list with search + exclusion set. |

The existing typed-email `addMemberBar` stays as a fallback for the edge case of adding a non-friend by email — hidden behind a disclosure ("Add someone who isn't a friend yet"). Default path is the picker.

---

## ViewModels

### `GroupsViewModel` — extend

Add:

- `friends: [Friend] = []` — accepted friends cache for the create sheet's picker.
- `isLoadingFriends: Bool` / `friendsError: String?`.
- `func loadFriends() async` — calls `xomify.getAllFriends(email:).accepted ?? []`. Cache so re-opening the sheet is instant.
- `@discardableResult func create(name:String, memberEmails:[String]) async -> XomifyGroup?` — replaces the description-only signature. Under the hood: create group, then fan-out-add each picked member email with `xomify.addMember`. If adds partially fail, surface "Group created, N of M members added — try re-adding from the group."
- `@discardableResult func delete(_ group: XomifyGroup) async -> Bool` — calls `xomify.removeGroup`; on success removes from `groups` and returns `true`. Owner-only gate done by the caller (view).

Keep: `load`, `refresh`, `leave` (used on detail screen too).

### `GroupDetailViewModel` — extend

Add:

- `friends: [Friend] = []` (accepted friends for the add-member picker).
- `func loadFriends() async`.
- `func addMembers(_ emails: [String]) async` — loops `xomify.addMember` with optimistic local `members` insert + rollback per-failure. Clears picker on success.
- `@discardableResult func leave() async -> Bool` — calls `xomify.leaveGroup`; returns `true` on success so the view can `dismiss()`.
- `@discardableResult func delete() async -> Bool` — calls `xomify.removeGroup` (owner-only; caller verifies `group?.ownerEmail == userEmail` first).

Keep: `load`, `refresh`, `addMember` (single), `removeMember`. Song methods untouched.

**Note on concurrency**: both VMs stay `@Observable` + `@MainActor`. They already are. No changes to the service `actor`.

---

## Service layer

**No changes required.** Every call we need is already exposed on `XomifyService`:

- `listGroups(email:)` → `GroupsListResponse`
- `createGroup(email:, name:, description:)` → `GroupCreateResponse`
- `getGroupInfo(groupId:, email:)` → `GroupInfo`
- `addMember(email:, groupId:, memberEmail:)` → `SuccessResponse`
- `removeMember(email:, groupId:, memberEmail:)` → `SuccessResponse`
- `leaveGroup(email:, groupId:)` → `SuccessResponse`
- `removeGroup(email:, groupId:)` → `SuccessResponse` (maps to backend `POST /groups/remove` — functional "delete")
- `getAllFriends(email:)` → `FriendsAllResponse` (accepted bucket feeds the picker)

No new models. All shapes verified in `Xomify-iOS/Models/SocialModels.swift`.

---

## Affected Files / Components

### New files

| File | Purpose |
|------|---------|
| `Xomify-iOS/Views/Groups/FriendPickerView.swift` | Reusable multi/single-select friend picker with search. Generic over selection mode. |
| `Xomify-iOS/Views/Groups/AddMemberSheet.swift` | Sheet shown from `GroupDetailView`; hosts `FriendPickerView` (excluding current members) + a confirm button. |

### Modified files

| File | Change | Why |
|------|--------|-----|
| `Xomify-iOS/Views/GroupsView.swift` | Show OWNER badge in `groupRow` when `group.ownerEmail == viewModel.userEmail`. Extend `CreateGroupSheet` with a second step: name → pick friends (multi-select). Replace current onCreate signature with `(name, selectedEmails, description?)`. | Close owner-affordance gap + swap email-typing for friend picker. |
| `Xomify-iOS/Views/GroupDetailView.swift` | Add toolbar `Menu` with "Leave Group" (non-owner) or "Delete Group" (owner), each gated by `.confirmationDialog`. Replace inline `addMemberBar` with a button that presents `AddMemberSheet`. Keep typed-email row behind a "Add by email" disclosure row inside the sheet. | Destructive-action parity + picker-first UX. |
| `Xomify-iOS/ViewModels/GroupsViewModel.swift` | Add `friends`, `loadFriends()`, `delete(_:)`, extend `create` to accept `memberEmails`. | See ViewModel section. |
| `Xomify-iOS/ViewModels/GroupDetailViewModel.swift` | Add `friends`, `loadFriends()`, `addMembers([String])`, `leave()`, `delete()`. | See ViewModel section. |

### Not touched

- `Xomify-iOS/Services/XomifyService.swift` — zero changes.
- `Xomify-iOS/Models/SocialModels.swift` — zero changes.
- `Xomify-iOS/Views/Shell/*` — zero changes. Drawer already routes `.groups → GroupsView()`.
- `Xomify-iOS/Views/GroupDetailView.swift` **Tracks tab** — zero changes. Epic boundary.

No backend changes. No Angular changes.

---

## Drawer wiring confirmation

`DrawerView.swift` already has:

```swift
case .groups:
    GroupsView()
```

inside `.navigationDestination(for: DrawerDestination.self)`. Drawer owns its own `NavigationStack(path: $navStore.drawerPath)`, so pushing `GroupDetailView` from the list via a `NavigationLink` works inside the drawer's stack. **No MainShell, HeaderBar, or NavigationStore edits.**

---

## Implementation Steps

- [ ] **1. Branch**
  - [ ] `git checkout -b feat/ios-groups-management` off `master`.
- [ ] **2. FriendPickerView (shared component)**
  - [ ] Create `Xomify-iOS/Views/Groups/FriendPickerView.swift`.
  - [ ] API: `init(friends: [Friend], excluding: Set<String> = [], selectionMode: Mode, onConfirm: (Set<String>) -> Void, onCancel: () -> Void)`.
  - [ ] `enum Mode { case single, multi }`.
  - [ ] Body: search field (filters by `label` / `targetEmail`) + `List { ... Toggle / Button rows }` + confirm button.
  - [ ] Empty state: "No friends yet. Add some from the Friends drawer entry."
  - [ ] Respect `.claude/rules/ios.md`: `foregroundStyle`, `Color.xomifyDark`, no force unwraps.
- [ ] **3. GroupsViewModel extensions**
  - [ ] Add `friends`, `isLoadingFriends`, `friendsError`.
  - [ ] Add `loadFriends()` calling `xomify.getAllFriends(email:)` — populate `friends` from the `accepted` bucket.
  - [ ] Replace `create(name:description:)` with `create(name:memberEmails:description:)`. Compile-check callsites (one: `GroupsView.CreateGroupSheet.onCreate`).
  - [ ] Add `delete(_:)` calling `xomify.removeGroup`; remove from `groups` on success.
- [ ] **4. CreateGroupSheet rework**
  - [ ] Two-step flow inside the same sheet: Step 1 = name + description; Step 2 = pick friends (embed `FriendPickerView` in `.multi` mode). "Back" returns to step 1.
  - [ ] Confirm button on step 2 calls `onCreate(name, selectedEmails, description)`.
  - [ ] Skip-step-2 affordance: "Create without members" button on step 1 that bypasses the picker with an empty set. Useful when friend list is empty.
  - [ ] On `.task`: `await viewModel.loadFriends()`.
- [ ] **5. GroupsView list row OWNER badge**
  - [ ] In `groupRow`, when `group.ownerEmail == viewModel.userEmail`, render the same OWNER capsule already used in `GroupDetailView.memberRow` (match style: `Color.xomifyPurple.opacity(0.2)` / `foregroundColor(.xomifyPurple)`, font `.caption2` semibold).
  - [ ] VoiceOver label on the row announces "Group Name, owner, N members, M tracks" when owned.
- [ ] **6. GroupDetailViewModel extensions**
  - [ ] Add `friends`, `loadFriends()`.
  - [ ] Add `addMembers(_ emails: [String])` — optimistic inserts (append skeleton `GroupMember(email:)` with `isOwner=false`), call `xomify.addMember` per email, on failure remove the skeleton and surface the error. On complete success do a `refresh()` to get server-canonical display names / joinedAt.
  - [ ] Add `leave()` / `delete()` — pessimistic, return `Bool`.
- [ ] **7. AddMemberSheet**
  - [ ] Create `Xomify-iOS/Views/Groups/AddMemberSheet.swift`.
  - [ ] Content: `FriendPickerView` in `.multi` mode with `excluding: Set(viewModel.members.map { $0.email })`.
  - [ ] Below picker: disclosure group "Add by email" — the old `TextField` + `person.badge.plus` button as a fallback. Keeps the existing `viewModel.addMember()` call path.
  - [ ] Confirm calls `viewModel.addMembers(Array(selected))`.
- [ ] **8. GroupDetailView destructive actions**
  - [ ] Replace the refresh-only toolbar with a `Menu`:
    - `Button("Refresh", systemImage: "arrow.clockwise") { Task { await viewModel.refresh() } }`.
    - If `viewerEmail == group?.ownerEmail`: `Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Delete Group", systemImage: "trash") }`.
    - Else: `Button(role: .destructive) { showLeaveConfirm = true } label: { Label("Leave Group", systemImage: "rectangle.portrait.and.arrow.right") }`.
  - [ ] Two `.confirmationDialog` modifiers. Destructive button text: "Delete Group" / "Leave Group". Include a `Button("Cancel", role: .cancel) {}` in each.
  - [ ] On success: call `dismiss` via `@Environment(\.dismiss)` so the user pops back to `GroupsView`. If delete, also ensure `GroupsViewModel` gets told to refresh — simplest: `.task(id: navStore.drawerPath)` on `GroupsView` already reloads on return. If not, add an explicit `viewModel.refresh()` in `onAppear`.
  - [ ] Replace the inline `addMemberBar` on the Members tab with a single "Add members" button that toggles `showingAddMemberSheet`.
- [ ] **9. Accessibility pass**
  - [ ] All destructive buttons: `.accessibilityLabel("Leave group")` / `.accessibilityLabel("Delete group")`, `.accessibilityHint("Opens a confirmation dialog")`.
  - [ ] Remove-member trash icon: `.accessibilityLabel("Remove <member label>")`, `.accessibilityHint("Removes this member from the group")`.
  - [ ] All action buttons ≥ 44×44pt (SwiftUI `Button` defaults are fine; verify trash and plus icons expand tap area).
  - [ ] Picker rows expose `.accessibilityAddTraits(.isButton)` and announce selected state.
- [ ] **10. Error UX**
  - [ ] Continue using the existing `overlay(alignment: .top) { if let error = viewModel.errorMessage ... }` red banner pattern already in `GroupDetailView`. Extend `GroupsView` to show the same banner (currently only `errorState` full-screen exists — add an inline banner for non-fatal errors like partial-create failures).
  - [ ] Each VM action sets `errorMessage` on throw; no silent swallows. Existing pattern already honors this.
- [ ] **11. Build**
  - [ ] `xcodebuild -project Xomify-iOS.xcodeproj -scheme Xomify-iOS -sdk iphonesimulator clean build`. Resolve any strict-concurrency warnings introduced by the new code.
- [ ] **12. Simulator smoke (manual, Dom to run)**
  - [ ] Sign in → open drawer → Groups.
  - [ ] Create group: typed name + picked 1 friend → verify OWNER badge shows on the new row.
  - [ ] Open new group → Members tab → Add members → pick another friend → confirm. Verify appears in list.
  - [ ] As owner: remove a member via the member-row trash. Confirm.
  - [ ] Open toolbar menu → Delete Group → confirm → verify list excludes the group on return.
  - [ ] Create a second group, add self only, switch Spotify accounts or simulate a non-owner (alt: have the member-side account run the flow) → toolbar shows **Leave** not **Delete**.
  - [ ] Verify "Add by email" fallback still works for typing a non-friend email.
- [ ] **13. PR**
  - [ ] Commit: `#<issue> feat(ios): groups management — friend picker, owner badge, leave/delete`.
  - [ ] PR title: `feat(ios): groups management — friend picker, owner badge, leave/delete`.
  - [ ] Body: `Closes #<issue>`, 2 screenshots (list with OWNER badge, detail with Delete menu), smoke checklist above.
  - [ ] Request `code-reviewer` agent pass.

---

## Accessibility

- **Destructive actions**: every leave / delete / remove control has a `.accessibilityLabel`, `.accessibilityHint`, and goes through a `.confirmationDialog`. No single-tap destructive paths.
- **Owner badge**: `.accessibilityLabel("Owner")` on the capsule; owner state is also announced in the parent row label.
- **Picker rows**: `.accessibilityValue("Selected")` / `"Not selected"` when in multi-select mode.
- **Touch targets**: 44×44pt minimum on every tappable control. SwiftUI `Button` + SF Symbol default padding verified with Accessibility Inspector during smoke.
- **Dynamic Type**: all screens already use `.font(.caption)` / `.font(.subheadline)` — test at `.accessibility3`. Owner badge may wrap; that's fine.
- **VoiceOver row announcement**: group list row uses `.accessibilityElement(children: .combine)` + a custom label ("Group Name, owner, 4 members").

---

## Build / test commands

```bash
# Clean build
xcodebuild -project Xomify-iOS.xcodeproj \
           -scheme Xomify-iOS \
           -sdk iphonesimulator \
           clean build

# Smoke run
open -a Simulator
xcrun simctl boot "iPhone 15" 2>/dev/null || true
xcodebuild -project Xomify-iOS.xcodeproj \
           -scheme Xomify-iOS \
           -sdk iphonesimulator \
           -destination 'platform=iOS Simulator,name=iPhone 15' \
           build
```

`.claude/CLAUDE.md` says `echo "no tests configured"` — no XCTest target. VM logic (friend-picker filter, delete, addMembers rollback) is small enough that manual smoke covers it. If the `ios-engineer` agent wants to add a minimal XCTest target in this PR, flag for Dom's approval first — don't expand scope.

---

## PR shape

- **Branch**: `feat/ios-groups-management`
- **Commit**: `#<issue-number> feat(ios): groups management — friend picker, owner badge, leave/delete`
- **PR title**: `feat(ios): groups management — friend picker, owner badge, leave/delete`
- **PR description**: `Closes #<issue-number>`, screenshots (list with OWNER badge, detail menu open, add-member picker), the simulator-smoke checklist above.
- **Reviewer**: `code-reviewer` agent.
- **Merge gate**: green build + manual smoke pass.

---

## Out of Scope

- **Invite-a-friend CTA** — that's `ios-friends-management` (#7). Do not put an Invite button on the Groups screens.
- **Groups-as-shared-queue UI** — the existing Tracks tab in `GroupDetailView` already exists and stays. We don't add new shared-queue entry points, and we don't remove the existing ones either. Epic decision #7.
- **Feed-side group filter chips** — that's `ios-feed` (#5), consuming `listGroups`.
- **Group rename / edit description** — `updateGroup` exists on the service but no UI is planned here. Defer.
- **Group avatar / cover image** — no backend support; defer.
- **Push notification on member add** — not backend-supported; defer.
- **XCTest scaffolding** — project has none; adding one is out of scope.
- **Drawer / NavigationStore changes** — already done in #2.

---

## Risks / Tradeoffs

- **Backend shape mismatch risk**: none found. Epic spec mentioned `GET /groups/detail` and `DELETE /groups/delete` but actual endpoints are `GET /groups/info` and `POST /groups/remove`, and these are already correctly wired in `XomifyService`. **No backend PR needed.**
- **Optimistic add-member rollback complexity**: looping `addMember` per picked friend means partial-failure state. Mitigation: accept partial success, surface the count ("N of M added"), and drive a `refresh()` to get the canonical list. Worse UX than atomic batch but matches the current single-member backend shape.
- **Pessimistic vs optimistic on create-and-add-members**: accepted pessimistic for create-group call (need `groupId`) + optimistic for post-create adds. Risk: group appears without all members if a network blip hits mid-fan-out. Mitigation: explicit toast + refresh button.
- **Drawer `NavigationStack` vs sheet presentation**: sheets on a push-stack inside the drawer can fight dismiss gestures on small devices. Mitigation: use `.sheet(isPresented:)` on the leaf view (`GroupDetailView`), not on the drawer root — already the pattern in the existing code.
- **Non-friend email fallback**: keeping the typed-email path risks letting owners add random emails. Accepted — mirrors the current behavior; backend already validates membership rules.
- **Removing a member who is the last non-owner**: no server-side guardrail we rely on. Accepted — owners can shrink their group to just themselves by design.
- **Delete-group navigation race**: after `delete()` success we need to `dismiss()` and have the list reload. Risk: stale row flashes before refresh. Mitigation: `GroupsView` calls `viewModel.refresh()` in `.onAppear` on return from detail.

---

## Open Questions

- [ ] **Confirm smoke-test account pair**: do we have two Spotify dev accounts ready to test the owner vs non-owner branch end-to-end, or do we stub a second `ownerEmail` for the smoke? Either works — flag before step 12.
- [ ] **Disclosure wording for the non-friend typed-email fallback**: "Add by email" vs "Add someone not in your friends list"? Minor copy call. Default to the shorter.
- [ ] **Should `GroupsView.create` take the description field through the picker flow, or drop description entirely?** Current `CreateGroupSheet` has a description field. Recommend **keep it** in step 1, since the backend supports it and it's already wired. Free UX sugar.
- [ ] **Partial-success toast UX**: full-screen alert or inline banner for "3 of 5 members added"? Recommend the existing top-banner pattern used by `GroupDetailView` — consistent and non-blocking.

---

## Skills / Agents to Use

- **ios-engineer agent**: primary implementer. Knows `@Observable`, modern SwiftUI, MVVM, strict concurrency, and already has context on the navigation shell from sub-feature #2.
- **ios-standards skill**: invoke during step 2 (`FriendPickerView`) + step 6 (VM extensions) to double-check `@Observable` + modern SwiftUI idioms and reject any `ObservableObject` / `@Published` drift.
- **code-reviewer agent**: single mandatory pre-merge review. Focus: concurrency warnings, owner-gate correctness (`viewerEmail == group.ownerEmail` checks), destructive-action `.confirmationDialog` coverage, accessibility labels.
- **test-writer agent**: not required this PR — no XCTest target exists. If Dom approves adding one, pair on `GroupsViewModel.create` + `GroupDetailViewModel.addMembers` rollback tests only.
