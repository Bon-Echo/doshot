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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "claude"]
        // Use the user's login PATH; `env` itself doesn't expand $PATH from a custom shell.
        process.environment = ProcessInfo.processInfo.environment
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
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
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
