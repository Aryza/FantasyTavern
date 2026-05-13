# FantasyTavern Plan 8 — Hex Grid Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a from-scratch hex map editor. Worlds can host any number of hex maps under `<world>/hexmaps/<name>.json`. Editor paints terrain per cell with a brush palette; click + drag paint, right-click erases. Tabs and sidebar expose hex maps alongside image maps.

**Architecture:**
- Pure-logic `HexMapDoc`, `HexCell`, `HexPaletteEntry` types added to `WorldStore` package, paired with `HexMapStore` (list/load/save) and a tiny `HexGeometry` helper in the app target for pixel↔cell math (so the editor view stays small).
- Pointy-top hex orientation, odd-r offset coordinates. Per-cell `terrain` is a palette key (string). Default palette ships with 8 entries (empty/plains/forest/hills/mountain/water/desert/town).
- `HexMapView` uses SwiftUI `Canvas` to render the grid. Click + drag paints with the active brush. Right-click sets `empty`.
- `TabContent` gains `.hexMap(String)`. Sidebar lists `Hex Maps (n)` section. File menu → "New → Hex Map…" prompts for name + dimensions.

**Tech Stack:** Same as prior plans — Swift 5.10+, macOS 14+, SwiftUI, AppKit, XCTest, XcodeGen. No new SPM packages.

**Plan 8 success criteria:**
1. File → New → Hex Map… → prompt for name + cols + rows → creates `hexmaps/<slug>.json`, opens a tab.
2. Sidebar's `Views` section lists every hex map. Click → opens / focuses tab.
3. The editor tab renders the grid as pointy-top hexes filled with the cell's palette color.
4. A palette strip across the top lists named brushes; clicking selects active brush.
5. Left-click a cell paints with active brush. Drag continues painting. Right-click clears to `empty`.
6. Edits persist to disk via debounced save (500 ms).
7. Existing image map functionality untouched.
8. All package tests stay green; new tests cover JSON round-trip, mutator helpers, and hex pixel↔cell math.

**Out of scope (later polish):**
- Resize-after-create (cols/rows fixed at create time; if needed, edit JSON).
- Flat-top orientation toggle.
- Per-cell label / location-link UI (model already supports it; editor exposes only terrain paint in v1).
- Custom palette editing in app (defaults only; user can edit JSON for now).
- Zoom / pan in editor.

---

## File Structure

```
Packages/WorldStore/Sources/WorldStore/
  HexMap.swift                              # NEW: HexCell, HexPaletteEntry, HexMapDoc + mutators
  HexMapStore.swift                         # NEW: list/load/save by name
  WorldStore.swift                          # MODIFY: expose hexMapNames + load/save helpers
Packages/WorldStore/Tests/WorldStoreTests/
  HexMapTests.swift                         # NEW: round-trip + mutators
  HexMapStoreTests.swift                    # NEW

FantasyTavernApp/Sources/
  HexMap/
    HexGeometry.swift                       # NEW: pure-logic pixel↔cell + center/path helpers
    HexMapView.swift                        # NEW: SwiftUI Canvas editor
    NewHexMapSheet.swift                    # NEW: name + dims prompt
  Tabs/TabContent.swift                     # MODIFY: add .hexMap(String) case
  Sidebar/SidebarView.swift                 # MODIFY: render Hex Maps section
  Tabs/TabBarView.swift                     # MODIFY: label "Hex Map: <name>" for .hexMap
  ContentView.swift                         # MODIFY: dispatch .hexMap → HexMapView
  Commands/AppCommands.swift                # MODIFY: New > Hex Map… menu item
FantasyTavernApp/Tests/
  HexGeometryTests.swift                    # NEW
```

**Why this split:**
- `HexMap.swift` is just types + mutators; lives next to `Map.swift`.
- `HexGeometry` pure-math kept testable.
- `HexMapView` only renders + handles input; mutation calls into doc helpers.
- `NewHexMapSheet` keeps the dimension-prompt UI isolated.

---

## Conventions (carry-over + additions)

- **Hex orientation:** pointy-top (vertex up). Stored `orientation: "pointy"` for forward compatibility but not switchable in v1.
- **Offset coordinates:** odd-r. Cell `(col, row)` row indexed from top.
- **Cell hex size (`s`):** 24 pt edge length default. Editor view uses a fixed size; zoom deferred.
- **Pointy-top math:**
  - `hexWidth  = s * sqrt(3)`
  - `hexHeight = s * 2`
  - `center.x = s * sqrt(3) * (Double(col) + (row.isMultiple(of: 2) ? 0.0 : 0.5))`
  - `center.y = s * 1.5 * Double(row)`
