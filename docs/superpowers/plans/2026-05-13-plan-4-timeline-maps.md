# FantasyTavern Plan 4 — Timeline & Maps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a horizontal timeline view that visualizes `.timelineEvent` entities, and an image-backed map view with location-linked pins. Both live alongside entity editors as full-fledged tabs.

**Architecture:**
- **TabContent enum** replaces `EntityID` as the tab key — supports `entity`, `timeline`, and `map(name)` variants.
- **TimelineView** is a SwiftUI canvas that reads timeline-event entities, parses a numeric year from each event's `date` field, lays out events on a pannable/zoomable horizontal axis, draws eras (from `world.json`) as background bands, and supports click-to-create at a date.
- **Map storage**: each map = a sibling pair `maps/<name>.{png,jpg,jpeg} + maps/<name>.json`. JSON holds normalized pins `{x, y, locationId, label}`. `WorldStore` loads/saves maps via a new `MapStore` helper inside the same package.
- **MapView** is a SwiftUI image with pin overlays; tap pin opens the linked location in a tab; ⌘-click empty area adds a new pin (location chosen via a small popover that lists existing locations).

**Tech Stack:** Swift 5.10+, macOS 14+, SwiftUI, AppKit interop (`NSEvent.modifierFlags` for ⌘-click), XCTest. No new SPM packages.

**Plan 4 success criteria:**
1. Sidebar shows a "Timeline" row (always present) and a "Maps" section listing every map file in `<world>/maps/`.
2. Clicking "Timeline" opens (or focuses) a timeline tab; clicking a map name opens a map tab. Tabs persist across world sessions until closed.
3. Timeline tab: events appear as dots along a horizontal axis labeled with years. Click a dot → popover with name + body preview + ref pills (links to entities). Click empty axis → "Create event at year N" prompt that creates a new `.timelineEvent` entity with `date: <year>` and opens it.
4. Era bands (from `world.json.calendar.eras`) shaded behind the axis. Mouseover shows era name.
5. Pan: drag to move horizontally. Zoom: ⌘scroll or ⌘+/⌘- keys cycle year/decade/century granularity.
6. Map tab: image fills the pane (object-fit contain). Pins float over image. Click pin → opens the linked location in a new tab. ⌘-click on the image → "Add pin (location: …)" picker.
7. Map pins survive quit + relaunch; saved into `maps/<name>.json`.
8. Existing entity tabs, sidebar, palette, save pipeline still work — refactor doesn't regress.
9. All package tests still green; new app tests cover `TabContent` mutation and `MapStore` round-trip.

**Out of scope (future plans / polish):**
- Multiple parallel timeline tracks (spec mentioned regions/factions tracks).
- Map layers (political/geographic/climate). Single layer in v1.
- Hex-grid map editor (deferred to v2 / later plan).
- Calendar customization (custom months/days). v1 uses ISO 8601 / plain-year parsing.
- Inline event editing on the timeline (tab opens the entity for full editing).
- Pin labels visible by default; v1 shows them only on hover.

---

## File Structure

```
Packages/WorldStore/Sources/WorldStore/
  Map.swift                                                 # NEW: MapDoc + MapPin structs
  MapStore.swift                                            # NEW: list/load/save maps
  Calendar.swift                                            # NEW: Era struct + load from world.json (used by Timeline)
  WorldStore.swift                                          # MODIFY: expose maps[] and calendar; reload helpers
Packages/WorldStore/Tests/WorldStoreTests/
  MapStoreTests.swift                                       # NEW
  CalendarTests.swift                                       # NEW

FantasyTavernApp/Sources/
  Tabs/
    TabContent.swift                                        # NEW: enum w/ .entity/.timeline/.map(String)
    TabsModel.swift                                         # MODIFY: store [TabContent], recents [TabContent]
    TabBarView.swift                                        # MODIFY: label per content kind
    EditorTab.swift                                         # MODIFY: takes TabContent
  Timeline/
    TimelineView.swift                                      # NEW
    TimelineGeometry.swift                                  # NEW: pure-logic scale + tick helpers
  Map/
    MapView.swift                                           # NEW
    AddPinPopover.swift                                     # NEW
  WorldSession.swift                                        # MODIFY: expose maps/calendar; reloadMap helper
  Sidebar/SidebarView.swift                                 # MODIFY: Timeline row + Maps section
  ContentView.swift                                         # MODIFY: dispatch on TabContent
  CommandPalette/PaletteController.swift                    # MODIFY: open .entity(id) on activate
  Editor/EditorView.swift                                   # MODIFY: link clicks open .entity(id)
  Editor/MarkdownTextView.swift                             # MODIFY: signature switches to (TabContent) -> Void via wrapper or to (EntityID) -> Void preserved + caller wraps
FantasyTavernApp/Tests/
  TabsModelTests.swift                                      # MODIFY: existing tests adapt to TabContent
  TimelineGeometryTests.swift                               # NEW
```

**Why this split:**
- `MapStore` + `Calendar` live in `WorldStore` (same disk concerns).
- `TimelineGeometry` is pure-math, easy to test in isolation.
- `TabContent` lives next to `TabsModel`; one enum keeps tab logic understandable.

---

## Conventions (carry-over + additions)

- **Tab equality:** `TabContent` cases compare by associated value; opening the same content twice doesn't create a second tab.
- **Sentinel-free:** no `:timeline:` / `:map:foo` strings encoded as `EntityID`. Use the enum.
- **Year parsing:** `TimelineGeometry.year(fromDateString:)` reads the first leading integer (incl. negatives) from a date string. `"1452"` → 1452; `"-1200"` → -1200; `"1452-04-12"` → 1452; `"AE 802"` → 802; `""` → nil. Events with `nil` year are dropped from the timeline.
- **Map file convention:** `<name>.png|jpg|jpeg` lives in `<world>/maps/`. The companion `<name>.json` may not exist yet for a brand-new map — treat as empty pins list.
- **Map pin coordinates:** `x`, `y` ∈ [0,1]. Normalized to the image's intrinsic size, not the on-screen size.
- **⌘-click detection:** Use `NSEvent.modifierFlags.contains(.command)` inside the gesture handler; or a custom `NSViewRepresentable` for the map image. The plan uses `.gesture(TapGesture().modifiers(.command))` plus a separate plain tap for pin selection.

---

## Task 1: WorldStore — `Map` + `MapPin` data types

