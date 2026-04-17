import Foundation

// MARK: - Jaccard result

struct CompareBreakdown: Sendable {
    let tracksOverlap: Double      // 0...1
    let artistsOverlap: Double
    let genresOverlap: Double
    let sharedTrackNames: [String]
    let sharedArtistNames: [String]
    let sharedGenres: [String]

    /// Overall similarity: simple mean of the three components.
    var overall: Double {
        let vals = [tracksOverlap, artistsOverlap, genresOverlap]
        return vals.reduce(0, +) / Double(vals.count)
    }

    var overallPercent: Int {
        Int(round(overall * 100))
    }
}

/// ViewModel for Compare: Jaccard similarity between the current user and a
/// friend. Uses the local-computation approach (no backend lambda).
@Observable
@MainActor
final class CompareViewModel {

    // MARK: - State

    var selfEmail: String = ""
    var friends: [Friend] = []
    var selectedFriend: Friend?

    var result: CompareBreakdown?

    var isLoadingFriends = false
    var isComparing = false
    var errorMessage: String?

    private let xomify = XomifyService.shared
    private let spotify = SpotifyService.shared

    // MARK: - Load friends

    func loadFriends(email: String) async {
        selfEmail = email
        guard !isLoadingFriends else { return }
        isLoadingFriends = true
        errorMessage = nil

        do {
            let response = try await xomify.getAllFriends(email: email)
            friends = response.accepted ?? []
        } catch {
            errorMessage = "Failed to load friends: \(error.localizedDescription)"
            print("❌ Compare: loadFriends failed - \(error)")
        }

        isLoadingFriends = false
    }

    // MARK: - Compare

    func compare(with friend: Friend) async {
        guard !isComparing else { return }
        selectedFriend = friend
        result = nil
        isComparing = true
        errorMessage = nil

        do {
            // Fetch my top tracks + artists (medium_term for stability).
            async let myTracks = spotify.getTopTracks(timeRange: .mediumTerm, limit: 50)
            async let myArtists = spotify.getTopArtists(timeRange: .mediumTerm, limit: 50)

            // Friend's backend profile has top* term maps.
            async let friendProfile = xomify.getFriendProfile(
                email: selfEmail,
                profileEmail: friend.targetEmail
            )

            let (mineTracks, mineArtists, profile) = try await (myTracks, myArtists, friendProfile)

            // Extract comparable identifiers/names.
            let myTrackIds = Set(mineTracks.map { $0.id })
            let myArtistIds = Set(mineArtists.compactMap { $0.id })
            let myGenres = Set(mineArtists.flatMap { $0.genres ?? [] }.map { $0.lowercased() })

            let myTrackNameById = Dictionary(uniqueKeysWithValues: mineTracks.map { ($0.id, $0.name) })
            let myArtistNameById = Dictionary(uniqueKeysWithValues: mineArtists.compactMap { artist -> (String, String)? in
                guard let id = artist.id else { return nil }
                return (id, artist.name)
            })

            let (friendTrackIds, friendTrackNames) = extractIdsAndNames(from: profile.topSongs, idKey: "id", nameKey: "name")
            let (friendArtistIds, friendArtistNames) = extractIdsAndNames(from: profile.topArtists, idKey: "id", nameKey: "name")
            let friendGenres = extractGenres(from: profile.topGenres)

            let sharedTrackIds = myTrackIds.intersection(friendTrackIds)
            let sharedArtistIds = myArtistIds.intersection(friendArtistIds)
            let sharedGenreSet = myGenres.intersection(friendGenres)

            let tracksOverlap = jaccard(a: myTrackIds, b: friendTrackIds)
            let artistsOverlap = jaccard(a: myArtistIds, b: friendArtistIds)
            let genresOverlap = jaccard(a: myGenres, b: friendGenres)

            let sharedTrackNames = sharedTrackIds.compactMap { id in
                myTrackNameById[id] ?? friendTrackNames[id]
            }
            let sharedArtistNames = sharedArtistIds.compactMap { id in
                myArtistNameById[id] ?? friendArtistNames[id]
            }

            result = CompareBreakdown(
                tracksOverlap: tracksOverlap,
                artistsOverlap: artistsOverlap,
                genresOverlap: genresOverlap,
                sharedTrackNames: Array(sharedTrackNames.prefix(10)),
                sharedArtistNames: Array(sharedArtistNames.prefix(10)),
                sharedGenres: Array(sharedGenreSet.prefix(10))
            )
        } catch {
            errorMessage = "Failed to compare: \(error.localizedDescription)"
            print("❌ Compare: compare failed - \(error)")
        }

        isComparing = false
    }

    // MARK: - Helpers

    private func jaccard<T: Hashable>(a: Set<T>, b: Set<T>) -> Double {
        guard !(a.isEmpty && b.isEmpty) else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    /// Extracts (ids set, id->name dict) from a term-bucket JSON map. Accepts
    /// either arrays of objects `{ id, name }` or arrays of plain strings.
    private func extractIdsAndNames(
        from map: [String: JSONValue]?,
        idKey: String,
        nameKey: String
    ) -> (Set<String>, [String: String]) {
        guard let map = map else { return ([], [:]) }

        // Prefer mediumTerm, fall back to others.
        let preferred = ["mediumTerm", "medium_term", "shortTerm", "short_term", "longTerm", "long_term"]
        var list: [JSONValue] = []
        for key in preferred {
            if let entry = map[key], let arr = entry.arrayValue {
                list = arr
                break
            }
        }
        if list.isEmpty {
            for (_, v) in map {
                if let arr = v.arrayValue, !arr.isEmpty {
                    list = arr
                    break
                }
            }
        }

        var ids = Set<String>()
        var names: [String: String] = [:]
        for item in list {
            if let s = item.stringValue {
                // Plain id string.
                ids.insert(s)
            } else if let obj = item.objectValue {
                if let id = obj[idKey]?.stringValue {
                    ids.insert(id)
                    if let name = obj[nameKey]?.stringValue {
                        names[id] = name
                    }
                } else if let id = obj["trackId"]?.stringValue {
                    ids.insert(id)
                    if let name = obj["trackName"]?.stringValue {
                        names[id] = name
                    }
                } else if let id = obj["artistId"]?.stringValue {
                    ids.insert(id)
                    if let name = obj["artistName"]?.stringValue {
                        names[id] = name
                    }
                }
            }
        }
        return (ids, names)
    }

    /// Genres are lower-cased strings. Accepts either arrays of strings or
    /// dicts `{ genre: count }`.
    private func extractGenres(from map: [String: JSONValue]?) -> Set<String> {
        guard let map = map else { return [] }
        let preferred = ["mediumTerm", "medium_term", "shortTerm", "short_term", "longTerm", "long_term"]

        var result = Set<String>()
        for key in preferred {
            if let entry = map[key] {
                if let arr = entry.arrayValue {
                    for item in arr {
                        if let s = item.stringValue { result.insert(s.lowercased()) }
                    }
                    if !result.isEmpty { return result }
                }
                if let obj = entry.objectValue {
                    for (k, _) in obj { result.insert(k.lowercased()) }
                    if !result.isEmpty { return result }
                }
            }
        }
        return result
    }
}
