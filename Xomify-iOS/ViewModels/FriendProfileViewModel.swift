import Foundation

/// Loads the public profile of another user.
@Observable
@MainActor
final class FriendProfileViewModel {

    var profile: FriendProfile?
    var isLoading = false
    var errorMessage: String?

    private let xomify = XomifyService.shared

    func load(viewerEmail: String, profileEmail: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            profile = try await xomify.getFriendProfile(email: viewerEmail, profileEmail: profileEmail)
        } catch {
            errorMessage = error.localizedDescription
            print("❌ FriendProfile: load failed - \(error)")
        }

        isLoading = false
    }

    // MARK: - Derived (lightweight, since payload shape varies)

    /// Best-effort "medium term" top artist names.
    var topArtistNames: [String] {
        stringsFromTermMap(profile?.topArtists)
    }

    /// Best-effort top song titles.
    var topSongNames: [String] {
        stringsFromTermMap(profile?.topSongs)
    }

    /// Best-effort top genres.
    var topGenres: [String] {
        stringsFromTermMap(profile?.topGenres)
    }

    /// Accepts either `{ mediumTerm: [...] }` (arrays of strings or objects with
    /// `name`) or a bare array. Returns a display-ready string list.
    private func stringsFromTermMap(_ value: [String: JSONValue]?) -> [String] {
        guard let value = value else { return [] }

        let preferredOrder = ["mediumTerm", "medium_term", "shortTerm", "short_term", "longTerm", "long_term"]

        for key in preferredOrder {
            if let entry = value[key], let list = entry.arrayValue {
                return extractNames(from: list)
            }
        }

        // Fallback: first non-empty array value.
        for (_, v) in value {
            if let list = v.arrayValue, !list.isEmpty {
                return extractNames(from: list)
            }
        }
        return []
    }

    private func extractNames(from list: [JSONValue]) -> [String] {
        list.compactMap { item -> String? in
            if let s = item.stringValue { return s }
            if let obj = item.objectValue {
                if let name = obj["name"]?.stringValue { return name }
                if let name = obj["trackName"]?.stringValue { return name }
                if let name = obj["artistName"]?.stringValue { return name }
            }
            return nil
        }
    }
}
