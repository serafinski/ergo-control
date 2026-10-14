import AppKit
import SwiftUI
import ErgoDevice

/// A transient overlay that never takes keyboard focus or intercepts clicks.
final class ControlIndicator {
    private var panel: NSPanel?
    private var hideTimer: Timer?
    private var checkingTimer: Timer?
    private var presentationID = UUID()

    func showDial(mode: String, profile: String) {
        show(title: "Command dial", value: mode, detail: profile,
             icon: "arrow.triangle.2.circlepath", duration: 1.5)
    }

    func requestBattery() -> UUID {
        dismiss()
        let ticket = UUID()
        presentationID = ticket
        let timer = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
            guard let self, self.presentationID == ticket else { return }
            self.show(title: "Keyboard battery", value: "Checking…", detail: "PT Ergo",
                      icon: "battery.100percent", duration: 12, ticket: ticket)
        }
        checkingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        return ticket
    }

    func updateBattery(_ state: BatteryReadState, for ticket: UUID) {
        guard ticket == presentationID else { return }
        switch state {
        case .ready(let percent):
            let level = percent >= 88 ? 100 : percent >= 63 ? 75 : percent >= 38 ? 50 : percent >= 13 ? 25 : 0
            show(title: "Keyboard battery", value: "\(percent)%", detail: "PT Ergo",
                 icon: "battery.\(level)percent", duration: 2)
        case .failed:
            show(title: "Keyboard battery", value: "Unavailable", detail: "Could not read the keyboard. Try again.",
                 icon: "battery.0percent", duration: 2)
        case .idle, .reading: break
        }
    }

    private func show(title: String, value: String, detail: String, icon: String, duration: TimeInterval, ticket: UUID? = nil) {
        checkingTimer?.invalidate(); checkingTimer = nil
        presentationID = ticket ?? UUID()
        let size = NSSize(width: 360, height: 104)
        let panel: NSPanel
        if let existing = self.panel { panel = existing }
        else {
            panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            self.panel = panel
        }
        panel.contentView = NSHostingView(rootView: ControlBadge(title: title, value: value, detail: detail, icon: icon))
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 90))
        }
        panel.orderFrontRegardless()
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in self?.dismiss() }
        hideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func dismiss() {
        presentationID = UUID()
        checkingTimer?.invalidate(); checkingTimer = nil
        hideTimer?.invalidate(); hideTimer = nil
        panel?.orderOut(nil)
    }
}

private struct ControlBadge: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.bold()).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(width: 360, height: 104)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
