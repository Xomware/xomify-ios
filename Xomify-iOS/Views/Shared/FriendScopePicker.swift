import SwiftUI

/// "Me / Friends" switch, plus the friend chooser once Friends is selected.
///
/// Shared by Wrapped, Release Radar and Music Taste rather than reimplemented
/// on each — the three screens differ in what they render, not in whose data
/// they are showing. See docs/features/friend-feed/PLAN.md.
struct FriendScopePicker: View {

    @Binding var showingFriends: Bool
    @Binding var selectedFriend: Friend?
    let friends: [Friend]

    var body: some View {
        VStack(spacing: XomSpacing.sm) {
            Picker("Whose", selection: $showingFriends) {
                Text("Me").tag(false)
                Text("Friends").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, XomSpacing.md)

            if showingFriends {
                if friends.isEmpty {
                    // Not an error state — you simply have nobody to look at.
                    Text("Add a friend to see their music here.")
                        .font(.xomifyCaption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, XomSpacing.xs)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: XomSpacing.xs) {
                            ForEach(friends, id: \.email) { friend in
                                chip(for: friend)
                            }
                        }
                        .padding(.horizontal, XomSpacing.md)
                    }
                }
            }
        }
        .padding(.vertical, XomSpacing.sm)
    }

    private func chip(for friend: Friend) -> some View {
        let selected = selectedFriend?.email == friend.email
        return Button {
            selectedFriend = friend
        } label: {
            HStack(spacing: 6) {
                AsyncImage(url: friend.avatar.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.white.opacity(0.08))
                }
                .frame(width: 22, height: 22)
                .clipShape(Circle())

                Text(friend.displayName ?? friend.email)
                    .font(.xomifyCaption)
                    .lineLimit(1)
            }
            .padding(.horizontal, XomSpacing.sm)
            .padding(.vertical, 6)
            .background(selected ? Color.xomifyPurple : Color.white.opacity(0.06), in: Capsule())
            .foregroundStyle(selected ? .white : .white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }
}

/// What a friend-scoped screen shows when the read is refused or empty.
///
/// A denial and "they have nothing yet" are deliberately the same message. The
/// backend returns one error for "not your friend" and "set to private" so a
/// denial reveals nothing; saying more here would undo that.
struct FriendDataUnavailable: View {
    let name: String
    let artefact: String

    var body: some View {
        VStack(spacing: XomSpacing.sm) {
            Image(systemName: "lock")
                .font(.title)
                .foregroundStyle(.white.opacity(0.35))
            Text("Nothing to show")
                .font(.headline)
                .foregroundStyle(.white)
            Text("\(name) hasn't shared their \(artefact).")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XomSpacing.xl)
    }
}
