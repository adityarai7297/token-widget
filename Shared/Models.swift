import Foundation

// MARK: - Usage models (matches Claude usage / OAuth responses)

struct UsageWindow: Codable, Equatable {
    let utilization: Double?
    let resetsAt: String?
    let limitDollars: Double?
    let usedDollars: Double?
    let remainingDollars: Double?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
        case limitDollars = "limit_dollars"
        case usedDollars = "used_dollars"
        case remainingDollars = "remaining_dollars"
    }

    var percent: Int {
        Int(min(100, max(0, utilization ?? 0)).rounded())
    }

    var resetDate: Date? {
        guard let resetsAt else { return nil }
        return ISO8601Parsing.date(from: resetsAt)
    }
}

struct UsageScopeModel: Codable, Equatable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

struct UsageScope: Codable, Equatable {
    let model: UsageScopeModel?
}

struct UsageLimit: Codable, Equatable, Identifiable {
    let kind: String?
    let group: String?
    let percent: Double?
    let resetsAt: String?
    let scope: UsageScope?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case kind, group, percent, scope
        case resetsAt = "resets_at"
        case isActive = "is_active"
    }

    var id: String {
        [kind, group, scope?.model?.displayName].compactMap { $0 }.joined(separator: "|")
    }

    var percentInt: Int {
        Int(min(100, max(0, percent ?? 0)).rounded())
    }

    var title: String {
        if let name = scope?.model?.displayName, !name.isEmpty {
            return name
        }
        switch kind {
        case "session": return "5-hour"
        case "weekly_all": return "Weekly"
        case "weekly_scoped": return "Weekly model"
        default: return kind ?? group ?? "Limit"
        }
    }

    var resetDate: Date? {
        guard let resetsAt else { return nil }
        return ISO8601Parsing.date(from: resetsAt)
    }
}

struct ExtraUsage: Codable, Equatable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization, currency
    }
}

struct UsageSpend: Codable, Equatable {
    let percent: Double?
    let enabled: Bool?
}

struct UsageResponse: Codable, Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let extraUsage: ExtraUsage?
    let limits: [UsageLimit]?
    let spend: UsageSpend?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
        case limits, spend
    }

    /// Prefer the richer `limits` array when present; otherwise synthesize from windows.
    var displayRows: [UsageLimit] {
        if let limits, !limits.isEmpty {
            return limits.filter { ($0.percent ?? 0) >= 0 }
        }
        var rows: [UsageLimit] = []
        if let fiveHour {
            rows.append(UsageLimit(
                kind: "session", group: "session", percent: fiveHour.utilization,
                resetsAt: fiveHour.resetsAt, scope: nil, isActive: nil
            ))
        }
        if let sevenDay {
            rows.append(UsageLimit(
                kind: "weekly_all", group: "weekly", percent: sevenDay.utilization,
                resetsAt: sevenDay.resetsAt, scope: nil, isActive: nil
            ))
        }
        if let sevenDaySonnet, sevenDaySonnet.utilization != nil {
            rows.append(UsageLimit(
                kind: "weekly_scoped", group: "weekly", percent: sevenDaySonnet.utilization,
                resetsAt: sevenDaySonnet.resetsAt,
                scope: UsageScope(model: UsageScopeModel(id: nil, displayName: "Sonnet")),
                isActive: nil
            ))
        }
        if let sevenDayOpus, sevenDayOpus.utilization != nil {
            rows.append(UsageLimit(
                kind: "weekly_scoped", group: "weekly", percent: sevenDayOpus.utilization,
                resetsAt: sevenDayOpus.resetsAt,
                scope: UsageScope(model: UsageScopeModel(id: nil, displayName: "Opus")),
                isActive: nil
            ))
        }
        return rows
    }
}

// MARK: - Auth

struct ClaudeOAuthBlock: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Int64
    var scopes: [String]?
    var subscriptionType: String?
    var rateLimitTier: String?

    enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, expiresAt, scopes, subscriptionType, rateLimitTier
    }
}

struct ClaudeCredentialsFile: Codable {
    var claudeAiOauth: ClaudeOAuthBlock?
    // Preserve unknown keys via round-trip of raw JSON elsewhere.
}

struct OAuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Helpers

enum ISO8601Parsing {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String) -> Date? {
        fractional.date(from: string) ?? basic.date(from: string)
    }
}

enum Formatters {
    /// Full countdown with second precision (menu / tooltips).
    static func countdown(until date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds == 0 { return "soon" }
        let d = seconds / 86_400
        let h = (seconds % 86_400) / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if d > 0 { return "\(d)d \(h)h \(m)m \(s)s" }
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    /// Compact remaining time for the menu-bar strip (second-accurate under 1h).
    static func compactCountdown(until date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds == 0 { return "0s" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        if m > 0 {
            return String(format: "%dm %02ds", m, s)
        }
        return "\(s)s"
    }

    /// Back-compat alias.
    static func compactMinutes(until date: Date?, now: Date = Date()) -> String {
        compactCountdown(until: date, now: now)
    }

    static func relativeUpdated(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let s = Int(now.timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }
}
