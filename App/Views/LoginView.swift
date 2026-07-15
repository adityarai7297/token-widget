import SwiftUI
import AppKit

/// Frictionless login:
/// 1. Try importing tokens from Claude Code (if already logged in there)
/// 2. Otherwise open the browser and auto-detect the code when you copy it
struct LoginView: View {
    /// When true (after Sign Out / dead tokens), skip Claude Code import and
    /// go straight to the browser — those tokens may be the ones that failed.
    var skipClaudeCodeImport: Bool = false
    var onSuccess: () -> Void
    var onCancel: () -> Void

    @State private var pkce = CredentialStore.makePKCE()
    @State private var status = "Checking for an existing Claude login…"
    @State private var errorText: String?
    @State private var phase: Phase = .checking
    @State private var clipboardTimer: Timer?
    @State private var lastClipboard = ""
    @State private var isBusy = false

    private enum Phase {
        case checking
        case waitingForCode
        case exchanging
        case failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect Claude")
                        .font(.title2.weight(.semibold))
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel", action: {
                    stopClipboardWatch()
                    onCancel()
                })
            }

            switch phase {
            case .checking:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking for Claude Code credentials…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 24)

            case .waitingForCode:
                VStack(alignment: .leading, spacing: 12) {
                    Text("Chrome should show an authentication code.")
                        .font(.headline)
                    Text("Just copy that code (⌘C) — this window will pick it up automatically. You do not paste it into Claude Code.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for you to copy the code…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)

                    Button("Open login page again") {
                        openBrowser()
                    }
                    .buttonStyle(.bordered)
                }

            case .exchanging:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finishing sign-in…")
                }
                .padding(.vertical, 24)

            case .failed:
                VStack(alignment: .leading, spacing: 12) {
                    if let errorText {
                        Text(errorText)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    Button("Try Again") {
                        start()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 480, height: 280)
        .onAppear { start() }
        .onDisappear { stopClipboardWatch() }
    }

    private func start() {
        stopClipboardWatch()
        errorText = nil
        isBusy = false
        phase = .checking
        status = "Checking for an existing Claude login…"
        Task { await bootstrap() }
    }

    @MainActor
    private func bootstrap() async {
        // 1) Already have Claude Code? Import and validate before finishing.
        if !skipClaudeCodeImport {
            do {
                _ = try CredentialStore.importFromClaudeCode()
                status = "Imported your Claude Code login — verifying…"
                phase = .exchanging
                _ = try await CredentialStore.refreshOAuthIfNeeded(force: true)
                status = "Imported your Claude Code login"
                onSuccess()
                return
            } catch {
                // Stale Claude Code tokens — clear and use the browser instead.
                CredentialStore.clearOwnedOAuth()
            }
        }

        // 2) Browser + clipboard auto-detect
        phase = .waitingForCode
        status = "Complete Google sign-in in Chrome, then copy the code on the page."
        openBrowser()
        startClipboardWatch()
    }

    private func openBrowser() {
        let url = CredentialStore.authorizeURL(pkce: pkce)
        NSWorkspace.shared.open(url)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startClipboardWatch() {
        lastClipboard = NSPasteboard.general.string(forType: .string) ?? ""
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            Task { @MainActor in
                pollClipboard()
            }
        }
        if let clipboardTimer {
            RunLoop.main.add(clipboardTimer, forMode: .common)
        }
    }

    private func stopClipboardWatch() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    @MainActor
    private func pollClipboard() {
        guard !isBusy, phase == .waitingForCode else { return }
        let current = NSPasteboard.general.string(forType: .string) ?? ""
        guard current != lastClipboard else { return }
        lastClipboard = current
        guard CredentialStore.looksLikeAuthCode(current) else { return }
        Task { await exchange(code: current) }
    }

    @MainActor
    private func exchange(code: String) async {
        guard !isBusy else { return }
        isBusy = true
        stopClipboardWatch()
        phase = .exchanging
        status = "Got the code — finishing sign-in…"
        errorText = nil
        do {
            let oauth = try await CredentialStore.exchangeCode(code, state: nil, pkce: pkce)
            try CredentialStore.saveOwnedOAuth(oauth)
            status = "Signed in"
            onSuccess()
        } catch {
            errorText = error.localizedDescription
            status = "Couldn’t finish sign-in"
            phase = .failed
            isBusy = false
            // New PKCE session required after a failed exchange.
            pkce = CredentialStore.makePKCE()
        }
    }
}