- **Grid pixel size:**
  - `totalWidth = hexWidth * (Double(cols) + (rows > 1 ? 0.5 : 0))`
  - `totalHeight = hexHeight * (1 + Double(rows - 1) * 0.75)` for rows ≥ 1
- **Hit testing:** scan cells; pick the cell whose center is closest within `s`. Cheap for v1 grid sizes (≤ 60×60).
- **Default palette keys + colors** (hex):
  - `empty` `#F5F5F5`
  - `plains` `#C8E6A0`
  - `forest` `#3F7D3F`
  - `hills` `#A78A5D`
  - `mountain` `#7E7E7E`
  - `water` `#5085C5`
  - `desert` `#E4C97A`
  - `town` `#B85C4A`
- **Filename slug:** reuse `Slug.make(_:)` from `WorldStore`.

---

## Task 1: HexMap model + mutators

**Files:**
- Create: `Packages/WorldStore/Sources/WorldStore/HexMap.swift`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/HexMapTests.swift`

- [ ] **Step 1: Failing tests**

  ```swift
  import XCTest
  import EntityModel
  @testable import WorldStore

  final class HexMapTests: XCTestCase {
      func test_defaultPalette_hasEightEntries() {
          XCTAssertEqual(HexMapDoc.defaultPalette.map(\.key),
                         ["empty","plains","forest","hills","mountain","water","desert","town"])
      }

      func test_make_filledWithEmpty() {
          let doc = HexMapDoc.make(cols: 3, rows: 2)
          XCTAssertEqual(doc.cols, 3)
          XCTAssertEqual(doc.rows, 2)
          XCTAssertEqual(doc.cells.count, 2)
          XCTAssertEqual(doc.cells[0].count, 3)
          XCTAssertTrue(doc.cells.flatMap { $0 }.allSatisfy { $0.terrain == "empty" })
      }

      func test_setTerrain_updatesCell() {
          var doc = HexMapDoc.make(cols: 2, rows: 2)
          doc.setTerrain("forest", col: 1, row: 0)
          XCTAssertEqual(doc.cell(col: 1, row: 0)?.terrain, "forest")
      }

      func test_setTerrain_outOfBounds_isNoOp() {
          var doc = HexMapDoc.make(cols: 1, rows: 1)
          doc.setTerrain("forest", col: 5, row: 5)
          doc.setTerrain("forest", col: -1, row: 0)
          XCTAssertEqual(doc.cell(col: 0, row: 0)?.terrain, "empty")
      }

      func test_codable_roundTrip() throws {
          var doc = HexMapDoc.make(cols: 2, rows: 2)
          doc.setTerrain("forest", col: 0, row: 0)
          doc.setTerrain("water",  col: 1, row: 1)
          let data = try JSONEncoder().encode(doc)
          let decoded = try JSONDecoder().decode(HexMapDoc.self, from: data)
          XCTAssertEqual(decoded, doc)
      }
  }
  ```

- [ ] **Step 2: Run** — `swift test --package-path Packages/WorldStore --filter HexMapTests`. Expect compile failure.

- [ ] **Step 3: Implement**

  `Packages/WorldStore/Sources/WorldStore/HexMap.swift`:

  ```swift
  import Foundation
  import EntityModel

  public struct HexCell: Equatable, Codable, Sendable {
      public var terrain: String
      public var label: String?
      public var locationId: EntityID?

      public init(terrain: String = "empty", label: String? = nil, locationId: EntityID? = nil) {
          self.terrain = terrain
          self.label = label
          self.locationId = locationId
      }
  }

  public struct HexPaletteEntry: Equatable, Codable, Sendable, Identifiable {
      public var key: String
      public var name: String
      public var colorHex: String

      public var id: String { key }

      public init(key: String, name: String, colorHex: String) {
          self.key = key
          self.name = name
          self.colorHex = colorHex
      }
  }

  public struct HexMapDoc: Equatable, Codable, Sendable {
      public var cols: Int
      public var rows: Int
      public var orientation: String
      public var palette: [HexPaletteEntry]
      public var cells: [[HexCell]]

      public init(cols: Int, rows: Int, orientation: String = "pointy",
                  palette: [HexPaletteEntry] = HexMapDoc.defaultPalette,
                  cells: [[HexCell]]) {
          self.cols = cols
          self.rows = rows
          self.orientation = orientation
          self.palette = palette
          self.cells = cells
      }

      public static let defaultPalette: [HexPaletteEntry] = [
          .init(key: "empty",    name: "Empty",    colorHex: "#F5F5F5"),
          .init(key: "plains",   name: "Plains",   colorHex: "#C8E6A0"),
          .init(key: "forest",   name: "Forest",   colorHex: "#3F7D3F"),
          .init(key: "hills",    name: "Hills",    colorHex: "#A78A5D"),
          .init(key: "mountain", name: "Mountain", colorHex: "#7E7E7E"),
          .init(key: "water",    name: "Water",    colorHex: "#5085C5"),
          .init(key: "desert",   name: "Desert",   colorHex: "#E4C97A"),
          .init(key: "town",     name: "Town",     colorHex: "#B85C4A"),
      ]

      public static func make(cols: Int, rows: Int) -> HexMapDoc {
          let row = Array(repeating: HexCell(), count: max(0, cols))
          let cells = Array(repeating: row, count: max(0, rows))
          return HexMapDoc(cols: max(0, cols), rows: max(0, rows), cells: cells)
      }

      public func cell(col: Int, row: Int) -> HexCell? {
          guard row >= 0, row < cells.count, col >= 0, col < cells[row].count else { return nil }
          return cells[row][col]
      }

      public mutating func setTerrain(_ terrain: String, col: Int, row: Int) {
          guard row >= 0, row < cells.count, col >= 0, col < cells[row].count else { return }
          cells[row][col].terrain = terrain
      }
  }
  ```

- [ ] **Step 4: Run** — 5 tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WorldStore
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(WorldStore): HexCell + HexMapDoc + default palette"
  ```