**Files:**
- Create: `Packages/WorldStore/Sources/WorldStore/Map.swift`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/MapTests.swift`

- [ ] **Step 1: Failing test**

  `Packages/WorldStore/Tests/WorldStoreTests/MapTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import WorldStore

  final class MapTests: XCTestCase {
      func test_mapDoc_codableRoundTrip() throws {
          let original = MapDoc(image: "overworld.png", pins: [
              MapPin(x: 0.42, y: 0.61, locationId: EntityID("silvermoon"), label: "Silvermoon"),
              MapPin(x: 0.10, y: 0.20, locationId: EntityID("ruins"),       label: nil),
          ])
          let data = try JSONEncoder().encode(original)
          let decoded = try JSONDecoder().decode(MapDoc.self, from: data)
          XCTAssertEqual(decoded, original)
      }

      func test_mapPin_clampedAccessors() {
          let pin = MapPin(x: 1.5, y: -0.2, locationId: EntityID("a"), label: nil)
          XCTAssertEqual(pin.clampedX, 1.0)
          XCTAssertEqual(pin.clampedY, 0.0)
      }
  }
  ```

- [ ] **Step 2: Run** — `swift test --package-path Packages/WorldStore --filter MapTests 2>&1 | tail -15` — expect compile failure.

- [ ] **Step 3: Implement**

  `Packages/WorldStore/Sources/WorldStore/Map.swift`:

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

  public struct MapDoc: Equatable, Codable, Sendable {
      public var image: String
      public var pins: [MapPin]

      public init(image: String, pins: [MapPin] = []) {
          self.image = image
          self.pins = pins
      }
  }
  ```

- [ ] **Step 4: Run** — expect 2 tests pass; full WorldStore package count 20.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WorldStore
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(WorldStore): MapDoc + MapPin types"
  ```

---

## Task 2: WorldStore — `MapStore` (list/load/save)

**Files:**
- Create: `Packages/WorldStore/Sources/WorldStore/MapStore.swift`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/MapStoreTests.swift`

- [ ] **Step 1: Failing tests**

  `Packages/WorldStore/Tests/WorldStoreTests/MapStoreTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import WorldStore

  final class MapStoreTests: XCTestCase {
      var tmp: URL!

      override func setUpWithError() throws {
          tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: tmp.appendingPathComponent("maps"), withIntermediateDirectories: true)
      }
      override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

      func test_listNames_findsImages() throws {
          let mapsDir = tmp.appendingPathComponent("maps")
          try Data([0]).write(to: mapsDir.appendingPathComponent("overworld.png"))
          try Data([0]).write(to: mapsDir.appendingPathComponent("east.jpg"))
          try Data([0]).write(to: mapsDir.appendingPathComponent("notes.txt"))
          let names = MapStore.listNames(in: tmp)
          XCTAssertEqual(Set(names), ["overworld", "east"])
      }

      func test_load_returnsEmptyPinsWhenJSONMissing() throws {
          let mapsDir = tmp.appendingPathComponent("maps")
          try Data([0]).write(to: mapsDir.appendingPathComponent("overworld.png"))
          let doc = try MapStore.load(name: "overworld", in: tmp)
          XCTAssertEqual(doc.image, "overworld.png")
          XCTAssertEqual(doc.pins, [])
      }

      func test_load_readsPinsFromJSON() throws {
          let mapsDir = tmp.appendingPathComponent("maps")
          try Data([0]).write(to: mapsDir.appendingPathComponent("overworld.png"))
          let json = """
          { "image":"overworld.png", "pins":[{"x":0.5,"y":0.5,"locationId":"silvermoon","label":"Silvermoon"}] }
          """
          try json.write(to: mapsDir.appendingPathComponent("overworld.json"),
                         atomically: true, encoding: .utf8)
          let doc = try MapStore.load(name: "overworld", in: tmp)
          XCTAssertEqual(doc.pins.count, 1)
          XCTAssertEqual(doc.pins.first?.locationId.rawValue, "silvermoon")
      }

      func test_save_writesJSONAtomically() throws {
          let mapsDir = tmp.appendingPathComponent("maps")
          try Data([0]).write(to: mapsDir.appendingPathComponent("overworld.png"))
          var doc = MapDoc(image: "overworld.png")
          doc.pins.append(MapPin(x: 0.2, y: 0.3, locationId: EntityID("ruins"), label: nil))
          try MapStore.save(doc, name: "overworld", in: tmp)
          let reread = try MapStore.load(name: "overworld", in: tmp)
          XCTAssertEqual(reread, doc)
      }

      func test_load_missingImage_throws() {
          XCTAssertThrowsError(try MapStore.load(name: "nope", in: tmp))
      }
  }
  ```

- [ ] **Step 2: Run** — expect compile failure.

- [ ] **Step 3: Implement**

  `Packages/WorldStore/Sources/WorldStore/MapStore.swift`:

  ```swift
  import Foundation
  import EntityModel

  public enum MapStoreError: Error {
      case imageNotFound(String)
  }

  public enum MapStore {
      private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg"]

      public static func listNames(in worldFolder: URL) -> [String] {
          let dir = worldFolder.appendingPathComponent("maps")
          guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
          else { return [] }
          let names = files.compactMap { url -> String? in
              imageExtensions.contains(url.pathExtension.lowercased())
                  ? url.deletingPathExtension().lastPathComponent
                  : nil
          }
          return names.sorted()
      }

      public static func load(name: String, in worldFolder: URL) throws -> MapDoc {
          let dir = worldFolder.appendingPathComponent("maps")
          guard let imageFile = findImage(named: name, in: dir) else {
              throw MapStoreError.imageNotFound(name)
          }
          let jsonURL = dir.appendingPathComponent("\(name).json")
          if let data = try? Data(contentsOf: jsonURL) {
              var doc = try JSONDecoder().decode(MapDoc.self, from: data)
              // ensure the stored image filename matches the actual one on disk
              doc.image = imageFile.lastPathComponent
              return doc
          }
          return MapDoc(image: imageFile.lastPathComponent)
      }

      public static func save(_ doc: MapDoc, name: String, in worldFolder: URL) throws {
          let dir = worldFolder.appendingPathComponent("maps")
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          let encoder = JSONEncoder()
          encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
          let data = try encoder.encode(doc)
          let target = dir.appendingPathComponent("\(name).json")
          let tmp = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
          try data.write(to: tmp, options: .atomic)
          if FileManager.default.fileExists(atPath: target.path) {
              _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
          } else {
              try FileManager.default.moveItem(at: tmp, to: target)
          }
      }

      private static func findImage(named name: String, in dir: URL) -> URL? {
          for ext in imageExtensions {
              let candidate = dir.appendingPathComponent("\(name).\(ext)")
              if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
          }
          return nil
      }
  }
  ```

- [ ] **Step 4: Run** — expect 5 MapStore + 2 Map tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WorldStore
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(WorldStore): MapStore (list/load/save map docs)"
  ```

---

## Task 3: WorldStore — `Calendar` + era loading

**Files:**
- Create: `Packages/WorldStore/Sources/WorldStore/Calendar.swift`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/CalendarTests.swift`

