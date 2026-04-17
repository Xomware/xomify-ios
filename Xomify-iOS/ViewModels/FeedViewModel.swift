import Foundation

/// ViewModel for the social Feed screen
@Observable
@MainActor
final class FeedViewModel {

    // MARK: - State

    var shares: [Share] = []
    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?

    /// shareId -> the viewer's local reaction (optimistic)
    var myReactions: [String: ReactionAction] = [:]

    private let xomifyService = XomifyService.shared

    // MARK: - Computed

    var isEmpty: Bool { shares.isEmpty }

    // MARK: - Actions

    func load(email: String) async {
        guard !email.isEmpty else {
            errorMessage = "Please log in first"
            return
        }
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        print("📡 Feed: Loading for \(email)...")

        do {
            let response = try await xomifyService.getFeed(email: email)
            shares = response.shares
            print("✅ Feed: Loaded \(shares.count) shares")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Feed: Error - \(error)")
        }

        isLoading = false
    }

    func refresh(email: String) async {
        guard !email.isEmpty else { return }
        guard !isRefreshing else { return }

        isRefreshing = true
        errorMessage = nil

        do {
            let response = try await xomifyService.getFeed(email: email)
            shares = response.shares
            print("✅ Feed: Refreshed - \(shares.count) shares")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Feed: Refresh error - \(error)")
        }

        isRefreshing = false
    }

    /// React to a share with optimistic update + rollback on failure.
    func react(shareId: String, email: String, action: ReactionAction) async {
        guard let index = shares.firstIndex(where: { $0.shareId == shareId }) else { return }

        let previousReaction = myReactions[shareId]
        let previousCounts = shares[index].interactionCounts ?? [:]

        // Optimistic update: adjust local reaction + counts
        var newCounts = previousCounts

        if let prev = previousReaction, prev != .none {
            newCounts[prev.rawValue] = max(0, (newCounts[prev.rawValue] ?? 0) - 1)
        }
        if action != .none {
            newCounts[action.rawValue] = (newCounts[action.rawValue] ?? 0) + 1
            myReactions[shareId] = action
        } else {
            myReactions.removeValue(forKey: shareId)
        }

        shares[index] = Share(
            shareId: shares[index].shareId,
            email: shares[index].email,
            type: shares[index].type,
            payload: shares[index].payload,
            caption: shares[index].caption,
            createdAt: shares[index].createdAt,
            interactionCounts: newCounts
        )

        do {
            _ = try await xomifyService.reactToShare(
                shareId: shareId,
                email: email,
                action: action
            )
        } catch {
            // Rollback
            print("❌ Feed: React failed, rolling back - \(error)")
            if let idx = shares.firstIndex(where: { $0.shareId == shareId }) {
                shares[idx] = Share(
                    shareId: shares[idx].shareId,
                    email: shares[idx].email,
                    type: shares[idx].type,
                    payload: shares[idx].payload,
                    caption: shares[idx].caption,
                    createdAt: shares[idx].createdAt,
                    interactionCounts: previousCounts
                )
            }
            if let prev = previousReaction {
                myReactions[shareId] = prev
            } else {
                myReactions.removeValue(forKey: shareId)
            }
        }
    }
}
