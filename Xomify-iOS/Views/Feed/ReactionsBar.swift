import SwiftUI

/// Shared reactions row used on both `ShareCardView` (feed) and
/// `ShareDetailView`. Renders a pill for every reaction the post has at least
/// one of (active when the viewer has reacted), then a smiley menu button at
/// the end that lets the viewer pick from any of the supported emojis.
///
/// The owning view model decides what happens on toggle — this component is
/// purely presentational + closure-driven.
struct ReactionsBar: View {

    let counts: [String: Int]
    let viewerReactions: [String]
    let inFlightSlugs: Set<String>
    let onToggle: (ShareReaction) -> Void

    /// Order pills appear in. Reactions with count > 0 stick to the front in
    /// `ShareReaction.allCases` order so the row stays stable as counts shift.
    private var activeReactions: [ShareReaction] {
        ShareReaction.allCases.filter { (counts[$0.rawValue] ?? 0) > 0 }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(activeReactions) { reaction in
                pill(reaction)
            }
            addMenu
        }
    }

    private func pill(_ reaction: ShareReaction) -> some View {
        let active = viewerReactions.contains(reaction.rawValue)
        let count = counts[reaction.rawValue] ?? 0
        let inFlight = inFlightSlugs.contains(reaction.rawValue)
        return Button {
            onToggle(reaction)
        } label: {
            HStack(spacing: 4) {
                Text(reaction.emoji)
                    .font(.system(size: 16))
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(active ? Color.xomifyGreen : .white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(active ? Color.xomifyGreen.opacity(0.18) : Color.white.opacity(0.08))
            .overlay(
                Capsule().strokeBorder(
                    active ? Color.xomifyGreen.opacity(0.6) : Color.clear,
                    lineWidth: 1
                )
            )
            .clipShape(Capsule())
            .opacity(inFlight ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(inFlight)
        .accessibilityLabel(reaction.accessibilityLabel)
        .accessibilityValue(active ? "On, \(count)" : "Off, \(count)")
    }

    private var addMenu: some View {
        Menu {
            ForEach(ShareReaction.allCases) { reaction in
                Button {
                    onToggle(reaction)
                } label: {
                    Label(reaction.accessibilityLabel, systemImage: "")
                    Text(reaction.emoji)
                }
            }
        } label: {
            Image(systemName: "face.smiling")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, height: 32)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .accessibilityLabel("Add a reaction")
    }
}
