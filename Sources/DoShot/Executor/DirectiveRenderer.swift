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
        // Placeholders are UPPERCASE per the directive author's contract.
        // DEFAULT_CHANNEL is the human-readable "#name" form; the corresponding
        // channel id reaches the directive via env (`$DOSHOT_SLACK_DEFAULT_CHANNEL`).
        let defaultChannelDisplay: String = {
            let name = settings.slackDefaultChannelName.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { return "" }
            return name.hasPrefix("#") ? name : "#" + name
        }()
        let substitutions: [String: String] = [
            "INSTRUCTION": instruction,
            "SCREENSHOT_PATH": screenshotPath,
            "DESKTOP_ROOT": settings.desktopRoot,
            "SLACK_TOKEN_PRESENT": settings.slackToken.isEmpty ? "no" : "yes",
            "DEFAULT_CHANNEL": defaultChannelDisplay
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