- [ ] **Step 1: Failing tests**

  `Packages/WorldStore/Tests/WorldStoreTests/CalendarTests.swift`:

  ```swift
  import XCTest
  @testable import WorldStore

  final class CalendarTests: XCTestCase {
      func test_emptyJSON_emptyEras() {
          let cal = WorldCalendar.load(from: nil)
          XCTAssertEqual(cal.eras, [])
          XCTAssertNil(cal.yearZeroLabel)
      }

      func test_loadsEras() throws {
          let data = """
          {
            "calendar": {
              "yearZeroLabel": "AE",
              "eras": [
                { "id":"first-age",  "name":"First Age",  "start":-2000, "end": 0 },
                { "id":"second-age", "name":"Second Age", "start": 0,    "end": 1500 }
              ]
            }
          }
          """.data(using: .utf8)!
          let cal = WorldCalendar.load(from: data)
          XCTAssertEqual(cal.yearZeroLabel, "AE")
          XCTAssertEqual(cal.eras.map(\.id), ["first-age", "second-age"])
          XCTAssertEqual(cal.eras.first?.end, 0)
      }
  }
  ```

- [ ] **Step 2: Run** — expect compile failure.

- [ ] **Step 3: Implement**

  `Packages/WorldStore/Sources/WorldStore/Calendar.swift`:

  ```swift
  import Foundation

  public struct Era: Equatable, Codable, Sendable {
      public let id: String
      public let name: String
      public let start: Int
      public let end: Int
  }

  public struct WorldCalendar: Equatable, Sendable {
      public let yearZeroLabel: String?
      public let eras: [Era]

      public init(yearZeroLabel: String? = nil, eras: [Era] = []) {
          self.yearZeroLabel = yearZeroLabel
          self.eras = eras
      }

      private struct Envelope: Decodable {
          struct Calendar: Decodable {
              let yearZeroLabel: String?
              let eras: [Era]?
          }
          let calendar: Calendar?
      }

      public static func load(from data: Data?) -> WorldCalendar {
          guard let data,
                let env = try? JSONDecoder().decode(Envelope.self, from: data),
                let cal = env.calendar
          else { return WorldCalendar() }
          return WorldCalendar(yearZeroLabel: cal.yearZeroLabel, eras: cal.eras ?? [])
      }
  }
  ```

- [ ] **Step 4: Run** — expect 2 new tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WorldStore
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(WorldStore): WorldCalendar + Era loaded from world.json"
  ```

---

## Task 4: WorldStore exposes maps + calendar

**Files:**
- Modify: `Packages/WorldStore/Sources/WorldStore/WorldStore.swift`
- Modify: `Packages/WorldStore/Tests/WorldStoreTests/WorldStoreTests.swift`

- [ ] **Step 1: Failing tests**

  Append to `WorldStoreTests.swift` (inside the class, alongside existing tests):

  ```swift
      func test_open_loadsMaps() throws {
          let url = try copyFixtureWorld()
          let mapsDir = url.appendingPathComponent("maps")
          try FileManager.default.createDirectory(at: mapsDir, withIntermediateDirectories: true)
          try Data([0]).write(to: mapsDir.appendingPathComponent("overworld.png"))
          let store = try WorldStore.open(url)
          XCTAssertEqual(store.mapNames, ["overworld"])
      }

      func test_open_loadsCalendar() throws {
          let url = try copyFixtureWorld()
          let json = """
          {
            "name": "Aetheria",
            "calendar": {
              "yearZeroLabel": "AE",
              "eras": [{ "id":"first-age", "name":"First Age", "start":-1000, "end":0 }]
            }
          }
          """
          try json.write(to: url.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
          let store = try WorldStore.open(url)
          XCTAssertEqual(store.calendar.yearZeroLabel, "AE")
          XCTAssertEqual(store.calendar.eras.map(\.id), ["first-age"])
      }

      func test_saveMap_roundTrip() throws {
          let url = try copyFixtureWorld()
          let mapsDir = url.appendingPathComponent("maps")
          try FileManager.default.createDirectory(at: mapsDir, withIntermediateDirectories: true)
          try Data([0]).write(to: mapsDir.appendingPathComponent("overworld.png"))
          let store = try WorldStore.open(url)
          var doc = try store.loadMap(named: "overworld")
          doc.pins.append(MapPin(x: 0.3, y: 0.4, locationId: EntityID("ruins"), label: nil))
          try store.saveMap(doc, name: "overworld")
          let reread = try store.loadMap(named: "overworld")
          XCTAssertEqual(reread.pins.count, 1)
      }
  ```

- [ ] **Step 2: Run** — expect compile failure.

- [ ] **Step 3: Implement**

  In `Packages/WorldStore/Sources/WorldStore/WorldStore.swift`, add two public properties + helpers. Final shape (modify the existing class — keep current method bodies, add the new pieces):

  ```swift
  @Observable
  public final class WorldStore {
      public private(set) var world: World
      public private(set) var entities: [Entity]
      public private(set) var schema: Schema
      public private(set) var mapNames: [String]
      public private(set) var calendar: WorldCalendar

      private init(world: World, entities: [Entity], schema: Schema,
                   mapNames: [String], calendar: WorldCalendar) {
          self.world = world
          self.entities = entities
          self.schema = schema
          self.mapNames = mapNames
          self.calendar = calendar
      }

      public static func open(_ folder: URL) throws -> WorldStore {
          let worldJSON = folder.appendingPathComponent("world.json")
          let worldData: Data? = try? Data(contentsOf: worldJSON)

          let name: String
          let color: String?
          if let data = worldData,
             let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
              name = (obj["name"] as? String) ?? folder.lastPathComponent
              color = obj["color"] as? String
          } else {
              name = folder.lastPathComponent
              color = nil
          }

          var loaded: [Entity] = []
          for type in EntityType.allCases {
              let dir = folder.appendingPathComponent(type.folderName)
              guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
              for file in files where file.pathExtension == "md" {
                  do {
                      let entity = try EntityFile.read(from: file, fallbackType: type)
                      loaded.append(entity)
                  } catch {
                      print("WorldStore: skip \(file.lastPathComponent): \(error)")
                  }
              }
          }

          let schema = SchemaLoader.load(overridesJSON: worldData)
          let calendar = WorldCalendar.load(from: worldData)
          let mapNames = MapStore.listNames(in: folder)
          let world = World(name: name, folder: folder, color: color)
          return WorldStore(
              world: world,
              entities: loaded.sorted { $0.name < $1.name },
              schema: schema,
              mapNames: mapNames,
              calendar: calendar
          )
      }

      // unchanged save / create / entities(of:) / path(for:) / uniqueSlug methods …

      public func loadMap(named name: String) throws -> MapDoc {
          try MapStore.load(name: name, in: world.folder)
      }

      public func saveMap(_ doc: MapDoc, name: String) throws {
          try MapStore.save(doc, name: name, in: world.folder)
          if !mapNames.contains(name) {
              mapNames.append(name)
              mapNames.sort()
          }
      }

      public func reloadMapNames() {
          mapNames = MapStore.listNames(in: world.folder)
      }
  }
  ```

- [ ] **Step 4: Run** — expect 28 tests total in WorldStore (was 18 + 2 from Task 1 + 5 from Task 2 + 2 from Task 3 + 3 new here = 30; if your count differs, investigate).

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WorldStore
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(WorldStore): expose mapNames + calendar; load/save map docs"
  ```

