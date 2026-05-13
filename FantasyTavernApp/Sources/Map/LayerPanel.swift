import SwiftUI
import WorldStore

struct LayerPanel: View {
    @Binding var doc: MapDoc
    @Binding var activeLayerID: String
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Layers").font(.headline)
            ForEach(doc.layers) { layer in
                layerRow(layer)
            }
            Divider()
            Button {
                let id = doc.addLayer()
                activeLayerID = id
                onChange()
            } label: {
                Label("Add Layer", systemImage: "plus")
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(10)
        .frame(width: 200)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func layerRow(_ layer: MapLayer) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { layer.visible },
                set: { newValue in
                    doc.setVisibility(id: layer.id, visible: newValue)
                    onChange()
                }
            )).labelsHidden()

            TextField("Name", text: Binding(
                get: { layer.name },
                set: { newName in
                    doc.renameLayer(id: layer.id, to: newName)
                    onChange()
                }
            ))
            .textFieldStyle(.plain)
            .background(layer.id == activeLayerID ? Color.accentColor.opacity(0.18) : .clear)
            .onTapGesture { activeLayerID = layer.id }

            Spacer()
            Button {
                if doc.removeLayer(id: layer.id) {
                    if activeLayerID == layer.id { activeLayerID = doc.layers.first?.id ?? "default" }
                    onChange()
                }
            } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .disabled(doc.layers.count <= 1)
        }
    }
}