---

## Task 2: HexMapStore (list/load/save)

**Files:**
- Create: `Packages/WorldStore/Sources/WorldStore/HexMapStore.swift`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/HexMapStoreTests.swift`

- [ ] **Step 1: Failing tests**

  ```swift
  import XCTest
  import EntityModel
  @testable import WorldStore

  final class HexMapStoreTests: XCTestCase {
      var tmp: URL!

      override func setUpWithError() throws {
          tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
      }
      override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

      func test_listNames_findsFiles() throws {
          let dir = tmp.appendingPathComponent("hexmaps")
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          try Data("{}".utf8).write(to: dir.appendingPathComponent("overworld.json"))
          try Data("{}".utf8).write(to: dir.appendingPathComponent("dungeon.json"))
          try Data("nope".utf8).write(to: dir.appendingPathComponent("notes.txt"))
          XCTAssertEqual(Set(HexMapStore.listNames(in: tmp)), Set(["overworld", "dungeon"]))
      }

      func test_save_thenLoad_roundTrip() throws {
          var doc = HexMapDoc.make(cols: 4, rows: 3)
          doc.setTerrain("forest", col: 1, row: 1)
          try HexMapStore.save(doc, name: "overworld", in: tmp)
          let reread = try HexMapStore.load(name: "overworld", in: tmp)
          XCTAssertEqual(reread, doc)
      }

      func test_load_missing_throws() {
          XCTAssertThrowsError(try HexMapStore.load(name: "nope", in: tmp))
      }
  }
  ```

- [ ] **Step 2: Run** — expect compile failure.

- [ ] **Step 3: Implement**

  `Packages/WorldStore/Sources/WorldStore/HexMapStore.swift`:

  ```swift
  import Foundation

  public enum HexMapStoreError: Error {
      case missing(String)
  }

  public enum HexMapStore {
      public static func listNames(in worldFolder: URL) -> [String] {
          let dir = worldFolder.appendingPathComponent("hexmaps")
          guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
          return files
              .filter { $0.pathExtension.lowercased() == "json" }
              .map { $0.deletingPathExtension().lastPathComponent }
              .sorted()
      }

      public static func load(name: String, in worldFolder: URL) throws -> HexMapDoc {
          let url = worldFolder.appendingPathComponent("hexmaps").appendingPathComponent("\(name).json")
          guard let data = try? Data(contentsOf: url) else {
              throw HexMapStoreError.missing(name)
          }
          return try JSONDecoder().decode(HexMapDoc.self, from: data)
      }

      public static func save(_ doc: HexMapDoc, name: String, in worldFolder: URL) throws {
          let dir = worldFolder.appendingPathComponent("hexmaps")
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          let target = dir.appendingPathComponent("\(name).json")
          let tmp = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
          let encoder = JSONEncoder()
          encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
          let data = try encoder.encode(doc)
          try data.write(to: tmp, options: .atomic)
          if FileManager.default.fileExists(atPath: target.path) {
              _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
          } else {
              try FileManager.default.moveItem(at: tmp, to: target)
          }
      }
  }
  ```

- [ ] **Step 4: Run** — 3 new tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WorldStore
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(WorldStore): HexMapStore (list/load/save)"
  ```

