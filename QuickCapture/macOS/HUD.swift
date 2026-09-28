import AppKit
import Combine
import SwiftUI

/// Small floating pill at the top of the active screen. Non-activating: it never steals focus
/// from what you're typing in.
@MainActor
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var subscription: AnyCancellable?

    func bind(to capture: CaptureController) {
        subscription = capture.$phase.sink { phase in
            MainActor.assumeIsolated { HUD.shared.update(phase) }
        }
    }

    private func update(_ phase: CaptureController.Phase) {
        if phase == .idle {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            position(panel)
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 84),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: HUDView(capture: .shared, recorder: CaptureController.shared.recorder))
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 12))
    }
}

private struct HUDView: View {
    @ObservedObject var capture: CaptureController
    @ObservedObject var recorder: SpeechRecorder

    var body: some View {
        HStack(spacing: 14) {
            CaptureOrb(listening: capture.isListening, level: recorder.level, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 440, height: 84)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { capture.toggle() }
    }

    private var title: String {
        switch capture.phase {
        case .listening: "Listening…"
        case .thinking: "Making tasks…"
        case .done: "Done"
        case .failed: "Couldn't capture"
        case .idle: ""
        }
    }

    private var detail: String {
        switch capture.phase {
        case .listening: recorder.transcript.isEmpty ? "Tap ⌥ when done · Esc to cancel" : recorder.transcript
        case .thinking: recorder.transcript
        case .done(let s), .failed(let s): s
        case .idle: ""
        }
    }
}
