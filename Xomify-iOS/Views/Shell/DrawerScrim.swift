import SwiftUI

/// Full-screen dim overlay behind the drawer. Tap to close.
struct DrawerScrim: View {
    @Environment(NavigationStore.self) private var navStore

    var body: some View {
        if navStore.isDrawerOpen {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    navStore.closeDrawer()
                }
                .accessibilityLabel("Close menu")
                .accessibilityHint("Double-tap to dismiss")
                .accessibilityAddTraits(.isButton)
                .transition(.opacity)
        }
    }
}
