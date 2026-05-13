# FantasyTavern Plan 7 — Map Layers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `MapDoc`'s flat `pins` with named, toggleable `layers`, each owning its own pins. Existing v1 maps migrate transparently. UI gains a layer panel for visibility toggles, add/rename/delete, and selecting the "active" layer for new pins.

**Architecture:**
- **Model migration**: `MapDoc.layers: [Layer]` becomes the source of truth. Legacy `pins: [MapPin]` is read on decode (mapped into a single `Default` layer) and never written on encode.
- **MapStore unchanged**: persistence is JSON via the new `MapDoc` Codable; round-trip is automatic.
- **MapView**: renders pins by flattening `layers.filter(\.visible)`. ⌘-click stores a pin in the *active* layer (UI-selected). Drag/delete still operate per-pin since pins now carry their owning layer's identity through the view's iteration index.
- **LayerPanel**: a right-edge column inside `MapView` (collapsible) listing layers with visibility toggles, an "Add Layer" button, and active-layer selection.

**Tech Stack:** Same as prior plans — Swift 5.10+, macOS 14+, SwiftUI, AppKit, XCTest. No new SPM packages.

**Plan 7 success criteria:**
1. Existing world's `maps/overworld.json` (flat-pins schema) opens, renders pins as before, and on first save migrates to layers schema on disk (a single "Default" layer).
2. New world JSON written by the app is `{ "image": ..., "layers": [ { "id": ..., "name": ..., "visible": ..., "pins": [...] } ] }`.
3. MapView pin behavior unchanged for ⌘-click add, drag, delete, tap-to-open-location.
4. A floating panel on the map shows each layer w/ checkbox-style visibility toggle. Unchecking a layer hides its pins live.
5. "Add Layer" creates a new empty layer w/ a default name (`Layer 2`, `Layer 3`, …), selects it as active. ⌘-click then adds new pins to it.
6. Rename via inline TextField. Delete via context menu — deleting the last layer is disabled.
7. All existing tests stay green (after fixture updates) + new tests cover migration decode, layer mutation helpers, and active-layer fallback when target layer disappears.

**Out of scope (later):**
- Reordering layers via drag.
- Per-layer color tint on pins.
- Per-layer locking (read-only) flag.
- Importing/exporting individual layers.

---

## File Structure

```
Packages/WorldStore/Sources/WorldStore/
  Map.swift                                 # MODIFY: MapDoc -> layers[]; legacy pins decoded; Layer struct
Packages/WorldStore/Tests/WorldStoreTests/
  MapTests.swift                            # MODIFY: round-trip + legacy-migration tests
  MapStoreTests.swift                       # MODIFY: pin assertions adapt to layers
  WorldStoreTests.swift                     # MODIFY: saveMap roundtrip adapt

FantasyTavernApp/Sources/Map/
  MapView.swift                             # MODIFY: flatten visible layers, route ⌘-click into active layer
  AddPinPopover.swift                       # unchanged
  LayerPanel.swift                          # NEW: SwiftUI list w/ toggles + add/rename/delete
FantasyTavernApp/Tests/
  MapLayerMutationTests.swift               # NEW: pure helpers (addLayer/removeLayer/renameLayer/addPin)
  MapPinLabelTests.swift                    # MODIFY: pin label tests against new layer structure
```

**Why this split:**
- All Codable migration lives in one file (`Map.swift`).
- Pure layer-mutation helpers stay on `MapDoc` extension; tested without UI.
- `LayerPanel` is its own SwiftUI file so `MapView` doesn't grow further.

---

## Conventions (carry-over + additions)

- **Default layer id:** `"default"`. Default name `"Default"`. Visible.
- **New layer ids:** monotonic UUID string (`UUID().uuidString`).
- **Layer naming when adding:** `"Layer \(n)"` where `n = current count + 1`.
- **Encode shape:** `{ image, layers }`. `pins` field is never emitted on save.
- **Decode rules:**
  - If `layers` present: use it; ignore any `pins` field.
  - Else if `pins` present: wrap into one default layer.
  - Else: single empty default layer.
- **Active layer fallback:** if the user-selected layer is removed, the active selection collapses to the topmost visible layer; if none visible, the first layer.

---

## Task 1: Map model — `Layer` + new `MapDoc`

**Files:**
- Modify: `Packages/WorldStore/Sources/WorldStore/Map.swift`
- Modify: `Packages/WorldStore/Tests/WorldStoreTests/MapTests.swift`

