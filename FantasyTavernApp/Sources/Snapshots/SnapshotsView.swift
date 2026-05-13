import SwiftUI
import SnapshotService

struct SnapshotsView: View {
    @Environment(WorldSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var entries: [SnapshotEntry] = []
    @State private var selected: URL?
    @State private var confirmRestore: SnapshotEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Snapshots").font(.headline)
            List(entries, id: \.url, selection: $selected) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.url.lastPathComponent)
                        Text(entry.date.formatted(date: .abbreviated, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(byteString(entry.size)).font(.caption).foregroundStyle(.secondary)
                }
                .tag(entry.url)
            }
            .frame(minHeight: 240)

            HStack {
                Button("Snapshot Now") {
                    session.snapshotNow()
                    reload()
                }
                Spacer()
                Button("Preview Selected") {
                    if let url = selected {
                        openWindow(value: url)
                    }
                }
                .disabled(selected == nil)
                Button("Restore Selected") {
                    if let url = selected, let entry = entries.first(where: { $0.url == url }) {
                        confirmRestore = entry
                    }
                }
                .disabled(selected == nil)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 520, height: 360)
        .onAppear { reload() }
        .alert("Restore this snapshot?",
               isPresented: Binding(get: { confirmRestore != nil },
                                     set: { if !$0 { confirmRestore = nil } })) {
            Button("Restore", role: .destructive) {
                if let entry = confirmRestore {
                    try? session.restore(snapshot: entry.url)
                    reload()
                }
                confirmRestore = nil
            }
            Button("Cancel", role: .cancel) { confirmRestore = nil }
        } message: {
            Text("Current state will be archived first as a pre-restore snapshot.")
        }
    }

    private func reload() {
        entries = session.listSnapshots()
    }

    private func byteString(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
