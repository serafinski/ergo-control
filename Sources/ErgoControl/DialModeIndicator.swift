import AppKit
import SwiftUI

/// A transient overlay that never takes keyboard focus or intercepts clicks.
final class DialModeIndicator {
    private var panel: NSPanel?
    private var hideTimer: Timer?

    func show(mode: String, profile: String) {
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
        panel.contentView = NSHostingView(rootView: DialModeBadge(mode: mode, profile: profile))
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 90))
        }
        panel.orderFrontRegardless()
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: false) { [weak self] _ in self?.dismiss() }
        hideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func dismiss() {
        hideTimer?.invalidate(); hideTimer = nil
        panel?.orderOut(nil)
    }
}

private struct DialModeBadge: View {
    let mode: String
    let profile: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 28, weight: .medium)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Command dial").font(.caption).foregroundStyle(.secondary)
                Text(mode).font(.title3.bold()).lineLimit(1)
                Text(profile).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