- [ ] **Step 1: Failing tests**

  Overwrite `Packages/WorldStore/Tests/WorldStoreTests/MapTests.swift` (keep prior `MapPin` clamp test, replace MapDoc tests):

  ```swift
  import XCTest
  import EntityModel
  @testable import WorldStore

  final class MapTests: XCTestCase {
      func test_mapPin_clampedAccessors() {
          let pin = MapPin(x: 1.5, y: -0.2, locationId: EntityID("a"), label: nil)
          XCTAssertEqual(pin.clampedX, 1.0)
          XCTAssertEqual(pin.clampedY, 0.0)
      }

      func test_mapDoc_codableRoundTrip_layers() throws {
          let pin = MapPin(x: 0.4, y: 0.6, locationId: EntityID("silvermoon"), label: "Silvermoon")
          let layer = MapLayer(id: "default", name: "Default", visible: true, pins: [pin])
          let original = MapDoc(image: "overworld.png", layers: [layer])
          let data = try JSONEncoder().encode(original)
          let decoded = try JSONDecoder().decode(MapDoc.self, from: data)
          XCTAssertEqual(decoded, original)
      }

      func test_mapDoc_legacyPinsDecode_intoDefaultLayer() throws {
          let json = #"{"image":"overworld.png","pins":[{"x":0.5,"y":0.5,"locationId":"silvermoon","label":"Silvermoon"}]}"#
          let decoded = try JSONDecoder().decode(MapDoc.self, from: json.data(using: .utf8)!)
          XCTAssertEqual(decoded.layers.count, 1)
          XCTAssertEqual(decoded.layers[0].id, "default")
          XCTAssertEqual(decoded.layers[0].pins.count, 1)
          XCTAssertEqual(decoded.layers[0].pins[0].locationId.rawValue, "silvermoon")
      }

      func test_mapDoc_emptyDecode_singleEmptyDefaultLayer() throws {
          let json = #"{"image":"overworld.png"}"#
          let decoded = try JSONDecoder().decode(MapDoc.self, from: json.data(using: .utf8)!)
          XCTAssertEqual(decoded.layers.count, 1)
          XCTAssertTrue(decoded.layers[0].pins.isEmpty)
      }

      func test_mapDoc_encode_omitsLegacyPinsKey() throws {
          let doc = MapDoc(image: "x.png", layers: [MapLayer(id: "default", name: "Default", visible: true, pins: [])])
          let data = try JSONEncoder().encode(doc)
          let str = String(data: data, encoding: .utf8) ?? ""
          XCTAssertFalse(str.contains("\"pins\":["))
          XCTAssertTrue(str.contains("\"layers\""))
      }

      func test_mapDoc_allPins_flattens() {
          let l1 = MapLayer(id: "a", name: "A", visible: true,
                            pins: [MapPin(x: 0, y: 0, locationId: EntityID("p1"))])
          let l2 = MapLayer(id: "b", name: "B", visible: false,
                            pins: [MapPin(x: 0, y: 0, locationId: EntityID("p2"))])
          let doc = MapDoc(image: "x.png", layers: [l1, l2])
          XCTAssertEqual(doc.allPins.map(\.locationId.rawValue), ["p1", "p2"])
          XCTAssertEqual(doc.visiblePins.map(\.locationId.rawValue), ["p1"])
      }
  }
  ```

- [ ] **Step 2: Run** — expect compile failure (`MapLayer` unknown / `MapDoc(image:layers:)` mismatch).