---

## Task 3: WorldStore exposes hex maps

**Files:**
- Modify: `Packages/WorldStore/Sources/WorldStore/WorldStore.swift`
- Modify: `Packages/WorldStore/Tests/WorldStoreTests/WorldStoreTests.swift`

- [ ] **Step 1: Failing tests**

  Append to `WorldStoreTests.swift` (inside the class):

  ```swift
      func test_open_listsHexMaps() throws {
          let url = try copyFixtureWorld()
          let dir = url.appendingPathComponent("hexmaps")
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          let doc = HexMapDoc.make(cols: 2, rows: 2)
          try HexMapStore.save(doc, name: "overworld", in: url)
          let store = try WorldStore.open(url)
          XCTAssertEqual(store.hexMapNames, ["overworld"])
      }

      func test_saveHexMap_updatesList() throws {
          let url = try copyFixtureWorld()
          let store = try WorldStore.open(url)
          XCTAssertEqual(store.hexMapNames, [])
          let doc = HexMapDoc.make(cols: 2, rows: 2)
          try store.saveHexMap(doc, name: "underdark")
          XCTAssertEqual(store.hexMapNames, ["underdark"])
      }
  ```

- [ ] **Step 2: Run** — expect compile failure (`hexMapNames` / `saveHexMap` / `loadHexMap` unknown).

- [ ] **Step 3: Update `WorldStore`**

  Modify the class:

  ```swift
  @Observable
  public final class WorldStore {
      public private(set) var world: World
      public private(set) var entities: [Entity]
      public private(set) var schema: Schema
      public private(set) var mapNames: [String]
      public private(set) var hexMapNames: [String]
      public private(set) var calendar: WorldCalendar

      private init(world: World, entities: [Entity], schema: Schema,
                   mapNames: [String], hexMapNames: [String], calendar: WorldCalendar) {
          self.world = world
          self.entities = entities
          self.schema = schema
          self.mapNames = mapNames
          self.hexMapNames = hexMapNames
          self.calendar = calendar
      }
      // existing open() implementation — also do:
      //   let hexMapNames = HexMapStore.listNames(in: folder)
      // and pass to the initializer.

      public func loadHexMap(named name: String) throws -> HexMapDoc {
          try HexMapStore.load(name: name, in: world.folder)
      }

      public func saveHexMap(_ doc: HexMapDoc, name: String) throws {
          try HexMapStore.save(doc, name: name, in: world.folder)
          if !hexMapNames.contains(name) {
              hexMapNames.append(name)
              hexMapNames.sort()
          }
      }

      public func reloadHexMapNames() {
          hexMapNames = HexMapStore.listNames(in: world.folder)
      }
      // …rest unchanged
  }
  ```

  Read existing `WorldStore.swift` and apply minimal edits — preserve all current behavior. The `open(_:)` must populate `hexMapNames` from `HexMapStore.listNames(in: folder)` and pass into the new init signature.

