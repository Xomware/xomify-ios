// Duplicated from Xomify-iOS/Utilities/URLShareParsing.swift -- keep in sync.
// The Share Extension is a separate target with no shared module, so it can't
// import the main app. Both copies exist for build-time isolation; if you
// edit one, edit the other.

import Foundation

extension URL {
    var xomifyShareTrackId: String? {
        if scheme == "xomify", host == "share" {
            return URLComponents(url: self, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "trackId" })?
                .value
        }
        if host == "open.spotify.com" {
            let parts = path.split(separator: "/")
            if parts.count >= 2, parts[0] == "track" {
                return String(parts[1]).components(separatedBy: "?").first
            }
        }
        if scheme == "spotify" {
            let parts = absoluteString.split(separator: ":")
            if parts.count >= 3, parts[1] == "track" {
                return String(parts[2]).components(separatedBy: "?").first
            }
        }
        return nil
    }
}