- [ ] **Step 3: Implement**

  Overwrite `Packages/WorldStore/Sources/WorldStore/Map.swift`:

  ```swift
  import Foundation
  import EntityModel

  public struct MapPin: Equatable, Codable, Sendable {
      public var x: Double
      public var y: Double
      public var locationId: EntityID
      public var label: String?

      public init(x: Double, y: Double, locationId: EntityID, label: String? = nil) {
          self.x = x
          self.y = y
          self.locationId = locationId
          self.label = label
      }

      public var clampedX: Double { min(1.0, max(0.0, x)) }
      public var clampedY: Double { min(1.0, max(0.0, y)) }
  }

  public struct MapLayer: Equatable, Codable, Sendable, Identifiable {
      public var id: String
      public var name: String
      public var visible: Bool
      public var pins: [MapPin]

      public init(id: String, name: String, visible: Bool = true, pins: [MapPin] = []) {
          self.id = id
          self.name = name
          self.visible = visible
          self.pins = pins
      }
  }

  public struct MapDoc: Equatable, Sendable {
      public var image: String
      public var layers: [MapLayer]

      public init(image: String, layers: [MapLayer] = [MapLayer(id: "default", name: "Default")]) {
          self.image = image
          self.layers = layers.isEmpty
              ? [MapLayer(id: "default", name: "Default")]
              : layers
      }

      public var allPins: [MapPin] { layers.flatMap(\.pins) }
      public var visiblePins: [MapPin] { layers.filter(\.visible).flatMap(\.pins) }
  }

  extension MapDoc: Codable {
      private enum CodingKeys: String, CodingKey {
          case image, layers, pins
      }

      public init(from decoder: Decoder) throws {
          let c = try decoder.container(keyedBy: CodingKeys.self)
          let image = try c.decode(String.self, forKey: .image)
          if let layers = try c.decodeIfPresent([MapLayer].self, forKey: .layers), !layers.isEmpty {
              self.init(image: image, layers: layers)
              return
          }
          if let legacyPins = try c.decodeIfPresent([MapPin].self, forKey: .pins) {
              self.init(image: image, layers: [MapLayer(id: "default", name: "Default", visible: true, pins: legacyPins)])
              return
          }
          self.init(image: image)
      }

      public func encode(to encoder: Encoder) throws {
          var c = encoder.container(keyedBy: CodingKeys.self)
          try c.encode(image, forKey: .image)
          try c.encode(layers, forKey: .layers)
      }
  }
  ```

- [ ] **Step 4: Run** — `swift test --package-path Packages/WorldStore --filter MapTests`. Expect new tests pass.

- [ ] **Step 5: Update existing tests that constructed `MapDoc(pins:)`**

  `Packages/WorldStore/Tests/WorldStoreTests/MapStoreTests.swift` likely uses `var doc = MapDoc(image: "overworld.png")` and `doc.pins.append(...)`. Replace with:

  ```swift
          var doc = try MapStore.load(name: "overworld", in: tmp)
          doc.layers[0].pins.append(MapPin(x: 0.2, y: 0.3, locationId: EntityID("ruins"), label: nil))
          try MapStore.save(doc, name: "overworld", in: tmp)
          let reread = try MapStore.load(name: "overworld", in: tmp)
          XCTAssertEqual(reread, doc)
  ```

  Where any test asserted `pins.count`, replace with `allPins.count`. Where assertions read `doc.pins.first?...` change to `doc.allPins.first?...`. Find and fix all such call sites.

  Also `Packages/WorldStore/Tests/WorldStoreTests/WorldStoreTests.swift` `test_saveMap_roundTrip`: change `doc.pins.append(...)` → `doc.layers[0].pins.append(...)`.

  Re-run `swift test --package-path Packages/WorldStore` — all WorldStore tests green.

- [ ] **Step 6: Commit**

  ```bash
  git add Packages/WorldStore
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(WorldStore): MapDoc gains layers[]; legacy pins[] migrated on decode"
  ```

---

## Task 2: MapDoc mutation helpers + tests

**Files:**
- Modify: `Packages/WorldStore/Sources/WorldStore/Map.swift` (append helpers)
- Create: `FantasyTavernApp/Tests/MapLayerMutationTests.swift`

These helpers keep callsites concise and testable. They live on `MapDoc` itself in the package.