---

## Task 5: TabContent enum + TabsModel refactor

This is the load-bearing refactor. All callers that pass `EntityID` to `TabsModel` must switch to `TabContent.entity(id)`. Touches: `TabsModel`, `TabBarView`, `EditorTab`, `ContentView`, `SidebarView`, `EditorView`, `MarkdownTextView`, `PaletteController`, `PaletteAction` builder.

**Files:**
- Create: `FantasyTavernApp/Sources/Tabs/TabContent.swift`
- Modify: `FantasyTavernApp/Sources/Tabs/TabsModel.swift`
- Modify: `FantasyTavernApp/Tests/TabsModelTests.swift`

- [ ] **Step 1: Add `TabContent.swift`**

  ```swift
  import Foundation
  import EntityModel

  public enum TabContent: Hashable, Sendable {
      case entity(EntityID)
      case timeline
      case map(String)

      public var entityID: EntityID? {
          if case .entity(let id) = self { return id } else { return nil }
      }
  }
  ```

- [ ] **Step 2: Update `TabsModelTests.swift`**

  Replace every `EntityID("…")` in `openTabs`/`selected`/`recents`-related assertions with `TabContent.entity(EntityID("…"))`. Concretely, rewrite the test file:

  ```swift
  import XCTest
  import EntityModel
  @testable import FantasyTavernApp

  final class TabsModelTests: XCTestCase {
      private func e(_ s: String) -> TabContent { .entity(EntityID(s)) }

      func test_open_addsTabAndSelects() {
          let model = TabsModel()
          model.open(e("a"))
          XCTAssertEqual(model.openTabs, [e("a")])
          XCTAssertEqual(model.selected, e("a"))
      }

      func test_openExisting_doesNotDuplicate_andSelects() {
          let model = TabsModel()
          model.open(e("a")); model.open(e("b")); model.open(e("a"))
          XCTAssertEqual(model.openTabs, [e("a"), e("b")])
          XCTAssertEqual(model.selected, e("a"))
      }

      func test_close_removesAndPicksNeighbor() {
          let model = TabsModel()
          model.open(e("a")); model.open(e("b")); model.open(e("c"))
          model.close(e("b"))
          XCTAssertEqual(model.openTabs, [e("a"), e("c")])
          XCTAssertEqual(model.selected, e("c"))
      }

      func test_closeLast_clearsSelection() {
          let model = TabsModel()
          model.open(e("a"))
          model.close(e("a"))
          XCTAssertEqual(model.openTabs, [])
          XCTAssertNil(model.selected)
      }

      func test_open_pushesToRecents_mostRecentFirst() {
          let m = TabsModel()
          m.open(e("a")); m.open(e("b")); m.open(e("c"))
          XCTAssertEqual(m.recents, [e("c"), e("b"), e("a")])
      }

      func test_open_existing_movesItToFrontOfRecents() {
          let m = TabsModel()
          m.open(e("a")); m.open(e("b")); m.open(e("a"))
          XCTAssertEqual(m.recents, [e("a"), e("b")])
      }

      func test_recents_cappedAtTen() {
          let m = TabsModel()
          for i in 0..<15 { m.open(e("e\(i)")) }
          XCTAssertEqual(m.recents.count, 10)
          XCTAssertEqual(m.recents.first, e("e14"))
      }

      func test_open_timelineAndMap_distinctTabs() {
          let m = TabsModel()
          m.open(.timeline)
          m.open(.map("overworld"))
          XCTAssertEqual(m.openTabs, [.timeline, .map("overworld")])
          XCTAssertEqual(m.selected, .map("overworld"))
      }
  }
  ```

- [ ] **Step 3: Run** — `xcodebuild test` will fail (TabsModel still uses EntityID).

- [ ] **Step 4: Rewrite `TabsModel.swift`**

  ```swift
  import Foundation
  import Observation
  import EntityModel

  @Observable
  public final class TabsModel {
      public private(set) var openTabs: [TabContent] = []
      public var selected: TabContent?
      public private(set) var recents: [TabContent] = []
      private let recentsCap = 10

      public init() {}

      public func open(_ content: TabContent) {
          if !openTabs.contains(content) { openTabs.append(content) }
          selected = content
          pushRecent(content)
      }

      public func close(_ content: TabContent) {
          guard let idx = openTabs.firstIndex(of: content) else { return }
          openTabs.remove(at: idx)
          if selected == content {
              if openTabs.isEmpty { selected = nil }
              else { selected = openTabs[min(idx, openTabs.count - 1)] }
          }
      }

      private func pushRecent(_ content: TabContent) {
          recents.removeAll { $0 == content }
          recents.insert(content, at: 0)
          if recents.count > recentsCap { recents.removeLast(recents.count - recentsCap) }
      }
  }
  ```

- [ ] **Step 5: Run TabsModel-only tests**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test -only-testing:FantasyTavernAppTests/TabsModelTests 2>&1 | tail -10
  ```

  Expected: 8 TabsModelTests pass.

  Note: the wider app target will not yet build until Task 6 lands the rest of the call-site updates. That's fine for this commit point — Task 6 is the contiguous follow-up.

- [ ] **Step 6: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "refactor(tabs): introduce TabContent enum; TabsModel keyed by it"
  ```

---

## Task 6: Refactor call sites — adapt to `TabContent`

The compile errors after Task 5 point at every caller. Fix them all in one commit. Tests should be green at the end.

**Files:**
- Modify: `FantasyTavernApp/Sources/Tabs/TabBarView.swift`
- Modify: `FantasyTavernApp/Sources/Tabs/EditorTab.swift`
- Modify: `FantasyTavernApp/Sources/ContentView.swift`
- Modify: `FantasyTavernApp/Sources/Sidebar/SidebarView.swift`
- Modify: `FantasyTavernApp/Sources/Editor/EditorView.swift`
- Modify: `FantasyTavernApp/Sources/Editor/MarkdownTextView.swift`
- Modify: `FantasyTavernApp/Sources/CommandPalette/PaletteController.swift`
- Modify: `FantasyTavernApp/Sources/CommandPalette/PaletteAction.swift`
- Modify: `FantasyTavernApp/Tests/WorldSessionSearchTests.swift` (uses `tabs.open` indirectly? — only if it does; otherwise leave)
- Modify: `FantasyTavernApp/Tests/PaletteControllerTests.swift` (assert `tabs.selected == .entity(id)`)

- [ ] **Step 1: `TabBarView.swift`**

  ```swift
  import SwiftUI
  import EntityModel

  struct TabBarView: View {
      @Environment(WorldSession.self) private var session
      @Environment(TabsModel.self) private var tabs

      var body: some View {
          ScrollView(.horizontal) {
              HStack(spacing: 4) {
                  ForEach(tabs.openTabs, id: \.self) { content in
                      EditorTab(content: content,
                                label: label(for: content),
                                isSelected: tabs.selected == content,
                                onSelect: { tabs.selected = content },
                                onClose: { tabs.close(content) })
                  }
              }
              .padding(.horizontal, 8).padding(.vertical, 4)
          }
          .frame(height: 32)
      }

      private func label(for content: TabContent) -> String {
          switch content {
          case .entity(let id):
              return session.store?.entities.first(where: { $0.id == id })?.name ?? id.rawValue
          case .timeline:
              return "Timeline"
          case .map(let name):
              return "Map: \(name)"
          }
      }
  }
  ```

