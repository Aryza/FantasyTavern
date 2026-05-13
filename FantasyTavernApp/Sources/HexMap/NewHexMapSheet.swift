import SwiftUI
import AppKit
import WorldStore

struct NewHexMapSheet: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = "overworld"
    @State private var cols: Int = 20
    @State private var rows: Int = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Hex Map").font(.headline)
            Form {
                TextField("Name", text: $name)
                HStack {
                    Stepper("Columns: \(cols)", value: $cols, in: 1...100)
                }
                HStack {
                    Stepper("Rows: \(rows)", value: $rows, in: 1...100)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(slug.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var slug: String { Slug.make(name) }

    private func create() {
        guard let store = session.store else { return }
        let doc = HexMapDoc.make(cols: cols, rows: rows)
        do {
            try store.saveHexMap(doc, name: slug)
            tabs.open(.hexMap(slug))
            dismiss()
        } catch {
            NSSound.beep()
        }
    }
}