- [ ] **Step 1: Failing tests**

  `FantasyTavernApp/Tests/MapLayerMutationTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  import WorldStore
  @testable import FantasyTavernApp

  final class MapLayerMutationTests: XCTestCase {
      private func makeDoc() -> MapDoc {
          MapDoc(image: "x.png", layers: [MapLayer(id: "default", name: "Default")])
      }

      func test_addLayer_appendsAndUniqueName() {
          var doc = makeDoc()
          let id1 = doc.addLayer()
          XCTAssertEqual(doc.layers.count, 2)
          XCTAssertEqual(doc.layers.last?.name, "Layer 2")
          XCTAssertEqual(doc.layers.last?.id, id1)
          let id2 = doc.addLayer()
          XCTAssertEqual(doc.layers.last?.name, "Layer 3")
          XCTAssertNotEqual(id1, id2)
      }

      func test_removeLayer_blockedWhenLast() {
          var doc = makeDoc()
          let removed = doc.removeLayer(id: "default")
          XCTAssertFalse(removed)
          XCTAssertEqual(doc.layers.count, 1)
      }

      func test_removeLayer_succeedsForExtra() {
          var doc = makeDoc()
          let added = doc.addLayer()
          XCTAssertTrue(doc.removeLayer(id: added))
          XCTAssertEqual(doc.layers.count, 1)
      }

      func test_renameLayer_updatesName() {
          var doc = makeDoc()
          doc.renameLayer(id: "default", to: "Political")
          XCTAssertEqual(doc.layers.first?.name, "Political")
      }

      func test_addPin_intoSpecificLayer() {
          var doc = makeDoc()
          let added = doc.addLayer()
          let pin = MapPin(x: 0.5, y: 0.5, locationId: EntityID("loc"))
          doc.addPin(pin, toLayer: added)
          XCTAssertEqual(doc.layer(id: added)?.pins.count, 1)
      }

      func test_setVisibility_togglesLayer() {
          var doc = makeDoc()
          doc.setVisibility(id: "default", visible: false)
          XCTAssertFalse(doc.layer(id: "default")?.visible ?? true)
      }
  }
  ```

- [ ] **Step 2: Run** — expect compile failures on `addLayer()`, `removeLayer(id:)`, `renameLayer(id:to:)`, `addPin(_:toLayer:)`, `setVisibility(id:visible:)`, `layer(id:)`.

- [ ] **Step 3: Implement**

  Append to `Packages/WorldStore/Sources/WorldStore/Map.swift`:

  ```swift
  public extension MapDoc {
      func layer(id: String) -> MapLayer? {
          layers.first { $0.id == id }
      }

      @discardableResult
      mutating func addLayer() -> String {
          let id = UUID().uuidString
          let n = layers.count + 1
          layers.append(MapLayer(id: id, name: "Layer \(n)"))
          return id
      }

      @discardableResult
      mutating func removeLayer(id: String) -> Bool {
          guard layers.count > 1, let idx = layers.firstIndex(where: { $0.id == id }) else { return false }
          layers.remove(at: idx)
          return true
      }

      mutating func renameLayer(id: String, to newName: String) {
          guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
          layers[idx].name = newName
      }

      mutating func setVisibility(id: String, visible: Bool) {
          guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
          layers[idx].visible = visible
      }

      mutating func addPin(_ pin: MapPin, toLayer id: String) {
          guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
          layers[idx].pins.append(pin)
      }
  }
  ```

