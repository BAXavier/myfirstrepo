import AppKit
import ApplicationServices
import CaptureKit

/// Global triggers: ⌥ ⌥ ⌥ and a mouse swirl. Uses passive NSEvent monitors (no event tap, no polling),
/// so the cost when idle is a few comparisons per modifier change / mouse move.
@MainActor
final class TriggerMonitor {
    static let shared = TriggerMonitor()

    private var taps = ModifierTapDetector()
    private var swirl = SwirlDetector()
    private var keyMonitors: [Any] = []
    private var mouseMonitor: Any?
    private var trustPoll: Timer?
    private let capture = CaptureController.shared

    private static let optionKeyCodes: Set<UInt16> = [58, 61] // left / right ⌥
    private static let escape: UInt16 = 53

    func start() {
        installKeyMonitors()
        applyPreferences()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TriggerMonitor.shared.applyPreferences() }
        }

        // Global key monitors only receive events once Accessibility is granted; re-install when it is.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                MainActor.assumeIsolated { TriggerMonitor.shared.installKeyMonitors() }
            }
        }
    }

    private func installKeyMonitors() {
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
                MainActor.assumeIsolated { TriggerMonitor.shared.handleKey(event) }
            },
            NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
                MainActor.assumeIsolated { TriggerMonitor.shared.handleKey(event) }
                return event
            },
        ].compactMap { $0 }
    }

    private func applyPreferences() {
        let wantsSwirl = UserDefaults.standard.bool(forKey: Pref.swirlEnabled)
        if wantsSwirl, mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
                MainActor.assumeIsolated { TriggerMonitor.shared.handleMouse(event) }
            }
        } else if !wantsSwirl, let m = mouseMonitor {
            NSEvent.removeMonitor(m)
            mouseMonitor = nil
            swirl.reset()
        }
    }

    private func handleKey(_ event: NSEvent) {
        if event.type == .keyDown {
            taps.interrupt()
            if event.keyCode == Self.escape, capture.isListening { capture.cancel() }
            return
        }
        guard UserDefaults.standard.bool(forKey: Pref.tripleOptionEnabled) else { return }
        guard Self.optionKeyCodes.contains(event.keyCode) else { taps.interrupt(); return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function])
        if flags.contains(.option) {
            // ⌥ went down; only a lone ⌥ counts.
            if flags == .option { taps.modifierDown(at: event.timestamp) } else { taps.interrupt() }
            return
        }
        switch taps.modifierUp(at: event.timestamp) {
        case .trigger: capture.toggle()
        case .tap where capture.isListening: Task { await capture.finish() } // one tap = done talking
        default: break
        }
    }

    private func handleMouse(_ event: NSEvent) {
        let p = NSEvent.mouseLocation
        if swirl.add(x: p.x, y: p.y, t: event.timestamp) { capture.toggle() }
    }
}
