import Foundation

/// Snapshot cached for the menu-bar UI.
struct UsageSnapshot: Codable, Equatable {
    enum Status: String, Codable {
        case ok
        case needsLogin
        case error
    }

    var status: Status
    var updatedAt: Date
    var subscription: String?
    var message: String?
    var rows: [SnapshotRow]

    struct SnapshotRow: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var percent: Int
        var resetsAt: Date?
        var isActive: Bool
    }

    static var needsLogin: UsageSnapshot {
        UsageSnapshot(
            status: .needsLogin,
            updatedAt: Date(),
            subscription: nil,
            message: "Sign in to see Claude usage",
            rows: []
        )
    }

    static func from(usage: UsageResponse, subscription: String?) -> UsageSnapshot {
        let rows = usage.displayRows.map { limit in
            SnapshotRow(
                id: limit.id,
                title: limit.title,
                percent: limit.percentInt,
                resetsAt: limit.resetDate,
                isActive: limit.isActive == true
            )
        }
        return UsageSnapshot(
            status: .ok,
            updatedAt: Date(),
            subscription: subscription,
            message: nil,
            rows: rows
        )
    }

    /// Rows ordered for the menu-bar bars: 5H, W, F (model).
    var statusBarRows: [(label: String, percent: Int, resetsAt: Date?)] {
        var result: [(String, Int, Date?)] = []
        if let session = rows.first(where: { $0.id.contains("session") || $0.title.lowercased().contains("5") }) {
            result.append(("5H", session.percent, session.resetsAt))
        }
        if let week = rows.first(where: { $0.id.contains("weekly_all") || $0.title.lowercased() == "weekly" }) {
            result.append(("W", week.percent, week.resetsAt))
        }
        if let model = rows.first(where: {
            let t = $0.title.lowercased()
            return !$0.id.contains("session")
                && !$0.id.contains("weekly_all")
                && t != "weekly"
                && !t.contains("5-hour")
                && !t.contains("5h")
        }) {
            let letter = String(model.title.prefix(1)).uppercased()
            result.append((letter.isEmpty ? "F" : letter, model.percent, model.resetsAt))
        }
        if result.isEmpty {
            let labels = ["5H", "W", "F"]
            for (idx, row) in rows.prefix(3).enumerated() {
                result.append((labels[idx], row.percent, row.resetsAt))
            }
        }
        return result
    }

    /// What the menu-bar strip should show.
    /// Weekly at 100% owns the strip (percent + countdown) until it resets.
    var menuBarPrimary: (label: String, percent: Int, resetsAt: Date?, tooltipPrefix: String)? {
        let bars = statusBarRows
        if let week = bars.first(where: { $0.label == "W" }), week.percent >= 100 {
            return ("W", week.percent, week.resetsAt, "Weekly")
        }
        if let fiveHour = bars.first(where: { $0.label == "5H" }) ?? bars.first {
            let prefix = fiveHour.label == "5H" ? "5-hour" : fiveHour.label
            return (fiveHour.label, fiveHour.percent, fiveHour.resetsAt, prefix)
        }
        return nil
    }

    /// True when 5H or weekly is ≥90% and <100% (visual warning; does not change strip ownership).
    var isNearLimitWarning: Bool {
        let bars = statusBarRows
        let five = bars.first(where: { $0.label == "5H" })?.percent ?? 0
        let week = bars.first(where: { $0.label == "W" })?.percent ?? 0
        return UsageDisplay.isNearLimit(percent: five) || UsageDisplay.isNearLimit(percent: week)
    }
}

enum SharedStore {
    static var directoryURL: URL {
        let home: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        } else {
            home = URL(fileURLWithPath: "/Users/\(NSUserName())", isDirectory: true)
        }
        let url = home.appendingPathComponent("Library/Application Support/TokenWidget", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var snapshotURL: URL {
        directoryURL.appendingPathComponent("usage-snapshot.json")
    }

    static func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: [.atomic])
    }

    static func load() -> UsageSnapshot {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) else {
            return .needsLogin
        }
        return snapshot
    }
}
