import Foundation
import Combine
import AppKit

/// User-facing settings. Slack token lives in Keychain; everything else lives in UserDefaults.
@MainActor
final class SettingsModel: ObservableObject {
    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: "ai.doshot.slack")

    // Slack
    @Published var slackToken: String {
        didSet { keychain.set(slackToken.isEmpty ? nil : slackToken, for: "bot_token") }
    }
    @Published var slackWorkspaceName: String {
        didSet { defaults.set(slackWorkspaceName, forKey: K.slackWorkspaceName) }
    }
    @Published var slackDefaultChannelId: String {
        didSet { defaults.set(slackDefaultChannelId, forKey: K.slackChannelId) }
    }
    @Published var slackDefaultChannelName: String {
        didSet { defaults.set(slackDefaultChannelName, forKey: K.slackChannelName) }
    }

    // Folder
    @Published var desktopRoot: String {
        didSet { defaults.set(desktopRoot, forKey: K.desktopRoot) }
    }

    // Claude
    @Published var claudeBinaryOverride: String {
        didSet { defaults.set(claudeBinaryOverride, forKey: K.claudeBinary) }
    }
    @Published var runTimeoutSeconds: Int {
        didSet { defaults.set(runTimeoutSeconds, forKey: K.runTimeout) }
    }

    // Onboarding
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: K.onboardingDone) }
    }

    // Live (not persisted)
    @Published var accessibilityGranted: Bool = AXIsProcessTrusted()

    init() {
        slackToken = KeychainStore(service: "ai.doshot.slack").get("bot_token") ?? ""
        slackWorkspaceName = defaults.string(forKey: K.slackWorkspaceName) ?? ""
        slackDefaultChannelId = defaults.string(forKey: K.slackChannelId) ?? ""
        slackDefaultChannelName = defaults.string(forKey: K.slackChannelName) ?? ""
        desktopRoot = defaults.string(forKey: K.desktopRoot)
            ?? NSString("~/Desktop/DoShot").expandingTildeInPath
        claudeBinaryOverride = defaults.string(forKey: K.claudeBinary) ?? ""
        runTimeoutSeconds = defaults.object(forKey: K.runTimeout) as? Int ?? 90
        hasCompletedOnboarding = defaults.bool(forKey: K.onboardingDone)
    }

    /// Resolved Claude binary path. Prefers explicit override, falls back to `which claude`.
    var resolvedClaudePath: String? {
        if !claudeBinaryOverride.isEmpty, FileManager.default.isExecutableFile(atPath: claudeBinaryOverride) {
            return claudeBinaryOverride
        }
        return Self.whichClaude()
    }

    static func whichClaude() -> String? {
        // GUI-launched macOS apps inherit launchd's stripped PATH (no ~/.local/bin,
        // /opt/homebrew/bin, etc.). Run the user's login shell so .zshrc/.bashrc
        // PATH exports take effect, then fall back to probing known install paths.
        if let path = runLoginShell(command: "command -v claude"),
           FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            NSString(string: "~/.local/bin/claude").expandingTildeInPath,
            NSString(string: "~/bin/claude").expandingTildeInPath
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private static func runLoginShell(command: String) -> String? {
        let process = Process()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        process.executableURL = URL(fileURLWithPath: shell)
        // -l = login shell (sources .zprofile/.profile), -i = interactive (sources .zshrc),
        // -c = run one command. Yes, we eat the cost of sourcing rc files on every detect;
        // it runs at app launch + Re-check button only, so the overhead is fine.
        process.arguments = ["-lic", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let trimmed = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Some rc files emit chatter; take only the last non-empty line.
        let lastLine = trimmed.split(separator: "\n").map(String.init).last(where: { !$0.isEmpty }) ?? ""
        return lastLine.isEmpty ? nil : lastLine
    }

    private enum K {
        static let slackWorkspaceName = "slack.workspaceName"
        static let slackChannelId = "slack.defaultChannelId"
        static let slackChannelName = "slack.defaultChannelName"
        static let desktopRoot = "folder.desktopRoot"
        static let claudeBinary = "claude.binaryOverride"
        static let runTimeout = "claude.runTimeoutSeconds"
        static let onboardingDone = "onboarding.completed"
    }
}