- [ ] **Step 4: Run all WorldStore tests** — expect 2 new pass; total WorldStore tests up by 2.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WorldStore
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(WorldStore): expose hexMapNames + load/save helpers"
  ```

---

## Task 4: HexGeometry pure-logic helper

**Files:**
- Create: `FantasyTavernApp/Sources/HexMap/HexGeometry.swift`
- Create: `FantasyTavernApp/Tests/HexGeometryTests.swift`

- [ ] **Step 1: Failing tests**

  ```swift
  import XCTest
  @testable import FantasyTavernApp

  final class HexGeometryTests: XCTestCase {
      func test_centerForOrigin() {
          let p = HexGeometry.center(col: 0, row: 0, size: 24)
          XCTAssertEqual(p.x, 0, accuracy: 0.001)
          XCTAssertEqual(p.y, 0, accuracy: 0.001)
      }

      func test_oddRowOffsetX() {
          // row 1 (odd) is shifted right by hexWidth/2
          let p0 = HexGeometry.center(col: 0, row: 0, size: 24)
          let p1 = HexGeometry.center(col: 0, row: 1, size: 24)
          let hexWidth = 24.0 * sqrt(3.0)
          XCTAssertEqual(p1.x - p0.x, hexWidth / 2, accuracy: 0.001)
      }

      func test_columnSpacing() {
          let a = HexGeometry.center(col: 0, row: 0, size: 24)
          let b = HexGeometry.center(col: 1, row: 0, size: 24)
          let hexWidth = 24.0 * sqrt(3.0)
          XCTAssertEqual(b.x - a.x, hexWidth, accuracy: 0.001)
      }

      func test_rowSpacing() {
          let a = HexGeometry.center(col: 0, row: 0, size: 24)
          let b = HexGeometry.center(col: 0, row: 1, size: 24)
          XCTAssertEqual(b.y - a.y, 24.0 * 1.5, accuracy: 0.001)
      }

      func test_cellAtPoint_centerHits() {
          let c = HexGeometry.center(col: 2, row: 3, size: 24)
          let result = HexGeometry.cellAt(point: c, size: 24, cols: 6, rows: 6)
          XCTAssertEqual(result?.col, 2)
          XCTAssertEqual(result?.row, 3)
      }

      func test_cellAtPoint_outsideAllCells_nil() {
          let result = HexGeometry.cellAt(point: CGPoint(x: -1000, y: -1000), size: 24, cols: 6, rows: 6)
          XCTAssertNil(result)
      }

      func test_totalSize_growsWithGrid() {
          let s1 = HexGeometry.totalSize(cols: 1, rows: 1, size: 24)
          let s10 = HexGeometry.totalSize(cols: 10, rows: 10, size: 24)
          XCTAssertGreaterThan(s10.width, s1.width)
          XCTAssertGreaterThan(s10.height, s1.height)
      }
  }
  ```

- [ ] **Step 2: Implement**

  `FantasyTavernApp/Sources/HexMap/HexGeometry.swift`:

  ```swift
  import CoreGraphics
  import Foundation

  enum HexGeometry {
      struct Coord: Equatable { let col: Int; let row: Int }

      static func center(col: Int, row: Int, size: Double) -> CGPoint {
          let hexWidth = size * sqrt(3.0)
          let xOffset = row.isMultiple(of: 2) ? 0.0 : hexWidth / 2.0
          let x = hexWidth * Double(col) + xOffset
          let y = size * 1.5 * Double(row)
          return CGPoint(x: x, y: y)
      }

      static func cellAt(point: CGPoint, size: Double, cols: Int, rows: Int) -> Coord? {
          guard cols > 0, rows > 0 else { return nil }
          var best: (dist: Double, coord: Coord)?
          for r in 0..<rows {
              for c in 0..<cols {
                  let center = HexGeometry.center(col: c, row: r, size: size)
                  let dx = point.x - center.x
                  let dy = point.y - center.y
                  let d = sqrt(Double(dx * dx + dy * dy))
                  if d <= size && (best == nil || d < best!.dist) {
                      best = (d, Coord(col: c, row: r))
                  }
              }
          }
          return best?.coord
      }

      static func totalSize(cols: Int, rows: Int, size: Double) -> CGSize {
          guard cols > 0, rows > 0 else { return .zero }
          let hexWidth = size * sqrt(3.0)
          let hexHeight = size * 2
          let width = hexWidth * (Double(cols) + (rows > 1 ? 0.5 : 0))
          let height = hexHeight * (1 + Double(rows - 1) * 0.75)
          return CGSize(width: width, height: height)
      }

      static func hexPath(centerX cx: Double, centerY cy: Double, size: Double) -> CGPath {
          // pointy-top: vertices at angles 90°, 150°, 210°, 270°, 330°, 30°
          let path = CGMutablePath()
          for i in 0..<6 {
              let angle = (Double.pi / 180.0) * (60.0 * Double(i) - 30.0)
              let x = cx + size * cos(angle)
              let y = cy + size * sin(angle)
              if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
              else { path.addLine(to: CGPoint(x: x, y: y)) }
          }
          path.closeSubpath()
          return path
      }
  }
  ```

- [ ] **Step 3: Run tests** — expect 7 new pass.

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(hexmap): HexGeometry pure-logic helpers"
  ```

