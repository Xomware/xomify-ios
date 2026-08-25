import SwiftUI

/// Pill-style tab switcher used above the tabbed `ProfileView` content. Mirrors
/// the web app's Overview/Settings pill group so brand feel matches across
/// surfaces — gradient fill on the active pill, subtle inactive label.
struct ProfileTabPicker: View {

    @Binding var selection: ProfileTab

    private let namespace: Namespace.ID
    private let tabs: [ProfileTab]

    init(
        selection: Binding<ProfileTab>,
        namespace: Namespace.ID,
        tabs: [ProfileTab] = ProfileTab.allCases
    ) {
        self._selection = selection
        self.namespace = namespace
        self.tabs = tabs
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .background(Color.xomifyCard.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: XomRadius.pill, style: .continuous)
                .stroke(Color.xomifyPurple.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: XomRadius.pill, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Profile sections")
    }

    private func tabButton(_ tab: ProfileTab) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selection = tab
            }
        } label: {
            ZStack {
                if isSelected {
                    LinearGradient(
                        colors: [Color.xomifyPurple, Color.xomifyGreen],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: XomRadius.pill, style: .continuous))
                    .matchedGeometryEffect(id: "profileTabActive", in: namespace)
                    .shadow(color: Color.xomifyPurple.opacity(0.35), radius: 8, y: 3)
                }
                Image(systemName: tab.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
