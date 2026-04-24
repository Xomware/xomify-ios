import SwiftUI

/// Pill-style tab switcher used above the tabbed `ProfileView` content. Mirrors
/// the web app's Overview/Settings pill group so brand feel matches across
/// surfaces — gradient fill on the active pill, subtle inactive label.
struct ProfileTabPicker: View {

    @Binding var selection: ProfileTab

    private let namespace: Namespace.ID

    init(selection: Binding<ProfileTab>, namespace: Namespace.ID) {
        self._selection = selection
        self.namespace = namespace
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .background(Color.xomifyCard.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .stroke(Color.xomifyPurple.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
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
                    .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
                    .matchedGeometryEffect(id: "profileTabActive", in: namespace)
                    .shadow(color: Color.xomifyPurple.opacity(0.35), radius: 8, y: 3)
                }
                Text(tab.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : Color.white.opacity(0.6))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.title) tab")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
