import SwiftUI

/// Shared reactions row used on both `ShareCardView` (feed) and
/// `ShareDetailView`. Renders a pill for every reaction the post has at least
/// one of (active when the viewer has reacted), then a smiley button at the
/// end that opens an iMessage-style horizontal emoji picker popover.
///
/// The owning view model decides what happens on toggle — this component is
/// purely presentational + closure-driven.
struct ReactionsBar: View {

    let counts: [String: Int]
    let viewerReactions: [String]
    let inFlightSlugs: Set<String>
    let onToggle: (ShareReaction) -> Void

    @State private var showPicker: Bool = false

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
            addButton
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

    private var addButton: some View {
        Button {
            showPicker = true
        } label: {
            Image(systemName: "face.smiling")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, height: 32)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a reaction")
        .popover(
            isPresented: $showPicker,
            attachmentAnchor: .point(.top),
            arrowEdge: .bottom
        ) {
            emojiPickerRow
                .presentationCompactAdaptation(.popover)
        }
    }

    /// iMessage-style row: emoji-only buttons in a single horizontal capsule.
    private var emojiPickerRow: some View {
        HStack(spacing: 14) {
            ForEach(ShareReaction.allCases) { reaction in
                Button {
                    showPicker = false
                    onToggle(reaction)
                } label: {
                    Text(reaction.emoji)
                        .font(.system(size: 28))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reaction.accessibilityLabel)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
