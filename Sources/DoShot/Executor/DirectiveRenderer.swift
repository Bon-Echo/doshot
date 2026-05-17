import Foundation

/// Renders `Resources/directive.md` with `{{...}}` placeholder substitution.
/// The template body itself is owned by the AI vertical; this renderer only handles substitution.
enum DirectiveRenderer {
    enum RenderError: Error, LocalizedError {
        case templateMissing
        case readFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .templateMissing:
                return "directive.md template missing from bundle"
            case .readFailed(let err):
                return "failed to read directive.md: \(err.localizedDescription)"
            }
        }
    }

    @MainActor
    static func render(instruction: String, settings: SettingsModel, screenshotPath: String) throws -> String {
        guard let url = Bundle.module.url(forResource: "directive", withExtension: "md") else {
            throw RenderError.templateMissing
        }
        let template: String
        do {
            template = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw RenderError.readFailed(underlying: error)
        }
        let substitutions: [String: String] = [
            "instruction": instruction,
            "screenshot_path": screenshotPath,
            "desktop_root": settings.desktopRoot,
            "slack_token_present": settings.slackToken.isEmpty ? "false" : "true",
            "slack_default_channel_id": settings.slackDefaultChannelId,
            "slack_default_channel_name": settings.slackDefaultChannelName
        ]
        return apply(substitutions: substitutions, to: template)
    }

    static func apply(substitutions: [String: String], to template: String) -> String {
        var output = template
        for (key, value) in substitutions {
            output = output.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return output
    }
}
