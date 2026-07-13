import Foundation
import Security
import CryptoKit

/// Owns OAuth tokens in an app-controlled credentials file (avoids Keychain UI hangs).
enum CredentialStore {
    static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = URL(string: "https://claude.com/cai/oauth/authorize")!
    static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    // Legacy console host returns 404 now — keep only as last resort.
    static let legacyTokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    static let cliUserAgent = "claude-cli/2.1.170 (external, cli)"
    static let scopes = [
        "org:create_api_key",
        "user:profile",
        "user:inference",
        "user:sessions:claude_code",
        "user:mcp_servers",
        "user:file_upload",
    ].joined(separator: " ")
    static let expirySkewMs: Int64 = 5 * 60 * 1000

    private static var credentialsURL: URL {
        SharedStore.directoryURL.appendingPathComponent("credentials.json")
    }

    // MARK: PKCE

    struct PKCESession: Equatable {
        let verifier: String
        let challenge: String
        let state: String
    }

    static func makePKCE() -> PKCESession {
        let verifier = randomBase64URL(32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64URLEncodedString()
        let state = randomBase64URL(32)
        return PKCESession(verifier: verifier, challenge: challenge, state: state)
    }

    static func authorizeURL(pkce: PKCESession) -> URL {
        var comps = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: oauthClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        return comps.url!
    }

    // MARK: Persistence

    static func hasCredentials() -> Bool {
        (try? loadOAuth()) != nil
    }

    static func loadOAuth() throws -> ClaudeOAuthBlock {
        let data = try Data(contentsOf: credentialsURL)
        return try JSONDecoder().decode(ClaudeOAuthBlock.self, from: data)
    }

    static func saveOwnedOAuth(_ oauth: ClaudeOAuthBlock) throws {
        try FileManager.default.createDirectory(at: SharedStore.directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(oauth)
        try data.write(to: credentialsURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsURL.path)
    }

    static func clearOwnedOAuth() {
        try? FileManager.default.removeItem(at: credentialsURL)
    }

    /// Pull tokens from an existing Claude Code login via the `security` CLI
    /// (avoids Keychain UI hangs from SecItem APIs).
    static func importFromClaudeCode() throws -> ClaudeOAuthBlock {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AuthError.noOAuthBlock
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauthDict = root["claudeAiOauth"] as? [String: Any],
              let access = oauthDict["accessToken"] as? String,
              let refresh = oauthDict["refreshToken"] as? String,
              !access.isEmpty, !refresh.isEmpty
        else {
            throw AuthError.noOAuthBlock
        }
        let expires = (oauthDict["expiresAt"] as? Int64)
            ?? (oauthDict["expiresAt"] as? Int).map(Int64.init)
            ?? (oauthDict["expiresAt"] as? Double).map { Int64($0) }
            ?? 0
        let block = ClaudeOAuthBlock(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expires,
            scopes: oauthDict["scopes"] as? [String],
            subscriptionType: oauthDict["subscriptionType"] as? String,
            rateLimitTier: oauthDict["rateLimitTier"] as? String
        )
        try saveOwnedOAuth(block)
        return block
    }

    /// True when clipboard looks like a Claude OAuth code (`code` or `code#state`).
    static func looksLikeAuthCode(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20, trimmed.count < 2000 else { return false }
        if trimmed.lowercased() == "true" { return false }
        // Reject URLs / junk.
        if trimmed.contains("://") || trimmed.contains(" ") { return false }
        let codePart = trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? trimmed
        // Auth codes are typically URL-safe base64-ish.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return codePart.unicodeScalars.allSatisfy { allowed.contains($0) } && codePart.count >= 20
    }

    static func isExpired(_ oauth: ClaudeOAuthBlock, nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Bool {
        oauth.expiresAt <= nowMs + expirySkewMs
    }

    // MARK: Token exchange / refresh

    static func exchangeCode(_ code: String, state: String?, pkce: PKCESession) async throws -> ClaudeOAuthBlock {
        var authCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        var returnedState = state ?? pkce.state
        if authCode.contains("#") {
            let parts = authCode.split(separator: "#", maxSplits: 1).map(String.init)
            authCode = parts[0]
            if parts.count > 1 { returnedState = parts[1] }
        }

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": authCode,
            "redirect_uri": redirectURI,
            "client_id": oauthClientID,
            "code_verifier": pkce.verifier,
            "state": returnedState,
        ]
        return try await postToken(body: body)
    }

    static func refreshOAuthIfNeeded(force: Bool = false) async throws -> ClaudeOAuthBlock {
        var oauth = try loadOAuth()
        if !force && !isExpired(oauth) {
            return oauth
        }
        oauth = try await refreshOAuth(using: oauth.refreshToken, preserving: oauth)
        try saveOwnedOAuth(oauth)
        return oauth
    }

    static func refreshOAuth(using refreshToken: String, preserving existing: ClaudeOAuthBlock?) async throws -> ClaudeOAuthBlock {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": oauthClientID,
        ]
        var oauth = try await postToken(body: body)
        oauth.scopes = existing?.scopes ?? oauth.scopes
        oauth.subscriptionType = existing?.subscriptionType ?? oauth.subscriptionType
        oauth.rateLimitTier = existing?.rateLimitTier ?? oauth.rateLimitTier
        return oauth
    }

    private static func postToken(body: [String: String]) async throws -> ClaudeOAuthBlock {
        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error = AuthError.refreshFailed(status: -1, body: "")

        // Prefer platform host; only fall back if it is unreachable (network), not on 4xx.
        let urls = [tokenURL, legacyTokenURL]
        for (index, url) in urls.enumerated() {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(cliUserAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if status == 200 {
                    let token = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
                    let expiresIn = token.expiresIn ?? 28_800
                    let expiresAt = Int64(Date().timeIntervalSince1970 * 1000) + Int64(expiresIn) * 1000
                    return ClaudeOAuthBlock(
                        accessToken: token.accessToken,
                        refreshToken: token.refreshToken ?? body["refresh_token"] ?? "",
                        expiresAt: expiresAt,
                        scopes: nil,
                        subscriptionType: nil,
                        rateLimitTier: nil
                    )
                }
                lastError = AuthError.refreshFailed(
                    status: status,
                    body: String((String(data: data, encoding: .utf8) ?? "").prefix(200))
                )
                // Don't bother with the dead legacy host on client errors from platform.
                if index == 0, (400...499).contains(status), status != 404 {
                    throw lastError
                }
            } catch let error as AuthError {
                throw error
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func randomBase64URL(_ bytes: Int) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer)
        return Data(buffer).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum AuthError: LocalizedError {
    case noOAuthBlock
    case keychainWriteFailed(OSStatus)
    case refreshFailed(status: Int, body: String)
    case loginCancelled

    var errorDescription: String? {
        switch self {
        case .noOAuthBlock:
            return "Sign in to Claude to continue"
        case .keychainWriteFailed(let status):
            return "Could not save credentials (\(status))"
        case .refreshFailed(let status, _):
            return "Auth failed (\(status))"
        case .loginCancelled:
            return "Sign-in cancelled"
        }
    }
}
