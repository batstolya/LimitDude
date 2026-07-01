import AppKit
import ApplicationServices
import Foundation
import LimitDudeCore

public final class SetupStatusProvider: @unchecked Sendable {
    private let codexAppPath: String
    private let codexCLIPath: String
    private let codexStatePath: String
    private let rateLimitProvider: CodexRateLimitProvider

    public init(
        codexAppPath: String = "/Applications/Codex.app",
        codexCLIPath: String = "/Applications/Codex.app/Contents/Resources/codex",
        codexStatePath: String = "\(NSHomeDirectory())/.codex/state_5.sqlite",
        rateLimitProvider: CodexRateLimitProvider = CodexRateLimitProvider()
    ) {
        self.codexAppPath = codexAppPath
        self.codexCLIPath = codexCLIPath
        self.codexStatePath = codexStatePath
        self.rateLimitProvider = rateLimitProvider
    }

    public func read() -> SetupReport {
        var checks: [SetupCheck] = []

        checks.append(codexAppCheck())
        checks.append(codexCLICheck())
        checks.append(codexLoginCheck())
        checks.append(codexStateCheck())
        checks.append(claudeAccessibilityCheck())

        return SetupReport(checks: checks)
    }

    private func codexAppCheck() -> SetupCheck {
        if FileManager.default.fileExists(atPath: codexAppPath) {
            return SetupCheck(title: "Codex.app", state: .ok, detail: "Found at \(codexAppPath)")
        }

        return SetupCheck(
            title: "Codex.app",
            state: .missing,
            detail: "Codex.app was not found at \(codexAppPath)",
            action: "Install Codex.app, open it, and sign in"
        )
    }

    private func codexCLICheck() -> SetupCheck {
        if FileManager.default.isExecutableFile(atPath: codexCLIPath) {
            return SetupCheck(title: "Codex local CLI", state: .ok, detail: "Found executable app-server binary")
        }

        return SetupCheck(
            title: "Codex local CLI",
            state: .missing,
            detail: "LimitDude cannot run \(codexCLIPath)",
            action: "Reinstall or update Codex.app"
        )
    }

    private func codexLoginCheck() -> SetupCheck {
        let reading = rateLimitProvider.read()
        switch reading.state {
        case .available, .warning, .limited:
            return SetupCheck(title: "Codex login", state: .ok, detail: "Rate limits are readable")
        case .checking:
            return SetupCheck(title: "Codex login", state: .warning, detail: "Codex is still checking")
        case .unknown:
            return SetupCheck(
                title: "Codex login",
                state: .missing,
                detail: reading.reason,
                action: "Open Codex.app and sign in, then run Setup Status again"
            )
        }
    }

    private func codexStateCheck() -> SetupCheck {
        if FileManager.default.fileExists(atPath: codexStatePath) {
            return SetupCheck(title: "Codex task history", state: .ok, detail: "Found \(codexStatePath)")
        }

        return SetupCheck(
            title: "Codex task history",
            state: .warning,
            detail: "No local Codex task database yet",
            action: "Start at least one Codex thread in Codex.app"
        )
    }

    private func claudeAccessibilityCheck() -> SetupCheck {
        let isClaudeInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
        let isTrusted = AXIsProcessTrusted()

        if isClaudeInstalled && isTrusted {
            return SetupCheck(title: "Claude Desktop", state: .ok, detail: "Installed and Accessibility permission is granted")
        }

        if isClaudeInstalled {
            return SetupCheck(
                title: "Claude Desktop",
                state: .warning,
                detail: "Installed, but Accessibility permission is not granted",
                action: "System Settings -> Privacy & Security -> Accessibility -> enable LimitDude"
            )
        }

        return SetupCheck(
            title: "Claude Desktop",
            state: .warning,
            detail: "Claude Desktop is not installed",
            action: "Install Claude Desktop only if you want Claude window checks"
        )
    }
}
