# Xomify Share Extension — Xcode Setup

The source files in this directory are ready to build but the Xcode target
must be added manually (editing `project.pbxproj` directly is error-prone).
Follow these steps once after cloning / checking out the branch.

---

## 1. Add the Share Extension target

1. Open `Xomify-iOS.xcodeproj` in Xcode.
2. **File → New → Target…**
3. Select **iOS → Share Extension** and click **Next**.
4. Set:
   - **Product Name**: `XomifyShareExtension`
   - **Bundle Identifier**: `com.xomware.xomify.share`
     (adjust to match your signing team's prefix, e.g. `com.domgiordano.xomify.share`)
   - **Language**: Swift
5. Click **Finish**. When Xcode asks to activate the scheme, click **Cancel**
   (we don't need a separate scheme for CI builds).

---

## 2. Replace the generated files

Xcode generates boilerplate `ShareViewController.swift` and `Info.plist`
inside the new target folder. Replace them with the files already in this repo:

```
XomifyShareExtension/ShareViewController.swift
XomifyShareExtension/Info.plist
```

In Xcode's Project Navigator, delete the generated files (move to Trash) and
add the repo files to the target:

- Right-click the `XomifyShareExtension` group → **Add Files to "Xomify-iOS"…**
- Select `ShareViewController.swift` and `Info.plist`
- Make sure only the `XomifyShareExtension` target is checked

---

## 3. Add URLShareParsing.swift to the extension target

`ShareViewController.swift` uses the `URL.xomifyShareTrackId` extension defined
in `Xomify-iOS/Utilities/URLShareParsing.swift`.

In Xcode's Project Navigator, select `URLShareParsing.swift` and in the
**File Inspector** (right panel → Target Membership) check
**XomifyShareExtension** in addition to **Xomify-iOS**.

---

## 4. Configure signing

In the `XomifyShareExtension` target's **Signing & Capabilities** tab:
- Set the same **Team** as the main `Xomify-iOS` target.
- Xcode will auto-generate entitlements. No additional capabilities needed.

---

## 5. Verify the activation rule

Open `XomifyShareExtension/Info.plist` and confirm:

```
NSExtensionAttributes → NSExtensionActivationRule
```

is set to:

```
SUBQUERY(extensionItems, $ei, SUBQUERY($ei.attachments, $a,
  ANY $a.registeredTypeIdentifiers UTI-CONFORMS-TO "public.url"
).@count > 0).@count > 0
```

This allows the extension to appear for any incoming URL. Spotify's share
sheet always passes a `https://open.spotify.com/track/<id>?si=...` URL.

To tighten the rule so the extension only shows for Spotify track URLs, replace
the predicate with a JavaScript/NSPREDUCATE string:

```
SUBQUERY(extensionItems, $ei, SUBQUERY($ei.attachments, $a,
  (ANY $a.registeredTypeIdentifiers UTI-CONFORMS-TO "public.url")
    AND $a.description CONTAINS "open.spotify.com/track"
).@count > 0).@count > 0
```

Note: URL content filtering in activation rules is limited on iOS — the
simpler `public.url` rule is more reliable across Spotify app versions.

---

## 6. Build and test

```bash
# Build the main app (extension builds alongside it after wiring):
xcodebuild -scheme Xomify-iOS \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

To test the share flow:
1. Install the app on a real device (simulator share sheets are unreliable).
2. Open Spotify, navigate to a track.
3. Tap **…** → **Share** → **More** → enable Xomify in the share sheet.
4. Tap Xomify — the extension should open.
5. Tap **Continue in Xomify** — the main app should launch with the composer
   pre-populated.

---

## Deep-link flow (for reference)

```
Spotify share sheet
  → ShareViewController reads URL
  → builds xomify://share?trackId=<id>
  → opens main app via UIApplication.open(_:)
  → Xomify_iOSApp.onOpenURL dispatches to ShareDeepLinkCoordinator
  → FeedView.handlePendingShareDeepLink() consumes the pending id
  → SpotifyService.getTrack(id:) resolves the full track
  → ShareComposerViewModel.selectTrack(_:) pre-populates the composer
  → navStore.composerSheetPresented = true opens the sheet
```