---

## Task 5: TabContent.hexMap + Sidebar + TabBar dispatch

**Files:**
- Modify: `FantasyTavernApp/Sources/Tabs/TabContent.swift`
- Modify: `FantasyTavernApp/Sources/Sidebar/SidebarView.swift`
- Modify: `FantasyTavernApp/Sources/Tabs/TabBarView.swift`
- Modify: `FantasyTavernApp/Sources/ContentView.swift` (stub dispatch to placeholder)

- [ ] **Step 1: Extend `TabContent`**

  ```swift
  public enum TabContent: Hashable, Sendable {
      case entity(EntityID)
      case timeline
      case map(String)
      case hexMap(String)

      public var entityID: EntityID? {
          if case .entity(let id) = self { return id } else { return nil }
      }
  }
  ```

- [ ] **Step 2: Add Sidebar row** — under existing "Views" section, after `DisclosureGroup("Maps (...)")`, add:

  ```swift
                          let hexNames = session.store?.hexMapNames ?? []
                          DisclosureGroup("Hex Maps (\(hexNames.count))") {
                              if hexNames.isEmpty {
                                  Text("No hex maps in folder").foregroundStyle(.secondary).font(.caption)
                              } else {
                                  ForEach(hexNames, id: \.self) { name in
                                      Button(name) { tabs.open(.hexMap(name)) }.buttonStyle(.plain)
                                  }
                              }
                          }
  ```

- [ ] **Step 3: Tab label** — In `TabBarView.label(for:)`:

  ```swift
          case .hexMap(let name):
              return "Hex Map: \(name)"
  ```

- [ ] **Step 4: ContentView dispatch** — Add case in the detail switch:

  ```swift
          case .hexMap(let name):
              HexMapView(name: name)
  ```

  Since `HexMapView` isn't implemented yet, add a stub for now:

  Create `FantasyTavernApp/Sources/HexMap/HexMapView.swift` (placeholder):

  ```swift
  import SwiftUI

  struct HexMapView: View {
      let name: String
      var body: some View {
          ContentUnavailableView("Hex Map: \(name) (coming soon)", systemImage: "hexagon")
      }
  }
  ```

- [ ] **Step 5: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, all existing tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(hexmap): TabContent + sidebar + tab bar dispatch (view stubbed)"
  ```

---

## Task 6: NewHexMapSheet + AppCommands menu

**Files:**
- Create: `FantasyTavernApp/Sources/HexMap/NewHexMapSheet.swift`
- Modify: `FantasyTavernApp/Sources/Commands/AppCommands.swift`
- Modify: `FantasyTavernApp/Sources/FantasyTavernAppApp.swift` (sheet plumbing — reuse `SnapshotsPresenter` pattern with a new `HexMapPresenter`)

- [ ] **Step 1: Presenter**

  Create `FantasyTavernApp/Sources/HexMap/HexMapPresenter.swift`:

  ```swift
  import Foundation
  import Observation

  @Observable
  final class HexMapPresenter {
      var isShowingNew: Bool = false
  }
  ```

- [ ] **Step 2: `NewHexMapSheet`**

  ```swift
  import SwiftUI
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
  ```

- [ ] **Step 3: Wire menu item**

  Read existing `AppCommands.swift`. Add `@Bindable var hexPresenter: HexMapPresenter`. Inside the existing `Menu("New")`, append:

  ```swift
                      Divider()
                      Button("Hex Map…") { hexPresenter.isShowingNew = true }
                          .disabled(session.store == nil)
  ```

- [ ] **Step 4: Mount sheet in `FantasyTavernAppApp`**

  Add `@State private var hexPresenter = HexMapPresenter()`. Inject `.environment(hexPresenter)` on the main `ContentView`. Add `.sheet(isPresented:)` binding to `hexPresenter.isShowingNew` displaying `NewHexMapSheet().environment(session).environment(tabs)`. Pass `hexPresenter: hexPresenter` into `AppCommands(...)`.

- [ ] **Step 5: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, all tests still pass.

- [ ] **Step 6: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(hexmap): New → Hex Map… menu opens dimensions sheet"
  ```

