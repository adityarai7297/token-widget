import Foundation

actor UsageService {
    static let shared = UsageService()

    private let oauthUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let cliUserAgent = CredentialStore.cliUserAgent
    private var cached: UsageResponse?
    private var cachedAt: Date?
    /// Background fetches can reuse a recent response; manual refresh never should.
    /// Keep short so the widget tracks the dashboard without hammering the API.
    private let softCacheInterval: TimeInterval = 45
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    func invalidateCache() {
        cached = nil
        cachedAt = nil
    }

    func fetch(force: Bool = false) async throws -> (UsageResponse, ClaudeOAuthBlock) {
        if !force,
           let cached,
           let cachedAt,
           Date().timeIntervalSince(cachedAt) < softCacheInterval {
            let oauth = try CredentialStore.loadOAuth()
            return (cached, oauth)
        }

        if force {
            invalidateCache()
        }

        // Do not hammer on 429 — retries deepen the lockout. One try; caller can retry later.
        return try await fetchOnce()
    }

    private func fetchOnce() async throws -> (UsageResponse, ClaudeOAuthBlock) {
        try Task.checkCancellation()
        let oauth = try await CredentialStore.refreshOAuthIfNeeded()
        var request = URLRequest(url: oauthUsageURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(oauth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(cliUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("cli", forHTTPHeaderField: "x-app")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        if status == 401 || status == 403 {
            let refreshed = try await CredentialStore.refreshOAuthIfNeeded(force: true)
            var retry = request
            retry.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            let (data2, response2) = try await session.data(for: retry)
            let status2 = (response2 as? HTTPURLResponse)?.statusCode ?? -1
            if status2 == 429 { throw UsageError.rateLimited }
            guard status2 == 200 else {
                throw UsageError.http(status2, String(data: data2, encoding: .utf8) ?? "")
            }
            let usage = try JSONDecoder().decode(UsageResponse.self, from: data2)
            cached = usage
            cachedAt = Date()
            return (usage, refreshed)
        }

        if status == 429 { throw UsageError.rateLimited }
        guard status == 200 else {
            throw UsageError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
        cached = usage
        cachedAt = Date()
        return (usage, oauth)
    }
}

enum UsageError: LocalizedError {
    case http(Int, String)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "Usage API \(code): \(body.prefix(120))"
        case .rateLimited:
            return "Rate limited by Claude — try again in a moment"
        }
    }
}