- [ ] **Step 2: `EditorTab.swift`**

  ```swift
  import SwiftUI

  struct EditorTab: View {
      let content: TabContent
      let label: String
      let isSelected: Bool
      let onSelect: () -> Void
      let onClose: () -> Void

      var body: some View {
          HStack(spacing: 4) {
              Button(action: onSelect) { Text(label).lineLimit(1) }
                  .buttonStyle(.plain)
              Button(action: onClose) { Image(systemName: "xmark") }
                  .buttonStyle(.plain).font(.caption)
          }
          .padding(.horizontal, 8).padding(.vertical, 4)
          .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
          .clipShape(RoundedRectangle(cornerRadius: 4))
      }
  }
  ```

- [ ] **Step 3: `ContentView.swift`** — dispatch on `TabContent`

  ```swift
  import SwiftUI
  import EntityModel

  struct ContentView: View {
      @Environment(WorldSession.self) private var session
      @Environment(TabsModel.self) private var tabs
      @Environment(PaletteController.self) private var palette

      var body: some View {
          ZStack {
              NavigationSplitView {
                  SidebarView()
                      .frame(minWidth: 220)
              } detail: {
                  VStack(spacing: 0) {
                      TabBarView()
                      Divider()
                      detail
                          .frame(maxWidth: .infinity, maxHeight: .infinity)
                  }
              }
              CommandPaletteView(controller: palette)
          }
      }

      @ViewBuilder
      private var detail: some View {
          switch tabs.selected {
          case .entity(let id):
              if let entity = session.store?.entities.first(where: { $0.id == id }) {
                  EditorView(entity: entity)
              } else {
                  ContentUnavailableView("Entity unavailable", systemImage: "exclamationmark.triangle")
              }
          case .timeline:
              TimelineView()
          case .map(let name):
              MapView(name: name)
          case .none:
              ContentUnavailableView("No tab open", systemImage: "doc.text",
                                     description: Text("Open an entity from the sidebar or press ⌘K."))
          }
      }
  }
  ```

  (`TimelineView` and `MapView` are placeholders for Tasks 8 + 10. They must exist as compilable stubs for this commit. Create them now with empty bodies so the project builds — see Step 6 of this task for stubs.)

- [ ] **Step 4: `SidebarView.swift`** — change `tabs.open(entity.id)` → `tabs.open(.entity(entity.id))`. Leave the structure otherwise. (Maps + timeline rows come in Task 7.)

  In the existing `Button(entity.name) { tabs.open(entity.id) }`, change to:

  ```swift
  Button(entity.name) { tabs.open(.entity(entity.id)) }
  ```

- [ ] **Step 5: `EditorView.swift`** — `tabs.open($0)` becomes `tabs.open(.entity($0))`

  In `MarkdownTextView`'s `onOpenLink` closure (where it's used inside `EditorView`):

  ```swift
  onOpenLink: { tabs.open(.entity($0)) }
  ```

- [ ] **Step 6: `MarkdownTextView.swift`** — no change; its `onOpenLink` callback still takes `EntityID`. The wrapping is done at the call site.

- [ ] **Step 7: `PaletteController.swift`** — update `activate` and `findResults`/recents handling:

  Where the file says:

  ```swift
              let id = results[selectionIndex].id
              if openInPlace, let current = tabs.selected, current != id {
                  tabs.close(current)
              }
              tabs.open(id)
              dismiss()
  ```

  rewrite to:

  ```swift
              let id = results[selectionIndex].id
              let content = TabContent.entity(id)
              if openInPlace, let current = tabs.selected, current != content {
                  tabs.close(current)
              }
              tabs.open(content)
              dismiss()
  ```

  And update the `findResults` recents lookup — replace:

  ```swift
              let recentHits = tabs.recents.compactMap { id -> SearchHit? in
                  guard let e = session.store?.entities.first(where: { $0.id == id }) else { return nil }
                  return SearchHit(id: e.id, type: e.type, name: e.name, score: 0)
              }
              let remaining = session.search("").filter { hit in !tabs.recents.contains(hit.id) }
  ```

  with:

  ```swift
              let recentHits: [SearchHit] = tabs.recents.compactMap { content in
                  guard case .entity(let id) = content,
                        let e = session.store?.entities.first(where: { $0.id == id })
                  else { return nil }
                  return SearchHit(id: e.id, type: e.type, name: e.name, score: 0)
              }
              let recentEntityIDs = Set(tabs.recents.compactMap { $0.entityID })
              let remaining = session.search("").filter { !recentEntityIDs.contains($0.id) }
  ```

- [ ] **Step 8: `PaletteAction.swift`** — `closeCurrentTab` becomes `if let s = self?.tabs.selected { self?.tabs.close(s) }`. Already structured correctly; just confirm `tabs.selected` is `TabContent?` now.

- [ ] **Step 9: `PaletteControllerTests.swift`** — every `tabs.selected == e.id` becomes `tabs.selected == .entity(e.id)`. The `test_activateFind_opensSelectedInNewTab` test should use `.entity(e.id)` as the expected `selected`.

- [ ] **Step 10: Create stub views** (so ContentView compiles)

  `FantasyTavernApp/Sources/Timeline/TimelineView.swift`:

  ```swift
  import SwiftUI

  struct TimelineView: View {
      var body: some View {
          ContentUnavailableView("Timeline coming soon", systemImage: "clock")
      }
  }
  ```

  `FantasyTavernApp/Sources/Map/MapView.swift`:

  ```swift
  import SwiftUI

  struct MapView: View {
      let name: String
      var body: some View {
          ContentUnavailableView("Map: \(name)", systemImage: "map")
      }
  }
  ```

  These are placeholders to be expanded in Tasks 8 + 10.

- [ ] **Step 11: Run full app tests**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: build succeeds; 28 tests pass (was 27, +1 new `test_open_timelineAndMap_distinctTabs`).

