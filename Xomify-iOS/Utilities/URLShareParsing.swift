import Foundation

extension URL {
    /// Returns the Spotify track id embedded in a share deep link, or `nil`.
    ///
    /// Recognised formats:
    ///   - `xomify://share?trackId=<id>`  (Xomify custom scheme)
    ///   - `https://open.spotify.com/track/<id>`  (Spotify copy-link)
    ///   - `spotify:track:<id>`  (Spotify URI)
    var xomifyShareTrackId: String? {
        // Custom scheme: xomify://share?trackId=<id>
        if scheme == "xomify", host == "share" {
            return URLComponents(url: self, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "trackId" })?
                .value
        }
        // Spotify HTTPS: https://open.spotify.com/track/<id>
        if host == "open.spotify.com" {
            let parts = path.split(separator: "/")
            if parts.count >= 2, parts[0] == "track" {
                // Strip any query params from the id (e.g. ?si=...)
                return String(parts[1]).components(separatedBy: "?").first
            }
        }
        // Spotify URI: spotify:track:<id>
        if scheme == "spotify" {
            let parts = absoluteString.split(separator: ":")
            if parts.count >= 3, parts[1] == "track" {
                return String(parts[2]).components(separatedBy: "?").first
            }
        }
        return nil
    }
}
