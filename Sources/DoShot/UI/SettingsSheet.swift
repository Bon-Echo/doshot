import SwiftUI
import KeyboardShortcuts
import AppKit

struct SettingsSheet: View {
    @ObservedObject var settings: SettingsModel
    @State private var slackTestState: String = ""
    @State private var slackChannels: [SlackAPI.Channel] = []

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            slack.tabItem { Label("Slack", systemImage: "paperplane") }
            advanced.tabItem { Label("Advanced", systemImage: "wrench") }
        }
        .padding(16)
        .frame(width: 480, height: 520)
    }

    private var general: some View {
        Form {
            Section("Hotkey") {
                KeyboardShortcuts.Recorder(for: .capture)
            }
            Section("Screenshot folder") {
                HStack {
                    Text(settings.desktopRoot).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…", action: chooseFolder)
                }
            }
            Section("Accessibility") {
                HStack {
                    Image(systemName: settings.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(settings.accessibilityGranted ? .green : .yellow)
                    Text(settings.accessibilityGranted ? "Granted" : "Not granted — hotkey will not fire")
                    Spacer()
                    Button("Open System Settings", action: openAccessibilityPane)
                }
            }
        }
    }

    private var slack: some View {
        Form {
            Section("Bot token") {
                SecureField("xoxb-…", text: $settings.slackToken)
                HStack {
                    Button("Test connection", action: testSlackToken).disabled(settings.slackToken.isEmpty)
                    Spacer()
                    Text(slackTestState).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if !settings.slackWorkspaceName.isEmpty {
                    Text("Workspace: \(settings.slackWorkspaceName)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Section("Default channel") {
                if slackChannels.isEmpty {
                    Text(settings.slackDefaultChannelName.isEmpty
                         ? "No channel selected. Test the token to load channels."
                         : "Current: #\(settings.slackDefaultChannelName)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Picker("Channel", selection: $settings.slackDefaultChannelId) {
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

    private var advanced: some View {
        Form {
            Section("Claude binary") {
                TextField("Auto-detect via `which claude`", text: $settings.claudeBinaryOverride)
                if let resolved = settings.resolvedClaudePath {
                    Text("Resolved: \(resolved)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                } else {
                    Text("Not found on PATH. Install Claude Code CLI or set an explicit path above.")
                        .font(.system(size: 11)).foregroundStyle(.red)
                }
            }
            Section("Per-run timeout") {
                Stepper("\(settings.runTimeoutSeconds)s", value: $settings.runTimeoutSeconds, in: 15...600, step: 15)
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
        }
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
                settings.slackWorkspaceName = auth.team ?? ""
                let channels = try await SlackAPI.conversationsList(token: settings.slackToken)
                await MainActor.run {
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