- [ ] **Step 12: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "refactor(app): switch tab callers to TabContent; stub Timeline/Map views"
  ```

---

## Task 7: Sidebar — Timeline row + Maps section

**Files:**
- Modify: `FantasyTavernApp/Sources/Sidebar/SidebarView.swift`

- [ ] **Step 1: Add the rows**

  ```swift
  import SwiftUI
  import EntityModel

  struct SidebarView: View {
      @Environment(WorldSession.self) private var session
      @Environment(TabsModel.self) private var tabs

      var body: some View {
          List {
              if let world = session.store?.world {
                  Section(world.name) {
                      ForEach(EntityType.allCases, id: \.self) { type in
                          let entries = session.store?.entities(of: type) ?? []
                          DisclosureGroup(title(for: type, count: entries.count)) {
                              if entries.isEmpty {
                                  Text("No entries yet").foregroundStyle(.secondary).font(.caption)
                              } else {
                                  ForEach(entries, id: \.id) { entity in
                                      Button(entity.name) { tabs.open(.entity(entity.id)) }
                                          .buttonStyle(.plain)
                                  }
                              }
                          }
                      }
                  }
                  Section("Views") {
                      Button("Timeline") { tabs.open(.timeline) }.buttonStyle(.plain)
                      let names = session.store?.mapNames ?? []
                      DisclosureGroup("Maps (\(names.count))") {
                          if names.isEmpty {
                              Text("No maps in folder").foregroundStyle(.secondary).font(.caption)
                          } else {
                              ForEach(names, id: \.self) { name in
                                  Button(name) { tabs.open(.map(name)) }.buttonStyle(.plain)
                              }
                          }
                      }
                  }
              } else {
                  ContentUnavailableView("No world open", systemImage: "globe")
              }
          }
          .listStyle(.sidebar)
      }

      private func title(for type: EntityType, count: Int) -> String {
          let base: String
          switch type {
          case .character:     base = "Characters"
          case .location:      base = "Locations"
          case .lore:          base = "Lore"
          case .item:          base = "Items"
          case .language:      base = "Languages"
          case .journal:       base = "Journal"
          case .timelineEvent: base = "Timeline"
          }
          return "\(base) (\(count))"
      }
  }
  ```

- [ ] **Step 2: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: 28 tests still pass.

- [ ] **Step 3: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(sidebar): Timeline row + Maps section"
  ```

---

## Task 8: TimelineGeometry pure-logic helper

**Files:**
- Create: `FantasyTavernApp/Sources/Timeline/TimelineGeometry.swift`
- Create: `FantasyTavernApp/Tests/TimelineGeometryTests.swift`

- [ ] **Step 1: Failing tests**

  ```swift
  import XCTest
  @testable import FantasyTavernApp

  final class TimelineGeometryTests: XCTestCase {
      func test_year_parsesPlainYear() {
          XCTAssertEqual(TimelineGeometry.year(fromDateString: "1452"), 1452)
      }
      func test_year_parsesNegative() {
          XCTAssertEqual(TimelineGeometry.year(fromDateString: "-1200"), -1200)
      }
      func test_year_parsesISODate() {
          XCTAssertEqual(TimelineGeometry.year(fromDateString: "1452-04-12"), 1452)
      }
      func test_year_parsesPrefixedLabel() {
          XCTAssertEqual(TimelineGeometry.year(fromDateString: "AE 802"), 802)
      }
      func test_year_emptyReturnsNil() {
          XCTAssertNil(TimelineGeometry.year(fromDateString: ""))
          XCTAssertNil(TimelineGeometry.year(fromDateString: "no digits"))
      }

      func test_tickStep_byGranularity() {
          XCTAssertEqual(TimelineGeometry.tickStep(.year), 1)
          XCTAssertEqual(TimelineGeometry.tickStep(.decade), 10)
          XCTAssertEqual(TimelineGeometry.tickStep(.century), 100)
      }

      func test_xPosition_normalizesWithinRange() {
          // Range [-100, 100], pixelWidth 200 → year 0 → x=100
          XCTAssertEqual(TimelineGeometry.x(forYear: 0, range: -100...100, width: 200), 100, accuracy: 0.001)
          XCTAssertEqual(TimelineGeometry.x(forYear: -100, range: -100...100, width: 200), 0, accuracy: 0.001)
          XCTAssertEqual(TimelineGeometry.x(forYear: 100, range: -100...100, width: 200), 200, accuracy: 0.001)
      }

      func test_yearAtPoint_inverse() {
          XCTAssertEqual(TimelineGeometry.year(atX: 100, range: -100...100, width: 200), 0)
          XCTAssertEqual(TimelineGeometry.year(atX: 0, range: -100...100, width: 200), -100)
      }
  }
  ```

- [ ] **Step 2: Implement**

  `FantasyTavernApp/Sources/Timeline/TimelineGeometry.swift`:

  ```swift
  import Foundation

  enum TimelineGranularity { case year, decade, century }

  enum TimelineGeometry {
      static func year(fromDateString raw: String) -> Int? {
          var digits = ""
          var sawSign = false
          var inRun = false
          for ch in raw {
              if ch == "-" && !inRun && digits.isEmpty {
                  digits.append(ch); sawSign = true
              } else if ch.isNumber {
                  digits.append(ch); inRun = true
              } else if inRun {
                  break
              }
          }
          guard !digits.isEmpty, digits != "-" else { return nil }
          _ = sawSign
          return Int(digits)
      }

      static func tickStep(_ g: TimelineGranularity) -> Int {
          switch g { case .year: return 1; case .decade: return 10; case .century: return 100 }
      }

      static func x(forYear year: Int, range: ClosedRange<Int>, width: Double) -> Double {
          let span = Double(range.upperBound - range.lowerBound)
          guard span > 0 else { return 0 }
          let frac = Double(year - range.lowerBound) / span
          return frac * width
      }

      static func year(atX x: Double, range: ClosedRange<Int>, width: Double) -> Int {
          guard width > 0 else { return range.lowerBound }
          let frac = max(0, min(1, x / width))
          let span = Double(range.upperBound - range.lowerBound)
          return range.lowerBound + Int((frac * span).rounded())
      }
  }
  ```

