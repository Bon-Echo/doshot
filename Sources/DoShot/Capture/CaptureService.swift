import Foundation

final class CaptureService {
    private let executable = "/usr/sbin/screencapture"

    /// Spawn `screencapture -i -s -t png <imageURL>` and return true if a non-empty PNG was produced.
    @MainActor
    func captureRegion(to imageURL: URL) async throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-i", "-s", "-t", "png", imageURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let fm = FileManager.default
                if let attrs = try? fm.attributesOfItem(atPath: imageURL.path),
                   let size = attrs[.size] as? NSNumber, size.intValue > 0 {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
