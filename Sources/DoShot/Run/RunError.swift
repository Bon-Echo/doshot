import Foundation

enum RunError: LocalizedError {
    case claudeMissing
    case claudeTimeout
    case claudeNonZero(code: Int32, transcript: String)
    case slackMissingToken
    case slackApiError(code: String)
    case unknown(message: String)

    var errorDescription: String? {
        switch self {
        case .claudeMissing:
            return "The `claude` CLI is not installed or not on PATH."
        case .claudeTimeout:
            return "Claude run exceeded the configured timeout."
        case .claudeNonZero(let code, _):
            return "Claude exited with code \(code)."
        case .slackMissingToken:
            return "Slack bot token is not configured."
        case .slackApiError(let code):
            return "Slack API error: \(code)."
        case .unknown(let message):
            return message
        }
    }

    /// Plain-text payload suitable for the modal's Copy-Error button.
    var copyPayload: String {
        switch self {
        case .claudeMissing:
            return "claudeMissing: install Claude Code CLI and ensure `which claude` resolves."
        case .claudeTimeout:
            return "claudeTimeout: bump the per-run timeout in Settings or retry with a smaller task."
        case .claudeNonZero(let code, let transcript):
            return "claudeNonZero (code=\(code))\n--- transcript ---\n\(transcript)"
        case .slackMissingToken:
            return "slackMissingToken: paste an `xoxb-…` token in Settings → Slack."
        case .slackApiError(let code):
            return "slackApiError: \(code)"
        case .unknown(let message):
            return "unknown: \(message)"
        }
    }
}
