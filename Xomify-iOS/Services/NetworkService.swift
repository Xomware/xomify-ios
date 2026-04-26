import Foundation

/// Handles all network requests to Spotify API and Xomify backend
actor NetworkService {
    
    // MARK: - Singleton
    
    static let shared = NetworkService()
    
    private init() {}
    
    // MARK: - Base URLs
    
    private let spotifyApiBaseUrl = "https://api.spotify.com/v1"
    
    // MARK: - HTTP Methods
    
    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }
    
    // MARK: - Errors
    
    enum NetworkError: LocalizedError {
        case unauthorized
        case noData
        case decodingError(Error)
        case serverError(statusCode: Int, message: String)
        case unknown(Error)
        
        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Not authenticated. Please log in again."
            case .noData:
                return "No data received from server."
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            case .serverError(let code, let message):
                return "Server error (\(code)): \(message)"
            case .unknown(let error):
                return error.localizedDescription
            }
        }
    }
    
    // MARK: - Spotify API Requests
    
    /// Make an authenticated request to Spotify API
    func spotifyRequest<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        body: [String: Any]? = nil
    ) async throws -> T {
        let token = try await getValidSpotifyToken()
        
        let url = URL(string: "\(spotifyApiBaseUrl)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        return try await performRequest(request)
    }
    
    /// GET request to Spotify
    func spotifyGet<T: Decodable>(_ endpoint: String, queryParams: [String: String]? = nil) async throws -> T {
        var fullEndpoint = endpoint
        
        if let params = queryParams, !params.isEmpty {
            let queryString = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            if endpoint.contains("?") {
                fullEndpoint += "&\(queryString)"
            } else {
                fullEndpoint += "?\(queryString)"
            }
        }
        
        return try await spotifyRequest(endpoint: fullEndpoint, method: .get)
    }
    
    /// POST request to Spotify
    func spotifyPost<T: Decodable>(_ endpoint: String, body: [String: Any]) async throws -> T {
        try await spotifyRequest(endpoint: endpoint, method: .post, body: body)
    }

    /// POST request to Spotify that does not include a JSON body and does not
    /// expect a JSON response. Used by endpoints like `/me/player/queue` where
    /// parameters live in the query string and the server returns 204. Throws
    /// `NetworkError.serverError` with the status code preserved on failure.
    func spotifyPostNoBody(_ endpoint: String) async throws {
        let token = try await getValidSpotifyToken()

        guard let url = URL(string: "\(spotifyApiBaseUrl)\(endpoint)") else {
            throw NetworkError.unknown(NSError(domain: "Invalid URL", code: 0))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown(NSError(domain: "Invalid response", code: 0))
        }

        if httpResponse.statusCode == 401 {
            throw NetworkError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "POST failed"
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }
    
    /// PUT request to Spotify (no response body)
    func spotifyPut(_ endpoint: String, body: [String: Any]) async throws {
        let token = try await getValidSpotifyToken()
        
        let url = URL(string: "\(spotifyApiBaseUrl)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "PUT failed")
        }
    }
    
    /// PUT request for uploading images (Base64 JPEG)
    func spotifyPutImage(_ endpoint: String, imageBase64: String) async throws {
        let token = try await getValidSpotifyToken()
        
        // Clean the base64 string
        let cleanBase64 = imageBase64
            .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
            .replacingOccurrences(of: "data:image/png;base64,", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        let url = URL(string: "\(spotifyApiBaseUrl)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = cleanBase64.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Image upload failed"
            throw NetworkError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: message)
        }
        
        print("✅ NetworkService: Uploaded playlist cover image")
    }
    
    /// DELETE request to Spotify (no response body)
    func spotifyDelete(_ endpoint: String, body: [String: Any]? = nil) async throws {
        let token = try await getValidSpotifyToken()
        
        let url = URL(string: "\(spotifyApiBaseUrl)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "DELETE failed")
        }
    }
    
    // MARK: - Xomify API Requests
    
    /// Get Xomify API base URL from config. Bearer header now resolves to the
    /// per-user JWT minted via `POST /auth/login` when present, falling back
    /// to the static `XOMIFY_API_TOKEN` from `secrets.xcconfig` so requests
    /// keep working on fresh installs and during the (0a)→(1l) migration.
    @MainActor
    private func getXomifyConfig() -> (baseUrl: String, token: String) {
        let apiId = Bundle.main.object(forInfoDictionaryKey: "XOMIFY_API_ID") as? String ?? ""
        let baseUrl = "https://\(apiId).execute-api.us-east-1.amazonaws.com/dev"
        let bearer = AuthService.shared.currentXomifyBearerToken()
        return (baseUrl, "Bearer \(bearer)")
    }
    
    /// GET request to Xomify API
    func xomifyGet<T: Decodable>(_ endpoint: String, queryParams: [String: String]? = nil) async throws -> T {
        let config = await getXomifyConfig()
        
        var components = URLComponents(string: "\(config.baseUrl)\(endpoint)")!
        
        if let params = queryParams {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        guard let url = components.url else {
            throw NetworkError.unknown(NSError(domain: "Invalid URL", code: 0))
        }
        
        print("🌐 XomifyAPI GET: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.token, forHTTPHeaderField: "Authorization")
        
        return try await performXomifyRequest(request)
    }
    
    /// POST request to Xomify API
    func xomifyPost<T: Decodable>(_ endpoint: String, body: [String: Any]) async throws -> T {
        let config = await getXomifyConfig()

        let url = URL(string: "\(config.baseUrl)\(endpoint)")!

        print("🌐 XomifyAPI POST: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await performXomifyRequest(request)
    }

    /// PUT request to Xomify API. Used for endpoints the API Gateway only
    /// binds to PUT (e.g. `/groups/update`) — sending POST there would 403
    /// before the lambda ever sees the body.
    func xomifyPut<T: Decodable>(_ endpoint: String, body: [String: Any]) async throws -> T {
        let config = await getXomifyConfig()

        let url = URL(string: "\(config.baseUrl)\(endpoint)")!

        print("🌐 XomifyAPI PUT: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await performXomifyRequest(request)
    }

    /// DELETE with a JSON body. Some newer endpoints (e.g. `/shares/comments`)
    /// parse identifiers from the body so the path stays clean. URLSession
    /// happily sends a body on DELETE — API Gateway forwards it through.
    func xomifyDelete<T: Decodable>(_ endpoint: String, body: [String: Any]) async throws -> T {
        let config = await getXomifyConfig()

        let url = URL(string: "\(config.baseUrl)\(endpoint)")!

        print("🌐 XomifyAPI DELETE: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await performXomifyRequest(request, allowEmpty: true)
    }

    /// DELETE request to Xomify API. Backend DELETE handlers read
    /// `queryStringParameters`, not a JSON body — pass identifiers via
    /// `queryParams`. Most DELETE endpoints return `204 No Content`, so
    /// this helper accepts an empty body and synthesises a typed result
    /// when the response carries no payload.
    func xomifyDelete<T: Decodable>(_ endpoint: String, queryParams: [String: String] = [:]) async throws -> T {
        let config = await getXomifyConfig()

        var components = URLComponents(string: "\(config.baseUrl)\(endpoint)")!
        if !queryParams.isEmpty {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw NetworkError.unknown(NSError(domain: "Invalid URL", code: 0))
        }

        print("🌐 XomifyAPI DELETE: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.token, forHTTPHeaderField: "Authorization")

        return try await performXomifyRequest(request, allowEmpty: true)
    }
    
    /// Perform Xomify API request. `allowEmpty` covers 204-style endpoints
    /// (group delete, remove-member, remove-song) where the server
    /// legitimately returns no body — we synthesise `{}` so the generic
    /// `T` decoder can still materialise a `SuccessResponse`-like struct
    /// with all-optional fields.
    ///
    /// On a 401 from the backend, attempts to recover **once**: refreshes the
    /// Spotify access token, re-mints the per-user Xomify JWT via
    /// `POST /auth/login`, swaps the new bearer onto the request, and retries
    /// the same call. If the retried request still 401s the failure is
    /// propagated — we never loop. This keeps users from being silently
    /// kicked out when the JWT (TTL=7d) expires.
    private func performXomifyRequest<T: Decodable>(
        _ request: URLRequest,
        allowEmpty: Bool = false,
        retryOn401: Bool = true
    ) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unknown(NSError(domain: "Invalid response", code: 0))
            }

            print("🌐 XomifyAPI Response: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401, retryOn401 {
                if let retried: T = try await retryAfterReauth(
                    originalRequest: request,
                    allowEmpty: allowEmpty
                ) {
                    return retried
                }
                // Fall through — the retry itself threw or the reauth could
                // not produce a fresh bearer; surface the original 401.
                let message = String(data: data, encoding: .utf8) ?? "Unauthorized"
                throw NetworkError.serverError(statusCode: 401, message: message)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ XomifyAPI Error: \(message)")
                throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: message)
            }

            let payload: Data = (allowEmpty && data.isEmpty) ? Data("{}".utf8) : data

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(T.self, from: payload)
            } catch {
                print("❌ NetworkService: Xomify decoding error - \(error)")
                if let jsonString = String(data: payload, encoding: .utf8) {
                    print("Raw JSON: \(jsonString.prefix(500))")
                }
                throw NetworkError.decodingError(error)
            }

        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.unknown(error)
        }
    }

    /// Single-shot reauth + retry for a 401. Refreshes the Spotify access
    /// token (so we have a known-good upstream credential), mints a fresh
    /// Xomify JWT, swaps the Authorization header on the original request,
    /// and replays it. Returns `nil` if reauth could not produce a new bearer
    /// — caller surfaces the original 401.
    private func retryAfterReauth<T: Decodable>(
        originalRequest: URLRequest,
        allowEmpty: Bool
    ) async throws -> T? {
        print("🔄 XomifyAPI: 401 received — attempting reauth + single retry")

        // Step 1: ensure a fresh Spotify access token. If the refresh fails
        // there's nothing we can do; bail and let the original 401 propagate.
        do {
            try await AuthService.shared.refreshAccessToken()
        } catch {
            print("⚠️ XomifyAPI: Spotify refresh failed during 401-retry: \(error)")
            return nil
        }

        // Step 2: mint a fresh Xomify JWT off the new Spotify access token.
        let minted = await AuthService.shared.mintXomifyJwt()
        guard minted else {
            print("⚠️ XomifyAPI: JWT mint failed during 401-retry")
            return nil
        }

        // Step 3: swap the Authorization header onto a copy of the original
        // request and replay. `retryOn401: false` ensures we never recurse.
        var retried = originalRequest
        let bearer = AuthService.shared.currentXomifyBearerToken()
        retried.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")

        return try await performXomifyRequest(retried, allowEmpty: allowEmpty, retryOn401: false)
    }
    
    // MARK: - Token Management
    
    @MainActor
    private func getValidSpotifyToken() async throws -> String {
        let authService = AuthService.shared
        
        guard let token = authService.accessToken else {
            throw NetworkError.unauthorized
        }
        
        if authService.isTokenExpired {
            try await authService.refreshAccessToken()
            guard let newToken = authService.accessToken else {
                throw NetworkError.unauthorized
            }
            return newToken
        }
        
        return token
    }
    
    // MARK: - Request Execution
    
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unknown(NSError(domain: "Invalid response", code: 0))
            }
            
            if httpResponse.statusCode == 401 {
                throw NetworkError.unauthorized
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: message)
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(T.self, from: data)
            } catch {
                print("❌ NetworkService: Decoding error - \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Raw JSON: \(jsonString.prefix(500))")
                }
                throw NetworkError.decodingError(error)
            }
            
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.unknown(error)
        }
    }
}
