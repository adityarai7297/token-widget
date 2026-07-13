import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var loginWindow: NSWindow?
    private var pollTimer: Timer?
    private var uiTickTimer: Timer?
    private var isRefreshing = false
    private var refreshGeneration = 0
    private var refreshTask: Task<Void, Never>?
    private var didBootstrap = false
    private var lastRefreshNote: String?
    private var displayedSnapshot: UsageSnapshot?
    private var menuRowViews: [MenuUsageRowView] = []
    private var updatedAtMenuItem: NSMenuItem?
    private var noteMenuItem: NSMenuItem?
    private var isMenuOpen = false
    private var lastPaintedStatusSignature: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        bootstrap()
    }

    /// Called from didFinishLaunching and also directly from main() so startup
    /// still happens if the launch notification was already delivered.
    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        NSApp.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: SharedStore.directoryURL, withIntermediateDirectories: true)
        Self.log("launch begin")
        setupStatusItem()
        // Show last-known usage immediately (don't wait on network).
        applySnapshot(SharedStore.load(), rebuildMenuIfNeeded: true)

        // Keychain prompts can block; do credential work after the run loop is alive.
        DispatchQueue.main.async { [weak self] in
            self?.startAfterKeychainReady()
        }

        // Usage percentages: poll about once a minute (API soft-caches ~45s).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: false) }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }

        // Countdowns / cooldown ring: tick every second locally from resetsAt.
        uiTickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickUI() }
        }
        if let uiTickTimer {
            RunLoop.main.add(uiTickTimer, forMode: .common)
        }

        Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { _ in
            Task {
                _ = try? await CredentialStore.refreshOAuthIfNeeded()
            }
        }
    }

    private func startAfterKeychainReady() {
        // Prefer an existing Claude Code login before prompting.
        if !CredentialStore.hasCredentials(),
           let _ = try? CredentialStore.importFromClaudeCode() {
            Self.log("imported Claude Code credentials")
        }

        let hasCreds = CredentialStore.hasCredentials()
        Self.log("hasCredentials=\(hasCreds)")
        if !hasCreds {
            Self.log("no credentials → login")
            SharedStore.save(.needsLogin)
            openLogin()
        } else {
            let existing = SharedStore.load()
            // Pull fresh usage if cache is older than ~45s.
            let fresh = existing.status == .ok && Date().timeIntervalSince(existing.updatedAt) < 45
            Self.log("credentials present → refresh force=\(!fresh)")
            refresh(force: !fresh)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == AppConstants.urlScheme {
            let action = (url.host ?? url.path).lowercased()
            if action.contains("login") {
                if CredentialStore.hasCredentials() || (try? CredentialStore.importFromClaudeCode()) != nil {
                    Self.log("login URL with existing creds → refresh only")
                    refresh(force: true)
                } else {
                    openLogin()
                }
            } else {
                // refresh / default
                refresh(force: true)
            }
        }
    }

    private var statusBarView: StatusBarUsageView?

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "Claude Usage"
        }
        statusBarView = StatusBarUsageView(frame: .zero)
        statusItem = item
        rebuildMenu(with: SharedStore.load())
    }

    // MARK: - Menu live updates

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        tickUI()
        // Opening the menu should feel as fresh as the dashboard.
        let age = displayedSnapshot.map { Date().timeIntervalSince($0.updatedAt) } ?? .infinity
        if CredentialStore.hasCredentials(), age > 20 {
            refresh(force: true)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    private func rebuildMenu(with snapshot: UsageSnapshot) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menuRowViews.removeAll(keepingCapacity: true)
        updatedAtMenuItem = nil
        noteMenuItem = nil

        if snapshot.status == .ok {
            let header = snapshot.subscription.map { "Claude · \($0)" } ?? "Claude Usage"
            let headerItem = NSMenuItem(title: header, action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)
            menu.addItem(.separator())

            for row in snapshot.rows {
                let reset = Formatters.countdown(until: row.resetsAt)
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                let rowView = MenuUsageRowView(frame: .zero)
                rowView.configure(title: row.title, percent: row.percent, resetText: reset)
                item.view = rowView
                item.isEnabled = false
                menu.addItem(item)
                menuRowViews.append(rowView)
            }

            let updated = NSMenuItem(
                title: "Updated \(Formatters.relativeUpdated(snapshot.updatedAt))",
                action: nil,
                keyEquivalent: ""
            )
            updated.isEnabled = false
            menu.addItem(updated)
            updatedAtMenuItem = updated

            if let lastRefreshNote, !lastRefreshNote.isEmpty {
                let note = NSMenuItem(title: Self.compactMenuNote(lastRefreshNote), action: nil, keyEquivalent: "")
                note.isEnabled = false
                menu.addItem(note)
                noteMenuItem = note
            }
            menu.addItem(.separator())
        } else if snapshot.status == .needsLogin {
            let item = NSMenuItem(title: "Not signed in", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        } else if let message = snapshot.message {
            let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(menuRefresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Sign In…", action: #selector(menuLogin), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Sign Out", action: #selector(menuLogout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Token Widget", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func menuRefresh() {
        Self.log("manual refresh requested")
        refresh(force: true)
    }
    @objc private func menuLogin() { openLogin() }

    @objc private func menuLogout() {
        CredentialStore.clearOwnedOAuth()
        SharedStore.save(.needsLogin)
        applySnapshot(nil, rebuildMenuIfNeeded: true)
        openLogin()
    }

    func openLogin() {
        // Already signed in — never flash an auto-closing sheet.
        if CredentialStore.hasCredentials() {
            refresh(force: true)
            return
        }
        if (try? CredentialStore.importFromClaudeCode()) != nil {
            Self.log("openLogin imported Claude Code creds")
            refresh(force: true)
            return
        }

        if let loginWindow, loginWindow.isVisible {
            loginWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = LoginView(
            onSuccess: { [weak self] in
                self?.loginWindow?.close()
                self?.loginWindow = nil
                self?.refresh(force: true)
            },
            onCancel: { [weak self] in
                self?.loginWindow?.close()
                self?.loginWindow = nil
                if !CredentialStore.hasCredentials() {
                    SharedStore.save(.needsLogin)
                    self?.applySnapshot(nil, rebuildMenuIfNeeded: true)
                }
            }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Token Widget"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.center()
        window.isReleasedWhenClosed = false
        loginWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh(force: Bool) {
        // Background polls never interrupt an in-flight refresh.
        if !force && isRefreshing { return }

        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true

        refreshTask = Task { @MainActor in
            await refreshAsync(force: force, generation: generation)
            guard generation == refreshGeneration else { return }
            isRefreshing = false
        }
    }

    private func refreshAsync(force: Bool, generation: Int) async {
        Self.log("refreshAsync force=\(force) gen=\(generation)")
        guard CredentialStore.hasCredentials() else {
            Self.log("refresh aborted — no credentials")
            SharedStore.save(.needsLogin)
            applySnapshot(nil, rebuildMenuIfNeeded: true)
            openLogin()
            return
        }

        if force {
            lastRefreshNote = isMenuOpen ? nil : "Refreshing…"
            if !isMenuOpen {
                applySnapshot(SharedStore.load(), rebuildMenuIfNeeded: true)
            }
        }

        do {
            let (usage, oauth) = try await UsageService.shared.fetch(force: force)
            guard generation == refreshGeneration else {
                Self.log("refresh discarded stale gen=\(generation)")
                return
            }
            let snapshot = UsageSnapshot.from(usage: usage, subscription: prettyPlan(oauth))
            SharedStore.save(snapshot)
            lastRefreshNote = nil
            let bars = snapshot.statusBarRows.map { "\($0.label)=\($0.percent)" }.joined(separator: " ")
            Self.log("refresh ok \(bars)")
            applySnapshot(snapshot, rebuildMenuIfNeeded: true)
        } catch is CancellationError {
            Self.log("refresh cancelled gen=\(generation)")
        } catch let error as AuthError {
            guard generation == refreshGeneration else { return }
            Self.log("auth error \(error)")
            lastRefreshNote = error.localizedDescription
            SharedStore.save(.needsLogin)
            applySnapshot(nil, rebuildMenuIfNeeded: true)
            openLogin()
        } catch let error as UsageError {
            guard generation == refreshGeneration else { return }
            Self.log("usage error \(error)")
            switch error {
            case .http(let code, _) where code == 401 || code == 403:
                lastRefreshNote = "Session expired"
                SharedStore.save(.needsLogin)
                openLogin()
            case .rateLimited:
                lastRefreshNote = force
                    ? "Rate limited — try again soon"
                    : nil
                applySnapshot(SharedStore.load(), rebuildMenuIfNeeded: true)
            default:
                lastRefreshNote = error.localizedDescription
                var snap = SharedStore.load()
                if snap.status != .ok {
                    snap = UsageSnapshot(status: .error, updatedAt: Date(), subscription: nil, message: error.localizedDescription, rows: [])
                    SharedStore.save(snap)
                }
                applySnapshot(SharedStore.load(), rebuildMenuIfNeeded: true)
            }
        } catch {
            guard generation == refreshGeneration else { return }
            Self.log("unknown error \(error)")
            lastRefreshNote = error.localizedDescription
            var snap = SharedStore.load()
            if snap.status != .ok {
                SharedStore.save(UsageSnapshot(status: .error, updatedAt: Date(), subscription: nil, message: error.localizedDescription, rows: []))
            }
            applySnapshot(SharedStore.load(), rebuildMenuIfNeeded: true)
        }
    }

    /// Local second-accurate UI refresh — no network.
    private func tickUI() {
        let snap = displayedSnapshot ?? SharedStore.load()
        guard snap.status == .ok else { return }
        displayedSnapshot = snap
        paintStatusBar(snap)

        for (idx, row) in snap.rows.enumerated() where idx < menuRowViews.count {
            menuRowViews[idx].updateResetText(Formatters.countdown(until: row.resetsAt))
        }
        updatedAtMenuItem?.title = "Updated \(Formatters.relativeUpdated(snap.updatedAt))"
    }

    private func applySnapshot(_ snapshot: UsageSnapshot?, rebuildMenuIfNeeded: Bool) {
        let snap = snapshot ?? .needsLogin
        let previous = displayedSnapshot
        displayedSnapshot = snap
        paintStatusBar(snap)

        guard rebuildMenuIfNeeded else {
            syncLiveMenuRows(with: snap)
            return
        }

        if shouldRebuildMenu(from: previous, to: snap) {
            rebuildMenu(with: snap)
        } else {
            syncLiveMenuRows(with: snap)
        }
    }

    private func shouldRebuildMenu(from previous: UsageSnapshot?, to next: UsageSnapshot) -> Bool {
        guard let previous else { return true }
        if previous.status != next.status { return true }
        if previous.subscription != next.subscription { return true }
        if previous.rows.map(\.id) != next.rows.map(\.id) { return true }
        if previous.rows.map(\.title) != next.rows.map(\.title) { return true }
        if menuRowViews.count != next.rows.count { return true }
        let hadNote = noteMenuItem != nil
        let wantsNote = !(lastRefreshNote ?? "").isEmpty
        if hadNote != wantsNote { return true }
        return false
    }

    private func syncLiveMenuRows(with snap: UsageSnapshot) {
        guard snap.status == .ok else { return }
        for (idx, row) in snap.rows.enumerated() where idx < menuRowViews.count {
            menuRowViews[idx].updatePercent(row.percent)
            menuRowViews[idx].updateResetText(Formatters.countdown(until: row.resetsAt))
        }
        updatedAtMenuItem?.title = "Updated \(Formatters.relativeUpdated(snap.updatedAt))"
        if let note = lastRefreshNote, !note.isEmpty {
            noteMenuItem?.title = Self.compactMenuNote(note)
        }
    }

    /// Keep status notes short so they don't force a wide menu.
    private static func compactMenuNote(_ note: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 36 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 33)
        return String(trimmed[..<idx]) + "…"
    }

    private func paintStatusBar(_ snap: UsageSnapshot) {
        guard let item = statusItem else { return }
        let view = statusBarView ?? StatusBarUsageView(frame: .zero)
        statusBarView = view

        if snap.status == .ok {
            let fiveHour = snap.statusBarRows.first(where: { $0.label == "5H" })
                ?? snap.statusBarRows.first
            if let fiveHour {
                view.model = .init(percent: fiveHour.percent, resetsAt: fiveHour.resetsAt)
                let reset = Formatters.countdown(until: fiveHour.resetsAt)
                item.button?.toolTip = "5-hour: \(fiveHour.percent)% · resets in \(reset)"
            } else {
                view.model = .init(percent: 0)
                item.button?.toolTip = "Claude Usage"
            }
        } else {
            view.model = .init(percent: 0)
            item.button?.toolTip = snap.status == .needsLogin ? "Sign in to Claude" : (snap.message ?? "Error")
        }

        let signature = statusBarSignature(snap)
        guard signature != lastPaintedStatusSignature || item.button?.image == nil else { return }
        lastPaintedStatusSignature = signature

        let size = view.intrinsicContentSize
        view.frame = NSRect(origin: .zero, size: size)
        let image = view.rasterizedImage()
        image.isTemplate = false
        item.button?.imageScaling = .scaleNone
        item.button?.imagePosition = .imageOnly
        item.button?.image = image
        item.button?.title = ""
        item.length = size.width + 8
    }

    private func statusBarSignature(_ snap: UsageSnapshot) -> String {
        guard snap.status == .ok else { return "\(snap.status.rawValue)|\(snap.message ?? "")" }
        let fiveHour = snap.statusBarRows.first(where: { $0.label == "5H" }) ?? snap.statusBarRows.first
        let pct = fiveHour?.percent ?? -1
        let cool = Formatters.compactCountdown(until: fiveHour?.resetsAt)
        return "\(pct)|\(cool)"
    }

    private func prettyPlan(_ oauth: ClaudeOAuthBlock) -> String {
        let tier = oauth.rateLimitTier ?? oauth.subscriptionType ?? ""
        if tier.contains("20x") { return "Max 20x" }
        if tier.contains("5x") { return "Max 5x" }
        if tier.lowercased().contains("max") { return "Max" }
        if tier.lowercased().contains("pro") { return "Pro" }
        return tier.isEmpty ? "Claude" : tier
    }

    private static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = SharedStore.directoryURL.appendingPathComponent("app.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
        NSLog("TokenWidget \(message)")
    }
}

@main
enum TokenWidgetMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        // NSApplication.delegate is weak — must retain the delegate for the process lifetime.
        retainedDelegate = delegate
        app.delegate = delegate
        // Start immediately on this (main) thread before the run loop.
        delegate.bootstrap()
        app.run()
    }
}

private var retainedDelegate: AppDelegate?