- [ ] **Step 4: Run app target tests** — `xcodegen generate && xcodebuild test`. Expect 6 new tests pass on top of prior totals.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WorldStore FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(map): MapDoc mutation helpers (add/remove/rename/visibility/pin)"
  ```

---

## Task 3: MapView — flatten visible layers, route ⌘-click to active layer

**Files:**
- Modify: `FantasyTavernApp/Sources/Map/MapView.swift`
- Modify: `FantasyTavernApp/Tests/MapPinLabelTests.swift` (if it asserted against old `.pins` shape)

- [ ] **Step 1: Update tests if needed**

  `MapPinLabelTests` from Plan 6 Task 3 used `MapPin` directly and `MapView.displayLabel(for:entities:)` — pin label logic itself is unchanged; no edits required if pins still flow through. Confirm by reading the file; if it builds, leave it.

- [ ] **Step 2: Rewrite `MapView` body to iterate visible layers**

  In `MapView.swift`, replace the existing pin `ForEach` block:

  Before:
  ```swift
                          ForEach(Array(doc.pins.enumerated()), id: \.offset) { idx, pin in
                              pinView(idx: idx, pin: pin, fit: fit)
                          }
  ```
  After:
  ```swift
                          ForEach(visiblePinDescriptors(doc: doc), id: \.id) { desc in
                              pinView(layerID: desc.layerID, idx: desc.pinIndex, pin: desc.pin, fit: fit)
                          }
  ```

  Add the descriptor helper inside `MapView`:

  ```swift
      private struct PinDescriptor: Identifiable {
          let id: String
          let layerID: String
          let pinIndex: Int
          let pin: MapPin
      }

      private func visiblePinDescriptors(doc: MapDoc) -> [PinDescriptor] {
          doc.layers.enumerated().flatMap { layerIdx, layer -> [PinDescriptor] in
              guard layer.visible else { return [] }
              return layer.pins.enumerated().map { pinIdx, pin in
                  PinDescriptor(id: "\(layer.id)#\(pinIdx)", layerID: layer.id, pinIndex: pinIdx, pin: pin)
              }
          }
      }
  ```

  Update `pinView(idx:pin:fit:)` to take `layerID:idx:pin:fit:` and route drag/delete through the layer-aware helpers. Replace the function signature + body:

  ```swift
      @State private var pinDragBaseline: [String: CGPoint] = [:]

      private func pinDragGesture(layerID: String, idx: Int, fit: FitRect) -> some Gesture {
          let key = "\(layerID)#\(idx)"
          return DragGesture(minimumDistance: 2)
              .onChanged { value in
                  guard var d = doc,
                        let lIdx = d.layers.firstIndex(where: { $0.id == layerID }),
                        idx < d.layers[lIdx].pins.count
                  else { return }
                  if pinDragBaseline[key] == nil {
                      pinDragBaseline[key] = CGPoint(x: d.layers[lIdx].pins[idx].x, y: d.layers[lIdx].pins[idx].y)
                  }
                  guard let base = pinDragBaseline[key] else { return }
                  let dx = Double(value.translation.width) / fit.size.width / scale
                  let dy = Double(value.translation.height) / fit.size.height / scale
                  d.layers[lIdx].pins[idx].x = MapGeometry.clampNormalized(Double(base.x) + dx)
                  d.layers[lIdx].pins[idx].y = MapGeometry.clampNormalized(Double(base.y) + dy)
                  doc = d
              }
              .onEnded { _ in
                  pinDragBaseline[key] = nil
                  if let d = doc, let store = session.store {
                      try? store.saveMap(d, name: name)
                  }
              }
      }

      private func deletePin(layerID: String, idx: Int) {
          guard var d = doc,
                let lIdx = d.layers.firstIndex(where: { $0.id == layerID }),
                idx < d.layers[lIdx].pins.count,
                let store = session.store
          else { return }
          d.layers[lIdx].pins.remove(at: idx)
          try? store.saveMap(d, name: name)
          doc = d
      }

      private func pinView(layerID: String, idx: Int, pin: MapPin, fit: FitRect) -> some View {
          let px = fit.origin.x + CGFloat(pin.clampedX) * fit.size.width
          let py = fit.origin.y + CGFloat(pin.clampedY) * fit.size.height
          let label = Self.displayLabel(for: pin, entities: session.store?.entities ?? [])
          return ZStack(alignment: .top) {
              Circle()
                  .fill(Color.red)
                  .frame(width: 12, height: 12)
                  .overlay(Circle().stroke(Color.white, lineWidth: 1))
              Text(label)
                  .font(.caption2).lineLimit(1).truncationMode(.tail)
                  .padding(.horizontal, 4).padding(.vertical, 1)
                  .background(.regularMaterial)
                  .clipShape(RoundedRectangle(cornerRadius: 3))
                  .frame(maxWidth: 120).offset(y: 14)
          }
          .position(x: px, y: py + 8)
          .help(label)
          .onTapGesture { tabs.open(.entity(pin.locationId)) }
          .gesture(pinDragGesture(layerID: layerID, idx: idx, fit: fit))
          .contextMenu {
              Button(role: .destructive) { deletePin(layerID: layerID, idx: idx) } label: { Text("Delete pin") }
          }
      }
  ```

  Update the `addPin(at:locationID:)` helper to use the active layer:

  ```swift
      @State private var activeLayerID: String = "default"

      private func addPin(at normalized: CGPoint, locationID: EntityID) {
          guard var d = doc, let store = session.store else { return }
          let label = store.entities.first(where: { $0.id == locationID })?.name
          let pin = MapPin(x: Double(normalized.x), y: Double(normalized.y), locationId: locationID, label: label)
          let targetLayer = d.layer(id: activeLayerID) != nil ? activeLayerID : (d.layers.first?.id ?? "default")
          d.addPin(pin, toLayer: targetLayer)
          try? store.saveMap(d, name: name)
          doc = d
      }
  ```

  In `load()`, after `doc = d`, reset `activeLayerID` to the first layer's id if the current value isn't found:

  ```swift
          if !d.layers.contains(where: { $0.id == activeLayerID }) {
              activeLayerID = d.layers.first?.id ?? "default"
          }
  ```

- [ ] **Step 3: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds. Tests still pass.

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(map): render pins per-layer; ⌘-click targets active layer"
  ```

