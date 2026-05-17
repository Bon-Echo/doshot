import SwiftUI
import AppKit

struct OnboardingSheet: View {
    @ObservedObject var settings: SettingsModel
    let onDone: () -> Void

    @State private var slackTestState: String = ""
    @State private var slackChannels: [SlackAPI.Channel] = []
    @State private var folderPicked: Bool = false
    @State private var claudeDetected: Bool

    init(settings: SettingsModel, onDone: @escaping () -> Void) {
        self.settings = settings
        self.onDone = onDone
        _claudeDetected = State(initialValue: settings.resolvedClaudePath != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to DoShot")
                    .font(.title2.bold())
                Text("Set up the three integrations DoShot needs. You can skip any of these and configure them later in Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                slackCard
                folderCard
                accessibilityCard

                if !claudeDetected {
                    claudeCard
                }

                HStack {
                    Spacer()
                    Button("Done", action: onDone).buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    private var slackCard: some View {
        Card(title: "Slack", systemImage: "paperplane") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste an `xoxb-…` bot token. Required scopes: `files:write`, `chat:write`, `channels:read`.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                SecureField("xoxb-…", text: $settings.slackToken)
                HStack {
                    Button("Test connection", action: testSlackToken).disabled(settings.slackToken.isEmpty)
                    Spacer()
                    Text(slackTestState).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if !slackChannels.isEmpty {
                    Picker("Default channel", selection: $settings.slackDefaultChannelId) {
                        ForEach(slackChannels) { channel in
                            Text("#\(channel.name)").tag(channel.id)
                        }
                    }
                    .onChange(of: settings.slackDefaultChannelId) { newId in
                        if let match = slackChannels.first(where: { $0.id == newId }) {
                            settings.slackDefaultChannelName = match.name
                        }
                    }
                }
            }
        }
    }

    private var folderCard: some View {
        Card(title: "Screenshot folder", systemImage: "folder") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Where saved screenshots land. DoShot will create subfolders per intent inside this root.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(settings.desktopRoot)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…", action: chooseFolder)
                    Button(folderPicked ? "Re-create default" : "Use default", action: createDefault)
                }
            }
        }
    }

    private var accessibilityCard: some View {
        Card(title: "Accessibility permission", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 8) {
                Text("DoShot needs Accessibility permission so the global hotkey fires from any app. **Without this, the hotkey is dead.**")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Image(systemName: settings.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(settings.accessibilityGranted ? .green : .yellow)
                    Text(settings.accessibilityGranted ? "Granted" : "Not granted")
                    Spacer()
                    Button("Request permission", action: requestAccessibility)
                    Button("Open System Settings", action: openAccessibilityPane)
                }
            }
        }
    }

    private var claudeCard: some View {
        Card(title: "Claude CLI", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 8) {
                Text("DoShot drives Claude Code via the `claude` CLI. It does not appear to be on your PATH.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Link("Install instructions",
                         destination: URL(string: "https://docs.anthropic.com/claude/docs/claude-code")!)
                    Spacer()
                    Button("Re-check") {
                        claudeDetected = settings.resolvedClaudePath != nil
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.desktopRoot)
        if panel.runModal() == .OK, let url = panel.url {
            settings.desktopRoot = url.path
            folderPicked = true
        }
    }

    private func createDefault() {
        let path = NSString("~/Desktop/DoShot").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        settings.desktopRoot = path
        folderPicked = false
    }

    private func requestAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func openAccessibilityPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func testSlackToken() {
        slackTestState = "Testing…"
        Task {
            do {
                let auth = try await SlackAPI.authTest(token: settings.slackToken)
                let channels = try await SlackAPI.conversationsList(token: settings.slackToken)
                await MainActor.run {
                    settings.slackWorkspaceName = auth.team ?? ""
                    slackChannels = channels
                    slackTestState = "\u{2713} \(auth.team ?? "ok") — \(channels.count) channels"
                    if settings.slackDefaultChannelId.isEmpty, let first = channels.first {
                        settings.slackDefaultChannelId = first.id
                        settings.slackDefaultChannelName = first.name
                    }
                }
            } catch {
                await MainActor.run {
                    slackTestState = "\u{2717} \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage).font(.system(size: 14))
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.gray.opacity(0.18)))
    }
}
