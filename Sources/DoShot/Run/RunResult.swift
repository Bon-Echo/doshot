import Foundation

struct RunResult: Codable {
    let summary: String
    let actions: [Action]

    struct Action: Codable {
        let kind: String
        let target: String?
        let ok: Bool
    }

    /// First save-action target path (if any) for Finder reveal on notification click.
    var saveTarget: String? {
        actions.first(where: { $0.kind == "save" && $0.ok })?.target
    }

    /// Compact one-line subtitle for the success toast: "Saved to X · Posted to Y".
    var subtitle: String {
        actions.map { action -> String in
            let where_ = action.target.map { " " + $0 } ?? ""
            let verb: String = {
                switch action.kind {
                case "save": return "Saved to"
                case "slack": return "Posted to"
                default: return action.kind.capitalized
                }
            }()
            return verb + where_
        }.joined(separator: " · ")
    }
}
