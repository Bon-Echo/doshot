import Foundation

/// Decoded surface of the events DoShot cares about from `claude --output-format stream-json`.
enum StreamJsonEvent {
    case assistantText(String)
    case toolUse(String)   // e.g. "Bash: mv …" / "Write: result.json"
    case errorText(String)
}

/// Line-buffered stream-json parser. Each line is an independent JSON object emitted by the
/// claude CLI. We only surface enough structure for the modal transcript view.
final class StreamJsonParser {
    private var buffer = ""

    func feed(_ chunk: String) -> [StreamJsonEvent] {
        buffer.append(chunk)
        var events: [StreamJsonEvent] = []
        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
            buffer = String(buffer[newlineRange.upperBound...])
            if let evs = decode(line: line) {
                events.append(contentsOf: evs)
            }
        }
        return events
    }

    private func decode(line: String) -> [StreamJsonEvent]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let type = json["type"] as? String ?? ""

        switch type {
        case "assistant":
            // { "type": "assistant", "message": { "content": [{type:"text",text:"…"} | {type:"tool_use",name,input}] } }
            guard let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return nil }
            var out: [StreamJsonEvent] = []
            for block in content {
                let blockType = block["type"] as? String ?? ""
                if blockType == "text", let text = block["text"] as? String, !text.isEmpty {
                    out.append(.assistantText(text))
                } else if blockType == "tool_use" {
                    let name = block["name"] as? String ?? "tool"
                    let summary = summarizeToolUse(name: name, input: block["input"] as? [String: Any] ?? [:])
                    out.append(.toolUse(summary))
                }
            }
            return out
        case "user":
            // tool_result echo — skip.
            return nil
        case "result":
            if let isError = json["is_error"] as? Bool, isError,
               let message = json["error"] as? String {
                return [.errorText(message)]
            }
            return nil
        case "system":
            return nil
        default:
            return nil
        }
    }

    private func summarizeToolUse(name: String, input: [String: Any]) -> String {
        switch name {
        case "Bash":
            let cmd = (input["command"] as? String) ?? ""
            return "Bash: " + truncated(cmd, to: 80)
        case "Write":
            let path = (input["file_path"] as? String) ?? ""
            return "Write: " + (path as NSString).lastPathComponent
        case "Read":
            let path = (input["file_path"] as? String) ?? ""
            return "Read: " + (path as NSString).lastPathComponent
        default:
            return name
        }
    }

    private func truncated(_ s: String, to limit: Int) -> String {
        if s.count <= limit { return s }
        return String(s.prefix(limit)) + "…"
    }
}