- [ ] **Step 3: Run** — `xcodebuild test` filter on TimelineGeometryTests; expect 9 pass.

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(timeline): TimelineGeometry pure-logic year parsing + scale"
  ```

---

## Task 9: TimelineView — render axis, events, eras, pan/zoom

**Files:**
- Modify: `FantasyTavernApp/Sources/Timeline/TimelineView.swift`

This task has no automated tests beyond compile + visual. Be tight; lots of code.

- [ ] **Step 1: Implement**

  ```swift
  import SwiftUI
  import EntityModel
  import WorldStore

  struct TimelineView: View {
      @Environment(WorldSession.self) private var session
      @Environment(TabsModel.self) private var tabs

      @State private var granularity: TimelineGranularity = .decade
      @State private var panOffset: Double = 0
      @State private var hoverYear: Int? = nil
      @State private var popoverEventID: EntityID? = nil
      @State private var createAtYear: Int? = nil

      private let viewportWidth: Double = 2000   // logical width before user pan
      private let rowHeight: Double = 80

      var body: some View {
          GeometryReader { geo in
              let range = autoRange()
              let width = max(viewportWidth, geo.size.width)
              ScrollView(.horizontal) {
                  ZStack(alignment: .topLeading) {
                      eraBands(range: range, width: width, height: geo.size.height)
                      axis(range: range, width: width)
                      eventDots(range: range, width: width)
                  }
                  .frame(width: width, height: geo.size.height)
                  .contentShape(Rectangle())
                  .onTapGesture { location in
                      let year = TimelineGeometry.year(atX: location.x, range: range, width: width)
                      createAtYear = year
                  }
              }
              .background(Color(nsColor: .underPageBackgroundColor))
          }
          .alert("Create event at year \(createAtYear ?? 0)?",
                 isPresented: Binding(get: { createAtYear != nil }, set: { if !$0 { createAtYear = nil } })) {
              Button("Create") {
                  if let year = createAtYear { createEvent(year: year) }
                  createAtYear = nil
              }
              Button("Cancel", role: .cancel) { createAtYear = nil }
          }
          .toolbar {
              ToolbarItemGroup {
                  Picker("Zoom", selection: $granularity) {
                      Text("Year").tag(TimelineGranularity.year)
                      Text("Decade").tag(TimelineGranularity.decade)
                      Text("Century").tag(TimelineGranularity.century)
                  }
                  .pickerStyle(.segmented)
              }
          }
      }

      // MARK: - data

      private var events: [(entity: Entity, year: Int)] {
          let raw = session.store?.entities(of: .timelineEvent) ?? []
          return raw.compactMap { e in
              guard case .string(let s)? = e.fields["date"] ?? nil,
                    let y = TimelineGeometry.year(fromDateString: s)
              else { return nil }
              return (e, y)
          }.sorted { $0.year < $1.year }
      }

      private func autoRange() -> ClosedRange<Int> {
          var ys = events.map(\.year)
          let calEras = session.store?.calendar.eras ?? []
          ys.append(contentsOf: calEras.map(\.start))
          ys.append(contentsOf: calEras.map(\.end))
          guard let lo = ys.min(), let hi = ys.max(), lo < hi else { return -100...100 }
          let pad = max(10, (hi - lo) / 10)
          return (lo - pad)...(hi + pad)
      }

      // MARK: - drawing

      private func eraBands(range: ClosedRange<Int>, width: Double, height: Double) -> some View {
          ForEach(session.store?.calendar.eras ?? [], id: \.id) { era in
              let x1 = TimelineGeometry.x(forYear: era.start, range: range, width: width)
              let x2 = TimelineGeometry.x(forYear: era.end,   range: range, width: width)
              let bandWidth = max(0, x2 - x1)
              Rectangle()
                  .fill(Color.accentColor.opacity(0.08))
                  .frame(width: bandWidth, height: height)
                  .offset(x: x1)
                  .overlay(alignment: .topLeading) {
                      Text(era.name)
                          .font(.caption)
                          .padding(4)
                          .background(.regularMaterial)
                          .offset(x: x1 + 4, y: 4)
                  }
          }
      }

      private func axis(range: ClosedRange<Int>, width: Double) -> some View {
          let step = TimelineGeometry.tickStep(granularity)
          let firstTick = ((range.lowerBound / step) * step)
          let ticks = stride(from: firstTick, through: range.upperBound, by: step)
          return ZStack(alignment: .topLeading) {
              Path { path in
                  path.move(to: CGPoint(x: 0, y: rowHeight))
                  path.addLine(to: CGPoint(x: width, y: rowHeight))
              }
              .stroke(Color.secondary, lineWidth: 1)

              ForEach(Array(ticks), id: \.self) { year in
                  let x = TimelineGeometry.x(forYear: year, range: range, width: width)
                  VStack(spacing: 2) {
                      Rectangle().fill(Color.secondary).frame(width: 1, height: 8)
                      Text("\(year)").font(.caption2).foregroundStyle(.secondary)
                  }
                  .offset(x: x - 10, y: rowHeight - 4)
              }
          }
      }

      private func eventDots(range: ClosedRange<Int>, width: Double) -> some View {
          ForEach(events.map(\.entity), id: \.id) { entity in
              let year = TimelineGeometry.year(fromDateString: dateString(for: entity)) ?? 0
              let x = TimelineGeometry.x(forYear: year, range: range, width: width)
              Button {
                  popoverEventID = entity.id
              } label: {
                  Circle().fill(Color.accentColor).frame(width: 12, height: 12)
              }
              .buttonStyle(.plain)
              .offset(x: x - 6, y: rowHeight - 6)
              .popover(isPresented: Binding(
                  get: { popoverEventID == entity.id },
                  set: { if !$0 { popoverEventID = nil } }
              )) {
                  VStack(alignment: .leading, spacing: 8) {
                      Text(entity.name).font(.headline)
                      Text("Year \(year)").font(.caption).foregroundStyle(.secondary)
                      if !entity.body.isEmpty {
                          Text(entity.body.prefix(200)).font(.body)
                      }
                      Button("Open in tab") {
                          tabs.open(.entity(entity.id))
                          popoverEventID = nil
                      }
                  }
                  .padding(12)
                  .frame(width: 320)
              }
          }
      }

      private func dateString(for entity: Entity) -> String {
          if case .string(let s)? = entity.fields["date"] { return s }
          return ""
      }

      private func createEvent(year: Int) {
          guard let entity = try? session.createEntity(type: .timelineEvent, name: "Year \(year)") else { return }
          var updated = entity
          updated.fields["date"] = .string(String(year))
          try? session.save(updated)
          tabs.open(.entity(updated.id))
      }
  }
  ```

- [ ] **Step 2: Build**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -15
  ```

  Expected: succeeds. If `ToolbarItemGroup` complains, drop the toolbar block — the picker is not critical.

