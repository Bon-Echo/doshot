import Foundation

/// Spawns the `claude` CLI with the rendered directive, streams stdout JSON events
/// back into the RunState, enforces a timeout, and posts completion / error notifications.
@MainActor
final class ClaudeExecutor {
    private let settings: SettingsModel
    private let notifications: NotificationService

    init(settings: SettingsModel, notifications: NotificationService) {
        self.settings = settings
        self.notifications = notifications
    }

    func run(state: RunState, phaseSink: @escaping (RunState.Phase) -> Void) async {
        guard let binary = settings.resolvedClaudePath else {
            let err = RunError.claudeMissing
            notifications.postError(error: err, runId: state.runDir.lastPathComponent)
            phaseSink(.failed(err))
            return
        }

        let directive: String
        do {
            directive = try DirectiveRenderer.render(
                instruction: state.instruction,
                settings: settings,
                screenshotPath: state.imageURL.path
            )
        } catch {
            let err = RunError.unknown(message: error.localizedDescription)
            notifications.postError(error: err, runId: state.runDir.lastPathComponent)
            phaseSink(.failed(err))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [
            "-p", directive,
            "--output-format", "stream-json",
            "--verbose",
            // Headless one-shot executor: no interactive approval, so we bypass all
            // permission prompts. Guardrails come from the directive prompt (cwd +
            // $DOSHOT_DESKTOP_ROOT only) and the per-run timeout — not from
            // interactive approval. `acceptEdits` alone only auto-approves file
            // writes, leaving Bash/curl blocked, which breaks both Save and Slack
            // actions in v1.
            "--dangerously-skip-permissions"
        ]
        process.currentDirectoryURL = state.runDir

        var env = ProcessInfo.processInfo.environment
        env["DOSHOT_SCREENSHOT_PATH"] = state.imageURL.path
        env["DOSHOT_DESKTOP_ROOT"] = settings.desktopRoot
        env["DOSHOT_SLACK_DEFAULT_CHANNEL"] = settings.slackDefaultChannelId
        env["DOSHOT_SLACK_DEFAULT_CHANNEL_NAME"] = settings.slackDefaultChannelName
        if !settings.slackToken.isEmpty {
            env["SLACK_BOT_TOKEN"] = settings.slackToken
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Run in its own process group so we can kill the whole tree on timeout.
        // Foundation's Process API doesn't expose setsid; fall back to PGID kill via the pid.
        do {
            try process.run()
        } catch {
            let err = RunError.unknown(message: "Failed to launch claude: \(error.localizedDescription)")
            notifications.postError(error: err, runId: state.runDir.lastPathComponent)
            phaseSink(.failed(err))
            return
        }

        let timeoutSeconds = settings.runTimeoutSeconds
        var timedOut = false
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
            if process.isRunning {
                timedOut = true
                kill(-process.processIdentifier, SIGKILL)
                process.terminate()
            }
        }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let parser = StreamJsonParser()
        let accumulator = TranscriptAccumulator()

        // Capture strongly into the task so Swift 6 sees no re-assignable captures.
        let weakState = state
        let weakSelf = self
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                while process.isRunning || stdoutHandle.availableData.count > 0 {
                    let chunk = stdoutHandle.availableData
                    if chunk.isEmpty { break }
                    accumulator.append(chunk)
                    guard let str = String(data: chunk, encoding: .utf8) else { continue }
                    let events = parser.feed(str)
                    for event in events {
                        await weakSelf.apply(event: event, to: weakState)
                    }
                }
            }
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    process.terminationHandler = { _ in continuation.resume() }
                }
            }
            await group.waitForAll()
        }

        timeoutTask.cancel()

        // Always persist the full stream-json transcript + stderr to the run dir,
        // regardless of exit path. This is the forensic surface for debugging
        // failed runs (no transcript = no way to see what Claude tried to do).
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let remaining = stdoutHandle.readDataToEndOfFile()
        if !remaining.isEmpty { accumulator.append(remaining) }
        try? accumulator.data.write(to: state.runDir.appendingPathComponent("transcript.jsonl"))
        if !stderrData.isEmpty {
            try? stderrData.write(to: state.runDir.appendingPathComponent("stderr.txt"))
        }
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        let tailText = String(data: remaining, encoding: .utf8) ?? ""

        if timedOut {
            let err = RunError.claudeTimeout
            notifications.postError(error: err, runId: state.runDir.lastPathComponent)
            phaseSink(.failed(err))
            return
        }

        let exitCode = process.terminationStatus

        let resultURL = state.runDir.appendingPathComponent("result.json")
        if exitCode == 0, let data = try? Data(contentsOf: resultURL),
           let result = try? JSONDecoder().decode(RunResult.self, from: data) {
            notifications.postSuccess(result: result)
            phaseSink(.done(result))
            return
        }

        let err: RunError
        if exitCode != 0 {
            err = .claudeNonZero(code: exitCode, transcript: stderrText.isEmpty ? tailText : stderrText)
        } else {
            err = .unknown(message: "result.json missing or unparseable")
        }
        notifications.postError(error: err, runId: state.runDir.lastPathComponent)
        phaseSink(.failed(err))
    }

    private func apply(event: StreamJsonEvent, to state: RunState) {
        switch event {
        case .assistantText(let text):
            state.append(TranscriptLine(kind: .assistantText, text: text))
        case .toolUse(let summary):
            state.append(TranscriptLine(kind: .toolUse, text: summary))
        case .errorText(let text):
            state.append(TranscriptLine(kind: .error, text: text))
        }
    }
}

/// Append-only stdout accumulator shared between the streaming task and the
/// post-stream forensic write. Single-writer-then-single-reader by construction
/// (TaskGroup's `waitForAll` establishes happens-before), so the unchecked
/// Sendable conformance is safe.
private final class TranscriptAccumulator: @unchecked Sendable {
    private(set) var data = Data()
    func append(_ chunk: Data) { data.append(chunk) }
}
