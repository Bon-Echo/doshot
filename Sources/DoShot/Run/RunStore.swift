import Foundation

final class RunStore {
    private let root: URL = URL(fileURLWithPath: NSString("~/.doshot/runs").expandingTildeInPath)

    func createRunDirectory(now: Date = Date()) throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        let dir = root.appendingPathComponent(stamp, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func writeMeta(runDir: URL, instruction: String?) throws {
        let payload: [String: Any] = [
            "startedAt": ISO8601DateFormatter().string(from: Date()),
            "hotkey": "\u{2303}\u{21E7}4",
            "instruction": instruction as Any
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: runDir.appendingPathComponent("meta.json"))
    }

    func readResult(runDir: URL) -> RunResult? {
        let url = runDir.appendingPathComponent("result.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RunResult.self, from: data)
    }
}
