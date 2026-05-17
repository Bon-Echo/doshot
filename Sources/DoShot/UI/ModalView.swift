import SwiftUI
import AppKit

struct ModalView: View {
    @ObservedObject var state: RunState
    @ObservedObject var settings: SettingsModel
    let onRun: (String) -> Void
    let onCancel: () -> Void
    let onCopyError: () -> Void

    @FocusState private var instructionFocused: Bool
    @State private var pulse: CGFloat = 0

    var body: some View {
        ZStack {
            ArcadeBackground()
            content
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 16)
        }
        // Size matches ModalWindowController.modalSize so the SwiftUI content
        // and the NSWindow frame stay in lock-step.
        .frame(width: ModalWindowController.modalSize.width,
               height: ModalWindowController.modalSize.height,
               alignment: .top)
        .onAppear {
            instructionFocused = true
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = 1
            }
        }
        .onExitCommand(perform: onCancel)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .awaitingInstruction:
            inputView
        case .running:
            runningView
        case .done(let result):
            doneView(result: result)
        case .failed(let error):
            errorView(error: error)
        }
    }

    // MARK: - Input

    private var inputView: some View {
        VStack(alignment: .center, spacing: 14) {
            header(title: "DOSHOT", tagline: "TARGET ACQUIRED")
            preview
            directiveField
            actionRow
        }
    }

    private var preview: some View {
        Group {
            if let image = NSImage(contentsOf: state.imageURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 380, maxHeight: 220)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ArcadePalette.cyan, lineWidth: 1.5)
                    )
                    .shadow(color: ArcadePalette.cyan.opacity(0.55), radius: 12)
                    .overlay(scanlineMask)
            } else {
                placeholderFrame
            }
        }
    }

    private var placeholderFrame: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(ArcadePalette.cyan.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            .frame(height: 220)
    }

    private var directiveField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("> DIRECTIVE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ArcadePalette.cyan)
                Rectangle()
                    .fill(ArcadePalette.cyan.opacity(0.4))
                    .frame(height: 1)
            }
            TextField("issue orders to DoShot…", text: $state.instruction, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(2...5)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(instructionFocused ? ArcadePalette.cyan : ArcadePalette.cyan.opacity(0.35),
                                lineWidth: 1.2)
                )
                .shadow(color: instructionFocused ? ArcadePalette.cyan.opacity(0.6) : .clear, radius: 8)
                .focused($instructionFocused)
                .onSubmit { commit() }
        }
    }

    private var actionRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onCancel) {
                Text("ESC")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 5).strokeBorder(ArcadePalette.magenta.opacity(0.6), lineWidth: 1)
                    )
                    .foregroundColor(ArcadePalette.magenta)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("w", modifiers: [.command])

            Spacer()

            Button(action: commit) {
                Text("FIRE")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .tracking(4)
                    .frame(minWidth: 160)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [ArcadePalette.cyan, ArcadePalette.magenta],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: ArcadePalette.cyan.opacity(0.5 + 0.4 * pulse), radius: 14)
                    .shadow(color: ArcadePalette.magenta.opacity(0.3 + 0.3 * pulse), radius: 18)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(state.instruction.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(state.instruction.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
        }
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 14) {
            header(title: "EXECUTING", tagline: "DO NOT INTERRUPT")
            preview
            HStack(spacing: 8) {
                Text("[ ").foregroundColor(ArcadePalette.cyan)
                Text(state.transcript.last?.text ?? "INITIALIZING…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(" ]").foregroundColor(ArcadePalette.cyan)
                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Done

    private func doneView(result: RunResult) -> some View {
        VStack(spacing: 14) {
            header(title: "MISSION COMPLETE", tagline: "+1 SCORE", accent: ArcadePalette.lime)
            preview
            VStack(spacing: 6) {
                Text(result.summary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text(result.subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ArcadePalette.lime)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(ArcadePalette.lime.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ArcadePalette.lime, lineWidth: 1)
            )
        }
    }

    // MARK: - Error

    private func errorView(error: RunError) -> some View {
        VStack(spacing: 14) {
            header(title: "MISSION FAILED", tagline: "DAMAGE REPORT", accent: ArcadePalette.red)
            preview
            VStack(spacing: 8) {
                Text(error.errorDescription ?? "Unknown error")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Spacer()
                    Button(action: onCopyError) {
                        Text("COPY ERROR")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(ArcadePalette.red, lineWidth: 1))
                            .foregroundColor(ArcadePalette.red)
                    }
                    .buttonStyle(.plain)

                    Button(action: onCancel) {
                        Text("DISMISS")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.4), lineWidth: 1))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("w", modifiers: [.command])
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(ArcadePalette.red.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ArcadePalette.red, lineWidth: 1))
        }
    }

    // MARK: - Shared chrome

    private func header(title: String, tagline: String, accent: Color = ArcadePalette.cyan) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Rectangle().fill(accent).frame(width: 14, height: 14)
                .shadow(color: accent.opacity(0.8), radius: 6)
            Text(title)
                .font(.system(size: 17, weight: .black, design: .monospaced))
                .tracking(3)
                .foregroundColor(.white)
                .shadow(color: accent.opacity(0.7), radius: 4)
            Spacer()
            Text(tagline)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(accent)
        }
    }

    private var scanlineMask: some View {
        GeometryReader { geo in
            VStack(spacing: 2) {
                ForEach(0..<Int(geo.size.height / 3), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.025))
                        .frame(height: 1)
                    Color.clear.frame(height: 2)
                }
            }
        }
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func commit() {
        let trimmed = state.instruction.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onRun(trimmed)
    }
}

// MARK: - Arcade palette + background

enum ArcadePalette {
    static let cyan = Color(red: 0.0, green: 0.90, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.15, blue: 0.85)
    static let lime = Color(red: 0.20, green: 1.0, blue: 0.55)
    static let red = Color(red: 1.0, green: 0.25, blue: 0.42)
    static let deep = Color(red: 0.03, green: 0.02, blue: 0.10)
    static let midnight = Color(red: 0.06, green: 0.05, blue: 0.18)
}

private struct ArcadeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ArcadePalette.midnight, ArcadePalette.deep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Soft magenta glow bottom-right
            RadialGradient(
                colors: [ArcadePalette.magenta.opacity(0.35), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 320
            )
            // Soft cyan glow top-left
            RadialGradient(
                colors: [ArcadePalette.cyan.opacity(0.28), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 280
            )
            // Hairline grid
            GeometryReader { geo in
                Path { path in
                    let step: CGFloat = 24
                    var x: CGFloat = 0
                    while x <= geo.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y <= geo.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        y += step
                    }
                }
                .stroke(ArcadePalette.cyan.opacity(0.06), lineWidth: 0.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ArcadePalette.cyan.opacity(0.4), lineWidth: 1)
                .shadow(color: ArcadePalette.cyan.opacity(0.5), radius: 10)
        )
    }
}
