import Foundation

/// Parses Universal Link and custom-scheme invite URLs and stashes the code
/// so the Friends screen can consume it once the user is authenticated.
///
/// Accepted shapes:
///   - Universal Link: `https://xomify.xomware.com/invite/<code>`
///   - Custom scheme:  `xomify://invite/<code>`
///
/// Any invite code captured here is "pending" until the Friends screen sees it
/// and either auto-accepts (if authenticated) or waits for login. After the
/// code is handed off, callers clear `pendingInviteCode` via `consume()`.
@Observable
@MainActor
final class InviteCoordinator {

    /// Shared singleton — matches the rest of the app's `.shared` service pattern.
    static let shared = InviteCoordinator()

    /// Host for Universal Link-style invite URLs.
    static let universalLinkHost = "xomify.xomware.com"

    /// Custom URL scheme (shared with Spotify OAuth callback, disambiguated by path).
    static let customScheme = "xomify"

    /// Captured invite code from the most recent deep link. Cleared via `consume()`
    /// once the Friends screen has handled it.
    private(set) var pendingInviteCode: String?

    private init() {}

    /// Parse an incoming URL and, if it's an invite link, capture the code.
    /// Safe to call with any URL — non-invite URLs are ignored.
    /// - Returns: `true` if the URL was recognized as an invite link.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let code = Self.extractInviteCode(from: url) else {
            return false
        }
        pendingInviteCode = code
        print("🔗 InviteCoordinator: captured invite code \(code.prefix(6))… from \(url.absoluteString)")
        return true
    }

    /// Pull the pending code (if any) and clear it. Intended for a one-shot
    /// consumer: once Friends has auto-acted on it, we don't want to re-act on
    /// a re-render.
    func consume() -> String? {
        defer { pendingInviteCode = nil }
        return pendingInviteCode
    }

    // MARK: - Parsing

    /// Extract an invite code from a deep-link URL, if the URL matches one of
    /// our known shapes. Returns `nil` for unrelated URLs.
    ///
    /// Accepts:
    ///   - `https://xomify.xomware.com/invite/<code>` (Universal Link)
    ///   - `xomify://invite/<code>` (custom scheme)
    static func extractInviteCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased()

        // Universal Link shape — path starts with /invite/<code>
        if scheme == "https", host == universalLinkHost {
            return inviteCode(fromPath: components.path)
        }

        // Custom scheme shape — xomify://invite/<code>
        // Note: for custom schemes `host` is typically the authority, so the
        // <code> might land in `host` or in `path` depending on URL shape.
        // We accept both `xomify://invite/<code>` (host=invite, path=/<code>)
        // and `xomify:///invite/<code>` (empty host, path=/invite/<code>).
        if scheme == customScheme {
            if host == "invite" {
                let trimmed = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return trimmed.isEmpty ? nil : trimmed
            }
            if host?.isEmpty ?? true {
                return inviteCode(fromPath: components.path)
            }
        }

        return nil
    }

    /// Given a path like `/invite/<code>` (or `/invite/<code>/`), return `<code>`.
    private static func inviteCode(fromPath path: String) -> String? {
        let parts = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count >= 2, parts[0].lowercased() == "invite" else { return nil }
        let code = parts[1]
        return code.isEmpty ? nil : code
    }
}
