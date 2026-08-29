import Foundation

/// Client for the Xomtracks backend — the tracks people send you over iMessage.
///
/// This is a DIFFERENT backend from Xomify's own. Xomify's `/shares/*` is the
/// retired in-app group-sharing system; Xomtracks ingests real messages and is
/// what the web app's Shares page has always shown. iOS had no client for it,
/// which is why its feed showed songs from groups that no longer exist.
///
/// Auth is the same Xomify JWT the rest of the app uses — the Xomtracks API
/// trusts it, exactly as the web app's interceptor assumes.
// Deliberately NOT @MainActor: this class does no UI work, and isolating it
// would isolate the Codable conformances of everything it decodes, which the
// Sendable requirements on the generic transport then reject.
final class XomtracksService: Sendable {

    static let shared = XomtracksService()

    /// A stable public hostname, not a secret and not per-environment — the web
    /// app hardcodes the same value in its environment file.
    private let baseURL = "https://api.xomtracks.xomware.com"

    private init() {}

    /// `GET /shares/list` — one direction within a time window.
    func listShares(direction: XtDirection, window: XtTimeWindow) async throws -> [XtShare] {
        let response: XtEnvelope<XtSharesListResponse> = try await get(
            "/shares/list",
            query: ["direction": direction.rawValue, "window": window.rawValue]
        )
        return try unwrap(response).shares ?? []
    }

    /// `POST /heard/set` — mark a track played, or un-mark it.
    @discardableResult
    func setHeard(trackKey: String, heard: Bool) async throws -> Bool {
        let response: XtEnvelope<XtHeardState> = try await post(
            "/heard/set",
            body: ["trackKey": trackKey, "heard": heard]
        )
        return try unwrap(response).heard ?? heard
    }

    // MARK: - Transport

    /// Xomtracks answers in an envelope and reports failures INSIDE it, with
    /// HTTP 200. Returning `data` without checking `error` would surface a
    /// failure as an empty list.
    private func unwrap<T>(_ envelope: XtEnvelope<T>) throws -> T {
        if let error = envelope.error {
            throw NetworkService.NetworkError.serverError(
                statusCode: error.status ?? 500,
                message: error.message ?? "Xomtracks request failed"
            )
        }
        guard let data = envelope.data else {
            throw NetworkService.NetworkError.noData
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        var components = URLComponents(string: baseURL + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            throw NetworkService.NetworkError.unknown(
                NSError(domain: "Invalid Xomtracks URL", code: 0)
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await send(request)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw NetworkService.NetworkError.unknown(
                NSError(domain: "Invalid Xomtracks URL", code: 0)
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        request.setValue(
            "Bearer \(AuthService.shared.currentXomifyBearerToken())",
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkService.NetworkError.noData
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw NetworkService.NetworkError.unauthorized }
            throw NetworkService.NetworkError.serverError(
                statusCode: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
