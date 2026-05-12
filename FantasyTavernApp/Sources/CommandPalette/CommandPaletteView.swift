import SwiftUI
import EntityModel

struct CommandPaletteView: View {
    @Bindable var controller: PaletteController
    @FocusState private var queryFocused: Bool

    var body: some View {
        if controller.isVisible {
            ZStack(alignment: .top) {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { controller.dismiss() }

                VStack(spacing: 0) {
                    TextField("Search entities, or type \">\" for actions…", text: $controller.query)
                        .font(.title3)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.background)
                        .focused($queryFocused)
                        .onKeyPress(.escape) { controller.dismiss(); return .handled }
                        .onKeyPress(.upArrow) { controller.moveSelection(by: -1); return .handled }
                        .onKeyPress(.downArrow) { controller.moveSelection(by: 1); return .handled }
                        .onKeyPress(keys: [.return]) { press in
                            controller.activate(openInPlace: press.modifiers.contains(.command))
                            return .handled
                        }

                    Divider()
                    results
                        .background(.background)
                }
                .frame(width: 520)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 20)
                .padding(.top, 80)
            }
            .transition(.opacity)
            .onAppear { queryFocused = true }
            .task { queryFocused = true }
        }
    }

    @ViewBuilder
    private var results: some View {
        if controller.isActionMode {
            List(Array(controller.actionResults.enumerated()), id: \.element.id) { idx, action in
                HStack {
                    Text(action.title)
                    Spacer()
                    Text("⏎").foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .background(idx == controller.selectionIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { controller.selectionIndex = idx; controller.activate(openInPlace: false) }
            }
            .frame(maxHeight: 320)
        } else {
            List(Array(controller.findResults.enumerated()), id: \.element.id) { idx, hit in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.name)
                        Text(hit.type.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .background(idx == controller.selectionIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { controller.selectionIndex = idx; controller.activate(openInPlace: false) }
            }
            .frame(maxHeight: 320)
        }
    }
}
