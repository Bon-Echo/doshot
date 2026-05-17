import Foundation
import Combine

/// MainActor-bound observable state for a single run. The modal subscribes to this.
@MainActor
final class RunState: ObservableObject {
    enum Phase: Equatable {
        case awaitingInstruction
        case running
        case done(RunResult)
        case failed(RunError)
    }

    @Published var phase: Phase = .awaitingInstruction
    @Published var instruction: String = ""
    @Published var transcript: [TranscriptLine] = []

    let runDir: URL
    let imageURL: URL

    init(runDir: URL, imageURL: URL) {
        self.runDir = runDir
        self.imageURL = imageURL
    }

    func append(_ line: TranscriptLine) {
        transcript.append(line)
    }
}

struct TranscriptLine: Identifiable, Equatable {
    enum Kind: Equatable {
        case assistantText
        case toolUse
        case error
    }
    let id = UUID()
    let kind: Kind
    let text: String
}

extension RunState.Phase {
    static func == (lhs: RunState.Phase, rhs: RunState.Phase) -> Bool {
        switch (lhs, rhs) {
        case (.awaitingInstruction, .awaitingInstruction): return true
        case (.running, .running): return true
        case (.done(let a), .done(let b)): return a.summary == b.summary
        case (.failed(let a), .failed(let b)): return a.errorDescription == b.errorDescription
        default: return false
        }
    }
}
