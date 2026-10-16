import SwiftUI
import AppKit

struct AppLogView: View {
    @ObservedObject var log: AppLog
    @State private var errorsOnly = false
    private var visible: [AppLog.Entry] {
        log.entries.reversed().filter { !errorsOnly || $0.level != .info }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("App logs").font(.largeTitle.bold())
            Text("Recent startup, mapping and lighting events. Logs stay on this Mac; typed text and chat contents are not recorded.")
                .foregroundStyle(.secondary)
            HStack {
                Toggle("Warnings and errors only", isOn: $errorsOnly)
                Spacer()
                Button("Copy logs") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.text, forType: .string)
                }.disabled(log.entries.isEmpty)
                Button("Show log file") { NSWorkspace.shared.activateFileViewerSelecting([log.file]) }
                Button("Clear logs") { log.clear() }.disabled(log.entries.isEmpty)
            }
            if let error = log.storageError { Text(error).foregroundStyle(.red) }
            if visible.isEmpty {
                Text(errorsOnly ? "No warnings or errors recorded." : "No app events recorded yet.")
                    .foregroundStyle(.secondary).padding(.vertical, 24)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(visible) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.level.rawValue.capitalized).bold()
                                    .foregroundStyle(entry.level == .error ? .red : entry.level == .warning ? .orange : .secondary)
                                Text(entry.category)
                                Spacer()
                                Text(entry.time, format: .dateTime.month().day().hour().minute().second())
                                    .foregroundStyle(.secondary)
                            }.font(.caption)
                            Text(entry.message).font(.callout).textSelection(.enabled)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Text("Keeps the latest \(AppLog.limit) events across app restarts. Clear logs removes this app-event history only.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
