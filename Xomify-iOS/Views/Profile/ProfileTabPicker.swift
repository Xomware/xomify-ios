import SwiftUI

/// Segmented control swapping between `Shares / Ratings / Taste`. Kept
/// separate from the view models so the chrome can iterate independently.
struct ProfileTabPicker: View {

    @Binding var selection: ProfileTab

    var body: some View {
        Picker("Profile tab", selection: $selection) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