---

## Task 7: HexMapView — Canvas render + paint

**Files:**
- Modify: `FantasyTavernApp/Sources/HexMap/HexMapView.swift` (full rewrite)

- [ ] **Step 1: Implement**

  ```swift
  import SwiftUI
  import AppKit
  import WorldStore

  struct HexMapView: View {
      @Environment(WorldSession.self) private var session
      let name: String

      @State private var doc: HexMapDoc?
      @State private var loadError: String?
      @State private var activeBrush: String = "plains"
      @State private var saveTask: Task<Void, Never>?

      private let cellSize: Double = 24

      var body: some View {
          Group {
              if let doc {
                  VStack(spacing: 0) {
                      palette(doc: doc)
                      Divider()
                      ScrollView([.horizontal, .vertical]) {
                          canvas(doc: doc)
                              .padding(20)
                      }
                  }
              } else if let loadError {
                  ContentUnavailableView(loadError, systemImage: "exclamationmark.triangle")
              } else {
                  ProgressView().task { load() }
              }
          }
      }

      private func palette(doc: HexMapDoc) -> some View {
          ScrollView(.horizontal) {
              HStack(spacing: 6) {
                  ForEach(doc.palette) { entry in
                      Button {
                          activeBrush = entry.key
                      } label: {
                          HStack(spacing: 6) {
                              Circle()
                                  .fill(Color(hex: entry.colorHex))
                                  .frame(width: 14, height: 14)
                                  .overlay(Circle().stroke(Color.primary.opacity(0.4)))
                              Text(entry.name).font(.caption)
                          }
                          .padding(.horizontal, 8).padding(.vertical, 4)
                          .background(activeBrush == entry.key ? Color.accentColor.opacity(0.25) : .clear)
                          .clipShape(RoundedRectangle(cornerRadius: 4))
                      }
                      .buttonStyle(.plain)
                  }
              }
              .padding(.horizontal, 12).padding(.vertical, 6)
          }
      }

      private func canvas(doc: HexMapDoc) -> some View {
          let total = HexGeometry.totalSize(cols: doc.cols, rows: doc.rows, size: cellSize)
          let pad = cellSize
          return Canvas { context, _ in
              let colorByKey = Dictionary(uniqueKeysWithValues: doc.palette.map { ($0.key, Color(hex: $0.colorHex)) })
              for r in 0..<doc.rows {
                  for c in 0..<doc.cols {
                      let cell = doc.cells[r][c]
                      let center = HexGeometry.center(col: c, row: r, size: cellSize)
                      let path = Path(HexGeometry.hexPath(centerX: center.x + pad, centerY: center.y + pad, size: cellSize))
                      context.fill(path, with: .color(colorByKey[cell.terrain] ?? .gray))
                      context.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
                  }
              }
          }
          .frame(width: total.width + pad * 2, height: total.height + pad * 2)
          .gesture(paintGesture(pad: pad))
          .gesture(eraseGesture(pad: pad))
      }

      private func paintGesture(pad: Double) -> some Gesture {
          DragGesture(minimumDistance: 0)
              .onChanged { value in
                  paintAt(point: value.location, pad: pad, terrain: activeBrush)
              }
              .onEnded { _ in scheduleSave() }
      }

      private func eraseGesture(pad: Double) -> some Gesture {
          // Right-click on macOS: SwiftUI doesn't expose it directly. Use long-press as fallback or skip.
          // Provide a long-press to erase as a single-finger alternative.
          LongPressGesture(minimumDuration: 0.4)
              .sequenced(before: DragGesture(minimumDistance: 0))
              .onEnded { _ in scheduleSave() }
      }

      private func paintAt(point: CGPoint, pad: Double, terrain: String) {
          guard var d = doc else { return }
          let translated = CGPoint(x: point.x - pad, y: point.y - pad)
          guard let coord = HexGeometry.cellAt(point: translated, size: cellSize, cols: d.cols, rows: d.rows) else { return }
          if d.cells[coord.row][coord.col].terrain == terrain { return }
          d.setTerrain(terrain, col: coord.col, row: coord.row)
          doc = d
      }

      private func load() {
          guard let store = session.store else { loadError = "No world open"; return }
          do {
              doc = try store.loadHexMap(named: name)
          } catch {
              loadError = "Failed to load hex map: \(error)"
          }
      }

      private func scheduleSave() {
          saveTask?.cancel()
          let snapshot = doc
          saveTask = Task {
              try? await Task.sleep(nanoseconds: 500_000_000)
              if Task.isCancelled { return }
              guard let d = snapshot, let store = session.store else { return }
              try? store.saveHexMap(d, name: name)
          }
      }
  }

  // MARK: - Color from #hex helper

  extension Color {
      init(hex: String) {
          var hexString = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
          if hexString.count == 3 {
              hexString = hexString.map { "\($0)\($0)" }.joined()
          }
          guard hexString.count == 6, let intVal = UInt64(hexString, radix: 16) else {
              self = .gray
              return
          }
          let r = Double((intVal >> 16) & 0xFF) / 255.0
          let g = Double((intVal >> 8) & 0xFF) / 255.0
          let b = Double(intVal & 0xFF) / 255.0
          self.init(red: r, green: g, blue: b)
      }
  }
  ```

  Note on right-click erase: macOS SwiftUI gestures don't natively split left/right buttons. The plan's `eraseGesture` is a long-press fallback. A cleaner solution is a `.contextMenu` per cell, but that's a lot of contextMenus. For v1 keep the simple long-press fallback or skip erase entirely — user can paint over with `empty` brush. **Decision: ship without long-press erase.** Remove the `eraseGesture` modifier from the canvas; document `Pick "Empty" brush and paint` as the erase workflow.

  Apply that — drop both `.gesture(eraseGesture(...))` and the `eraseGesture` method.

