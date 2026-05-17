import SwiftUI
import AppKit

struct ModalView: View {
    @ObservedObject var state: RunState
    @ObservedObject var settings: SettingsModel
    let onRun: (String) -> Void
    let onCancel: () -> Void
    let onCopyError: () -> Void

    @FocusState private var instructionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
            content
        }
        .padding(14)
        .frame(width: 420)
        .frame(minHeight: 360, maxHeight: 480, alignment: .top)
        .background(VisualEffectBackground())
        .onAppear { instructionFocused = true }
        .onExitCommand(perform: onCancel)
    }

    @ViewBuilder
    private var preview: some View {
        if let image = NSImage(contentsOf: state.imageURL) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 392, maxHeight: 200)
                .cornerRadius(8)
                .shadow(radius: 2)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .awaitingInstruction:
            input
        case .running:
            transcriptView
        case .done(let result):
            donePill(result: result)
        case .failed(let error):
            errorView(error: error)
        }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What would you like to do?", text: $state.instruction, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(3...6)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .focused($instructionFocused)
                .onSubmit { commit() }
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut("w", modifiers: [.command])
                Spacer()
                Button("Run", action: commit)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                    .disabled(state.instruction.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressView().controlSize(.small)
                Text("Running…").font(.system(size: 12, weight: .medium))
                Spacer()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(state.transcript) { line in
                            TranscriptRow(line: line).id(line.id)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 220)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .onChange(of: state.transcript.count) { _ in
                    if let last = state.transcript.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func donePill(result: RunResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(result.summary).font(.system(size: 13, weight: .medium)).lineLimit(2)
                Spacer()
            }
            Text(result.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.08)))
    }

    private func errorView(error: RunError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(error.errorDescription ?? "Unknown error")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            HStack {
                Spacer()
                Button("Copy Error", action: onCopyError)
                Button("Close", action: onCancel).keyboardShortcut("w", modifiers: [.command])
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
    }

    private func commit() {
        let trimmed = state.instruction.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onRun(trimmed)
    }
}

private struct TranscriptRow: View {
    let line: TranscriptLine

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            icon
            Text(line.text)
                .font(.system(size: 11, design: line.kind == .toolUse ? .monospaced : .default))
                .foregroundStyle(line.kind == .error ? Color.red : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch line.kind {
        case .assistantText:
            Image(systemName: "text.bubble").font(.system(size: 10)).foregroundStyle(.secondary)
        case .toolUse:
            Image(systemName: "wrench.adjustable").font(.system(size: 10)).foregroundStyle(.secondary)
        case .error:
            Image(systemName: "xmark.octagon").font(.system(size: 10)).foregroundStyle(.red)
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.state = .active
        v.blendingMode = .behindWindow
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