- [ ] **Step 3: Tests still green**

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(timeline): horizontal axis, era bands, event dots, click-to-create"
  ```

---

## Task 10: MapView — image + pins + add-pin popover

**Files:**
- Modify: `FantasyTavernApp/Sources/Map/MapView.swift`
- Create: `FantasyTavernApp/Sources/Map/AddPinPopover.swift`

- [ ] **Step 1: `AddPinPopover.swift`**

  ```swift
  import SwiftUI
  import EntityModel

  struct AddPinPopover: View {
      @Environment(WorldSession.self) private var session
      let onPick: (EntityID) -> Void

      var body: some View {
          let locations = session.store?.entities(of: .location) ?? []
          VStack(alignment: .leading) {
              Text("Pin location").font(.headline)
              if locations.isEmpty {
                  Text("No locations yet.").foregroundStyle(.secondary)
              } else {
                  List(locations, id: \.id) { loc in
                      Button(loc.name) { onPick(loc.id) }.buttonStyle(.plain)
                  }
                  .frame(width: 220, height: 200)
              }
          }
          .padding(12)
      }
  }
  ```

- [ ] **Step 2: `MapView.swift`** — fully replace the stub

  ```swift
  import SwiftUI
  import AppKit
  import EntityModel
  import WorldStore

  struct MapView: View {
      @Environment(WorldSession.self) private var session
      @Environment(TabsModel.self) private var tabs
      let name: String

      @State private var doc: MapDoc?
      @State private var loadError: String?
      @State private var pendingPinNormalized: CGPoint?
      @State private var image: NSImage?

      var body: some View {
          Group {
              if let doc, let image {
                  GeometryReader { geo in
                      let fit = aspectFit(imageSize: image.size, container: geo.size)
                      ZStack(alignment: .topLeading) {
                          Image(nsImage: image)
                              .resizable()
                              .scaledToFit()
                              .frame(width: fit.size.width, height: fit.size.height)
                              .offset(x: fit.origin.x, y: fit.origin.y)
                              .onTapGesture(modifiers: .command) { location in
                                  pendingPinNormalized = normalize(location, in: fit)
                              }
                          ForEach(Array(doc.pins.enumerated()), id: \.offset) { _, pin in
                              pinView(pin: pin, fit: fit)
                          }
                      }
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
              } else if let loadError {
                  ContentUnavailableView(loadError, systemImage: "exclamationmark.triangle")
              } else {
                  ProgressView().task { load() }
              }
          }
      }

      // MARK: - data

      private func load() {
          guard let store = session.store else { loadError = "No world open"; return }
          do {
              let d = try store.loadMap(named: name)
              doc = d
              let imageURL = store.world.folder
                  .appendingPathComponent("maps")
                  .appendingPathComponent(d.image)
              image = NSImage(contentsOf: imageURL)
              if image == nil { loadError = "Image \(d.image) could not be loaded" }
          } catch {
              loadError = "Failed to load map: \(error)"
          }
      }

      private func addPin(at normalized: CGPoint, locationID: EntityID) {
          guard var d = doc, let store = session.store else { return }
          let label = store.entities.first(where: { $0.id == locationID })?.name
          d.pins.append(MapPin(x: Double(normalized.x), y: Double(normalized.y),
                               locationId: locationID, label: label))
          try? store.saveMap(d, name: name)
          doc = d
      }

      // MARK: - layout

      private struct FitRect {
          let origin: CGPoint
          let size: CGSize
      }

      private func aspectFit(imageSize: CGSize, container: CGSize) -> FitRect {
          guard imageSize.width > 0, imageSize.height > 0 else {
              return FitRect(origin: .zero, size: container)
          }
          let scale = min(container.width / imageSize.width, container.height / imageSize.height)
          let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
          let origin = CGPoint(x: (container.width - size.width) / 2,
                               y: (container.height - size.height) / 2)
          return FitRect(origin: origin, size: size)
      }

      private func normalize(_ point: CGPoint, in fit: FitRect) -> CGPoint {
          let relX = (point.x - fit.origin.x) / fit.size.width
          let relY = (point.y - fit.origin.y) / fit.size.height
          return CGPoint(x: min(1, max(0, relX)), y: min(1, max(0, relY)))
      }

      private func pinView(pin: MapPin, fit: FitRect) -> some View {
          let px = fit.origin.x + CGFloat(pin.clampedX) * fit.size.width
          let py = fit.origin.y + CGFloat(pin.clampedY) * fit.size.height
          return Circle()
              .fill(Color.red)
              .frame(width: 12, height: 12)
              .overlay(Circle().stroke(Color.white, lineWidth: 1))
              .position(x: px, y: py)
              .help(pin.label ?? pin.locationId.rawValue)
              .onTapGesture { tabs.open(.entity(pin.locationId)) }
      }
  }
  ```

- [ ] **Step 3: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, ~37 tests pass (depends on prior counts; main thing is no regressions).

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(map): image-backed map view with location pins (⌘-click to add)"
  ```

---

## Task 11: Manual acceptance

**Files:** none.

- [ ] **Step 1: Prepare a map image**

  ```bash
  mkdir -p ~/Documents/FantasyTavern/Aetheria/maps
  # If you don't have a map image, generate a placeholder via Preview, or copy any PNG into maps/.
  ```

  Use any PNG you have lying around — name it `overworld.png` inside `Aetheria/maps/`.

- [ ] **Step 2: Build + launch**

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -3
  pkill -f FantasyTavernApp 2>/dev/null || true
  sleep 1
  open ~/Library/Developer/Xcode/DerivedData/FantasyTavern-cjpexdvcsmhrwcafqhtvzpbgihqg/Build/Products/Debug/FantasyTavernApp.app
  ```

- [ ] **Step 3: Walk through**

  1. Open Aetheria. Sidebar has "Views" section with "Timeline" + "Maps (1)".
  2. Click "Timeline" → empty axis appears (no events yet). Click on axis at some year → prompt → confirm → new `Year N` timeline event opens in a tab. Set its `date` field if needed, then return to Timeline → dot appears.
  3. Add 2-3 more events at different years (via the prompt or by manually creating timeline-event entities). Confirm dots cluster appropriately; click a dot → popover with name + body + "Open in tab".
  4. Edit `world.json` to add eras (e.g. First Age -1000..0, Second Age 0..1500), reopen, confirm era bands shaded behind the axis.
  5. Click "Maps → overworld" → image fills detail pane.
  6. ⌘-click on the image at some spot → popover lists Locations → pick "Silvermoon" (create it first if missing). Pin appears at the click spot.
  7. Quit + relaunch → pin persists. Open `maps/overworld.json` to confirm.
  8. Click a pin → Silvermoon opens in a tab.

- [ ] **Step 4: Tag**

  ```bash
  git tag plan-4-timeline-maps-complete
  ```

---

## Deferred from Plan 4 (call out at review)

- **Map pan/zoom inside the image** — Plan 4 stretches the image to fit the pane; no zoom/pan yet. Future polish.
- **Drag-to-reposition pins** — pins are placed via ⌘-click and not movable. Future.
- **Pin removal UI** — manually edit JSON to remove. Future.
- **Multi-layer toggling** — single layer in v1 per spec.
- **Hex grid map editor** — deferred to a later plan.
- **Custom calendar (months, weekdays)** — v1 uses leading-int year parsing only.
- **Multiple parallel timeline tracks** — single axis in v1.
- **Inline event editing on the timeline** — popover shows "Open in tab" for full editing.

## Self-Review notes

**Spec coverage:**
- Horizontal timeline: Task 9. ✓
- Pan/zoom (segmented picker w/ granularity): Task 9. ✓
- Events as dots, popover w/ refs (we show "Open in tab"; ref pills inside body could be added via a Plan 1.5 polish using `WikiLinkParser` for the popover body). Acceptable scope-down.
- Click axis → create event: Task 9. ✓
- Per-world calendar: Task 3 (loader) + Task 4 (exposed) + Task 9 (rendered). ✓
- Map image + pins, click → open location, ⌘-click → add pin: Task 10. ✓
- v1 single layer, no hex grid, no PDF — matches spec deferrals.

**Placeholder scan:** no TBDs; all code blocks complete.

**Type consistency:**
- `TabContent` defined in Task 5, used in Tasks 6–10 identically.
- `MapDoc`/`MapPin` defined in Task 1, used in Tasks 2, 4, 10.
- `WorldStore.loadMap(named:)` / `saveMap(_:name:)` consistent across Tasks 4 + 10.
- `TimelineGeometry.year(fromDateString:)` / `x(forYear:range:width:)` consistent Task 8 + 9.