---

## Task 4: LayerPanel UI

**Files:**
- Create: `FantasyTavernApp/Sources/Map/LayerPanel.swift`
- Modify: `FantasyTavernApp/Sources/Map/MapView.swift` (mount panel)

- [ ] **Step 1: `LayerPanel`**

  ```swift
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
  ```

- [ ] **Step 2: Mount panel in MapView**

  Inside the outer `Group` (where `if let doc, let image`), wrap with an `HStack` so the panel sits to the right of the canvas. Replace:

  ```swift
              if let doc, let image {
                  GeometryReader { geo in
                      // existing canvas
                  }
                  .popover(...) {
                      AddPinPopover { ... }
                  }
              }
  ```

  With:

  ```swift
              if let doc, let image {
                  HStack(spacing: 0) {
                      GeometryReader { geo in
                          // existing canvas body unchanged
                      }
                      .popover(isPresented: Binding(
                          get: { pendingPinNormalized != nil },
                          set: { if !$0 { pendingPinNormalized = nil } }
                      )) {
                          AddPinPopover { locationID in
                              if let p = pendingPinNormalized {
                                  addPin(at: p, locationID: locationID)
                                  pendingPinNormalized = nil
                              }
                          }
                      }
                      LayerPanel(
                          doc: Binding(
                              get: { self.doc ?? doc },
                              set: { newDoc in
                                  self.doc = newDoc
                              }
                          ),
                          activeLayerID: $activeLayerID,
                          onChange: { persistDoc() }
                      )
                      .frame(width: 200)
                  }
              }
  ```

  And add the `persistDoc` helper:

  ```swift
      private func persistDoc() {
          guard let d = doc, let store = session.store else { return }
          try? store.saveMap(d, name: name)
      }
  ```

- [ ] **Step 3: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, tests pass.

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(map): LayerPanel UI (toggle visibility, add/rename/delete, pick active)"
  ```

---

## Task 5: Manual acceptance

- [ ] **Step 1: Build + launch**

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -3
  pkill -f FantasyTavernApp 2>/dev/null || true
  sleep 1
  open ~/Library/Developer/Xcode/DerivedData/FantasyTavern-cjpexdvcsmhrwcafqhtvzpbgihqg/Build/Products/Debug/FantasyTavernApp.app
  ```

- [ ] **Step 2: Walkthrough**

  1. Open Aetheria → Maps → overworld. Existing pins still render under "Default" layer.
  2. Cat the map JSON: should still be old shape until you touch it. ⌘-click anywhere → add a pin → check JSON: now `"layers":[…]` format, no `"pins":` top-level.
  3. Layer panel on the right: "Default" listed w/ checkbox on. Untick → all pins disappear. Re-tick → reappear.
  4. Click "Add Layer" → "Layer 2" appears, becomes active (highlighted). ⌘-click → new pin lands in Layer 2. Toggling Layer 2 visibility hides only those pins.
  5. Rename Layer 2 inline. Delete it via trash icon. Default remains; trash on Default disabled.
  6. Quit + relaunch → state persists.

- [ ] **Step 3: Tag**

  ```bash
  git tag plan-7-map-layers-complete
  ```

---

## Deferred from Plan 7 (call out at review)

- Drag-to-reorder layers.
- Per-layer color tint.
- Per-layer read-only flag.
- Importing/exporting individual layers.

## Self-Review notes

**Spec coverage:**
- Layers schema with backward compat: Task 1.
- Mutation helpers: Task 2.
- Visible-layer rendering + active-layer ⌘-click: Task 3.
- UI panel: Task 4.

**Placeholder scan:** clean.

**Type consistency:**
- `MapLayer` (id/name/visible/pins) consistent Tasks 1, 2, 3, 4.
- `MapDoc.layers: [MapLayer]` + `allPins` / `visiblePins` / `layer(id:)` / `addLayer()` / `removeLayer(id:)` / `renameLayer(id:to:)` / `setVisibility(id:visible:)` / `addPin(_:toLayer:)` consistent.
- `MapView.activeLayerID` String matching `MapLayer.id`.
- `pinDragBaseline` keyed by `"<layerID>#<idx>"` consistent within Task 3.
