import CryptoKit
import Foundation

/// Disposable on-disk JSON cache for the last N feed items per filter.
///
/// Lives in `.cachesDirectory` — the OS is free to evict it under memory
/// pressure. Read-through on cold launch, written after every successful
/// `getFeed` call. Corrupt files are swallowed (next successful fetch will
/// overwrite).
actor FeedCacheService {

    // MARK: - Singleton

    static let shared = FeedCacheService()

    // MARK: - Tunables

    /// Hard cap on shares persisted per filter key. Keeps the on-disk blob
    /// tiny and bounds worst-case parse cost on cold launch.
    static let maxSharesPerFilter: Int = 50

    // MARK: - State

    private let fileManager: FileManager

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Load cached shares for a filter key. Returns `nil` when no cache exists
    /// or the existing blob is corrupt / out-of-version.
    func load(filterKey: String) -> [Share]? {
        guard let url = cacheURL(for: filterKey) else { return nil }
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let cached = try decoder.decode(CachedFeed.self, from: data)
            guard cached.version == CachedFeed.currentVersion else {
                // Version drift — drop it silently; next fetch rewrites.
                try? fileManager.removeItem(at: url)
                return nil
            }
            return cached.shares
        } catch {
            // Corrupt / schema-drift — best-effort cleanup then signal miss.
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    /// Persist up to `maxSharesPerFilter` shares for a filter key. Overwrites
    /// existing file. Errors are swallowed — the cache is best-effort.
    func save(_ shares: [Share], forKey filterKey: String) {
        guard let url = cacheURL(for: filterKey) else { return }

        let capped = Array(shares.prefix(Self.maxSharesPerFilter))
        let envelope = CachedFeed(filterKey: filterKey, shares: capped)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(envelope)
            try ensureDirectory(for: url)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Intentionally swallowed — disposable cache.
        }
    }

    /// Drop the cache for a single filter key. Used by tests + the "sign out"
    /// cleanup path (future).
    func clear(filterKey: String) {
        guard let url = cacheURL(for: filterKey) else { return }
        try? fileManager.removeItem(at: url)
    }

    /// Drop every cached filter. Intended for tests.
    func clearAll() {
        guard let dir = cacheDirectory() else { return }
        guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("feed-cache-") {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Paths

    /// Hash the filter key so file names never leak group IDs / emails to
    /// casual filesystem inspection. Deterministic — same key always maps to
    /// same file.
    private func hash(_ key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func cacheDirectory() -> URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private func cacheURL(for filterKey: String) -> URL? {
        guard let dir = cacheDirectory() else { return nil }
        return dir.appendingPathComponent("feed-cache-\(hash(filterKey)).json")
    }

    private func ensureDirectory(for fileURL: URL) throws {
        let dir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