- [ ] **Step 2: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, tests still pass.

- [ ] **Step 3: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(hexmap): Canvas-based grid editor + brush palette"
  ```

---

## Task 8: Manual acceptance

- [ ] **Step 1: Build + launch**

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -3
  pkill -f FantasyTavernApp 2>/dev/null || true
  sleep 1
  open ~/Library/Developer/Xcode/DerivedData/FantasyTavern-cjpexdvcsmhrwcafqhtvzpbgihqg/Build/Products/Debug/FantasyTavernApp.app
  ```

- [ ] **Step 2: Walkthrough**

  1. Open Aetheria. Sidebar's "Views" section gains "Hex Maps (0)".
  2. File → New → Hex Map… → name "overworld" cols 20 rows 15 → Create.
  3. Tab "Hex Map: overworld" opens. Grid shows 20×15 light-grey hexes.
  4. Palette strip at top. Click "Forest" → highlighted active.
  5. Click + drag on hexes → painted green.
  6. Pick "Water" → paint a river. Pick "Mountain" → cluster.
  7. Pick "Empty" → paint over to erase.
  8. Wait ~1s. Inspect `~/Documents/FantasyTavern/Aetheria/hexmaps/overworld.json` — `cells` array has the terrain keys you painted.
  9. Quit + relaunch → state persists.
  10. Sidebar shows "Hex Maps (1)" → click → focuses existing tab.

- [ ] **Step 3: Tag**

  ```bash
  git tag plan-8-hex-grid-complete
  ```

---

## Deferred from Plan 8 (call out at review)

- Right-click erase (currently use "Empty" brush — single-stroke erase).
- Resize-after-create.
- Flat-top orientation.
- Custom palette editing UI.
- Zoom / pan inside editor.
- Per-cell label / location-link UI.
- Coordinate overlay (col,row labels per hex).

## Self-Review notes

**Spec coverage:**
- Hex grid editor / paint terrain: Tasks 1–7. ✓
- Generate from scratch: Task 6 (New Hex Map sheet). ✓
- v1 simple, no fancy editor: matches.

**Placeholder scan:** no TBDs.

**Type consistency:**
- `HexMapDoc.cells[row][col]` consistent across mutators, geometry, view.
- `HexGeometry.center(col:row:size:)`, `cellAt(point:size:cols:rows:)`, `totalSize(cols:rows:size:)`, `hexPath(centerX:centerY:size:)` consistent across Tasks 4 + 7.
- `WorldStore.hexMapNames` / `loadHexMap(named:)` / `saveHexMap(_:name:)` consistent across Tasks 3, 6, 7.
- `TabContent.hexMap(String)` consistent Tasks 5, 6, 7.
- `HexMapPresenter.isShowingNew` consistent Tasks 6.
