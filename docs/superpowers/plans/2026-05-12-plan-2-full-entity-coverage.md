# FantasyTavern Plan 2 — Full Entity Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the foundation to support all seven entity types (locations, lore, items, languages, journal, timeline events — characters already work) with schema-driven custom fields and tags rendered in the inspector.

**Architecture:** Add a new pure-logic SPM package `SchemaRegistry` holding field-definition types and default per-type schemas. Generalize app-level "new entity" + sidebar + inspector to be schema-driven rather than character-specific. Honor `world.json.schemaOverrides` to let each world tweak fields.

**Tech Stack:** Same as Plan 1 — Swift 5.10+, macOS 14+, SwiftUI, SPM, XCTest, XcodeGen, Yams.

**Plan 2 success criteria:**
1. Sidebar shows seven type sections (Characters, Locations, Lore, Items, Languages, Journal, Timeline) under the open world, each with a count.
2. File menu has "New …" for each type, all open the created entity in a new tab.
3. Inspector shows: name (already there), schema-defined custom fields form, free-form tags editor, backlinks (already there).
4. Editing a custom field saves through the debounced editor pipeline.
5. Custom fields persist as `fields:` in front-matter (already partially supported by `FrontMatter`).
6. Default schema matches the design spec (character race/age/alignment/status; location kind/population/climate; item rarity/attunement; language family; journal date).
7. Per-world `world.json` may include `schemaOverrides` which replaces a given type's field list when present.

**Out of scope (later plans):**
- ⌘K palette / search (Plan 3).
- Horizontal timeline view, map view (Plan 4).
- Snapshots & restore UI, markdown export (Plan 5).
- FSEvents external-edit watcher (deferred — Plan 5).
- Hybrid inline markdown (`**bold**`, headings) — still deferred, may be a Plan 1.5 polish pass.

---

## File Structure

```
Packages/
  SchemaRegistry/                                 # NEW pure-logic package
    Package.swift
    Sources/SchemaRegistry/
      FieldDefinition.swift                       # FieldType enum, FieldDefinition struct
      Schema.swift                                # Schema = [String: [FieldDefinition]]
      DefaultSchemas.swift                        # bundled defaults per EntityType
      SchemaLoader.swift                          # merge world.json overrides into defaults
    Tests/SchemaRegistryTests/
      FieldDefinitionTests.swift
      DefaultSchemasTests.swift
      SchemaLoaderTests.swift

Packages/WorldStore/                              # MODIFY: expose schema-loader entry point
  Sources/WorldStore/WorldStore.swift             # add `schema: Schema` property; load on open
  (no new files)

FantasyTavernApp/Sources/
  WorldSession.swift                              # MODIFY: createEntity(type:name:), expose schema
  Commands/
    AppCommands.swift                             # MODIFY: replace "New Character" with all seven
  Sidebar/
    SidebarView.swift                             # MODIFY: iterate over EntityType.allCases
  Inspector/
    InspectorView.swift                           # MODIFY: render schema form + tags + backlinks
    FieldEditorView.swift                         # NEW: per-FieldType editor widget
    TagsEditorView.swift                          # NEW: comma-separated tags chip editor
FantasyTavernApp/Tests/
  WorldSessionEntityCoverageTests.swift           # NEW: createEntity(type:name:) for all types
  SchemaInspectorTests.swift                      # NEW: pure-logic helpers for inspector (no UI)
```

**Why this split:**
- `SchemaRegistry` is pure-logic, no UI / no I/O: easy to test, reusable, doesn't pollute `WorldStore`.
- `FieldEditorView` per field type keeps the inspector small. Easy to add new types (e.g. `ref`) later.
- Sidebar iterating over `EntityType.allCases` removes character-specific code. Generalizing now is cheap.

---

## Conventions (carry-over + additions)

(Same Plan 1 conventions for slug rule, atomic writes, ISO 8601 dates, commit messages, build/test commands.)

Plan 2 additions:
- **Schema lookup:** `world.schema(for: .character)` returns `[FieldDefinition]`. Empty array = no custom fields.
- **Override merge rule:** if `world.json.schemaOverrides[<typeRawValue>]` is present, it **replaces** the default array for that type entirely. Missing keys fall back to defaults. (Simple to reason about; per-field merge can come later if needed.)
- **Field display order:** preserved as written in the schema array.
- **Tags:** lowercased on save, deduped, trimmed. Display preserves input order. Empty tag list serializes as `tags: []`.

---

## Task 1: SchemaRegistry package scaffold + FieldDefinition types

**Files:**
- Create: `Packages/SchemaRegistry/Package.swift`
- Create: `Packages/SchemaRegistry/Sources/SchemaRegistry/FieldDefinition.swift`
- Create: `Packages/SchemaRegistry/Tests/SchemaRegistryTests/FieldDefinitionTests.swift`

- [ ] **Step 1: Scaffold the SPM package**

  ```bash
  mkdir -p Packages/SchemaRegistry/Sources/SchemaRegistry
  mkdir -p Packages/SchemaRegistry/Tests/SchemaRegistryTests
  ```

  Write `Packages/SchemaRegistry/Package.swift`:

  ```swift
  // swift-tools-version: 5.10
  import PackageDescription

  let package = Package(
      name: "SchemaRegistry",
      platforms: [.macOS(.v14)],
      products: [
          .library(name: "SchemaRegistry", targets: ["SchemaRegistry"]),
      ],
      dependencies: [
          .package(path: "../EntityModel"),
      ],
      targets: [
          .target(name: "SchemaRegistry", dependencies: ["EntityModel"]),
          .testTarget(name: "SchemaRegistryTests", dependencies: ["SchemaRegistry"]),
      ]
  )
  ```

- [ ] **Step 2: Write failing tests**

  `Packages/SchemaRegistry/Tests/SchemaRegistryTests/FieldDefinitionTests.swift`:

  ```swift
  import XCTest
  @testable import SchemaRegistry

  final class FieldDefinitionTests: XCTestCase {
      func test_stringField() {
          let f = FieldDefinition(key: "race", label: "Race", type: .string)
          XCTAssertEqual(f.key, "race")
          XCTAssertEqual(f.label, "Race")
          XCTAssertEqual(f.type, .string)
          XCTAssertNil(f.options)
      }

      func test_enumField_carriesOptions() {
          let f = FieldDefinition(key: "alignment", label: "Alignment", type: .enum, options: ["LG","NG","CG"])
          XCTAssertEqual(f.options, ["LG","NG","CG"])
      }

      func test_fieldType_codable_rawValues() throws {
          let types: [FieldType] = [.string, .int, .bool, .date, .enum, .ref]
          let encoded = try JSONEncoder().encode(types)
          let decoded = try JSONDecoder().decode([FieldType].self, from: encoded)
          XCTAssertEqual(types, decoded)
      }
  }
  ```

- [ ] **Step 3: Run to verify failure**

  ```bash
  swift test --package-path Packages/SchemaRegistry 2>&1 | tail -20
  ```

  Expected: compile failure (`FieldDefinition` / `FieldType` unknown).

- [ ] **Step 4: Implement**

  `Packages/SchemaRegistry/Sources/SchemaRegistry/FieldDefinition.swift`:

  ```swift
  import Foundation

  public enum FieldType: String, Codable, Equatable, Sendable, CaseIterable {
      case string
      case int
      case bool
      case date
      case `enum`
      case ref
  }

  public struct FieldDefinition: Equatable, Codable, Sendable {
      public let key: String
      public let label: String
      public let type: FieldType
      public let options: [String]?

      public init(key: String, label: String, type: FieldType, options: [String]? = nil) {
          self.key = key
          self.label = label
          self.type = type
          self.options = options
      }
  }
  ```

- [ ] **Step 5: Run tests**

  ```bash
  swift test --package-path Packages/SchemaRegistry 2>&1 | tail -10
  ```

  Expected: 3 tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add Packages/SchemaRegistry
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(SchemaRegistry): FieldDefinition + FieldType"
  ```

---

## Task 2: Schema type alias + default schemas

**Files:**
- Create: `Packages/SchemaRegistry/Sources/SchemaRegistry/Schema.swift`
- Create: `Packages/SchemaRegistry/Sources/SchemaRegistry/DefaultSchemas.swift`
- Create: `Packages/SchemaRegistry/Tests/SchemaRegistryTests/DefaultSchemasTests.swift`

- [ ] **Step 1: Write failing tests**

  `Packages/SchemaRegistry/Tests/SchemaRegistryTests/DefaultSchemasTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import SchemaRegistry

  final class DefaultSchemasTests: XCTestCase {
      func test_character_hasRaceAgeAlignmentStatus() {
          let fields = DefaultSchemas.fields(for: .character)
          XCTAssertEqual(fields.map(\.key), ["race", "age", "alignment", "status"])
          XCTAssertEqual(fields.first(where: { $0.key == "alignment" })?.type, .enum)
          XCTAssertEqual(fields.first(where: { $0.key == "age" })?.type, .int)
      }

      func test_location_hasKindPopulationClimate() {
          let keys = DefaultSchemas.fields(for: .location).map(\.key)
          XCTAssertEqual(keys, ["kind", "population", "climate"])
      }

      func test_item_hasRarityAttunement() {
          let keys = DefaultSchemas.fields(for: .item).map(\.key)
          XCTAssertEqual(keys, ["rarity", "attunement"])
      }

      func test_lore_hasEmptySchema() {
          XCTAssertEqual(DefaultSchemas.fields(for: .lore), [])
      }

      func test_language_hasFamily() {
          XCTAssertEqual(DefaultSchemas.fields(for: .language).map(\.key), ["family"])
      }

      func test_journal_hasDate() {
          let f = DefaultSchemas.fields(for: .journal)
          XCTAssertEqual(f.map(\.key), ["date"])
          XCTAssertEqual(f.first?.type, .date)
      }

      func test_timelineEvent_hasDate() {
          XCTAssertEqual(DefaultSchemas.fields(for: .timelineEvent).map(\.key), ["date"])
      }

      func test_schema_aliasIsDictionary() {
          let schema: Schema = [:]
          XCTAssertEqual(schema.count, 0)
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  ```bash
  swift test --package-path Packages/SchemaRegistry --filter DefaultSchemasTests 2>&1 | tail -20
  ```

  Expected: compile failure (`DefaultSchemas` / `Schema` unknown).

- [ ] **Step 3: Implement `Schema`**

  `Packages/SchemaRegistry/Sources/SchemaRegistry/Schema.swift`:

  ```swift
  import Foundation
  import EntityModel

  /// A schema maps an entity type's raw value (e.g. "character") to its ordered field definitions.
  public typealias Schema = [String: [FieldDefinition]]

  public extension Schema {
      func fields(for type: EntityType) -> [FieldDefinition] {
          self[type.rawValue] ?? []
      }
  }
  ```

- [ ] **Step 4: Implement `DefaultSchemas`**

  `Packages/SchemaRegistry/Sources/SchemaRegistry/DefaultSchemas.swift`:

  ```swift
  import Foundation
  import EntityModel

  public enum DefaultSchemas {
      public static let schema: Schema = [
          EntityType.character.rawValue: [
              FieldDefinition(key: "race",      label: "Race",      type: .string),
              FieldDefinition(key: "age",       label: "Age",       type: .int),
              FieldDefinition(key: "alignment", label: "Alignment", type: .enum,
                              options: ["LG","NG","CG","LN","TN","CN","LE","NE","CE"]),
              FieldDefinition(key: "status",    label: "Status",    type: .enum,
                              options: ["alive","dead","unknown"]),
          ],
          EntityType.location.rawValue: [
              FieldDefinition(key: "kind",       label: "Kind",       type: .enum,
                              options: ["city","town","village","dungeon","region","landmark"]),
              FieldDefinition(key: "population", label: "Population", type: .int),
              FieldDefinition(key: "climate",    label: "Climate",    type: .string),
          ],
          EntityType.item.rawValue: [
              FieldDefinition(key: "rarity",     label: "Rarity",     type: .enum,
                              options: ["common","uncommon","rare","very-rare","legendary","artifact"]),
              FieldDefinition(key: "attunement", label: "Attunement", type: .bool),
          ],
          EntityType.lore.rawValue: [],
          EntityType.language.rawValue: [
              FieldDefinition(key: "family", label: "Family", type: .string),
          ],
          EntityType.journal.rawValue: [
              FieldDefinition(key: "date", label: "Date", type: .date),
          ],
          EntityType.timelineEvent.rawValue: [
              FieldDefinition(key: "date", label: "Date", type: .date),
          ],
      ]

      public static func fields(for type: EntityType) -> [FieldDefinition] {
          schema.fields(for: type)
      }
  }
  ```

- [ ] **Step 5: Run tests**

  ```bash
  swift test --package-path Packages/SchemaRegistry 2>&1 | tail -10
  ```

  Expected: 11 tests pass total (3 from Task 1 + 8 here).

- [ ] **Step 6: Commit**

  ```bash
  git add Packages/SchemaRegistry
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(SchemaRegistry): default schemas for all entity types"
  ```

---

## Task 3: SchemaLoader (merge world.json overrides)

**Files:**
- Create: `Packages/SchemaRegistry/Sources/SchemaRegistry/SchemaLoader.swift`
- Create: `Packages/SchemaRegistry/Tests/SchemaRegistryTests/SchemaLoaderTests.swift`

- [ ] **Step 1: Write failing tests**

  `Packages/SchemaRegistry/Tests/SchemaRegistryTests/SchemaLoaderTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import SchemaRegistry

  final class SchemaLoaderTests: XCTestCase {
      func test_emptyOverrides_returnsDefault() {
          let loaded = SchemaLoader.load(overridesJSON: nil)
          XCTAssertEqual(loaded.fields(for: .character).map(\.key),
                         DefaultSchemas.fields(for: .character).map(\.key))
      }

      func test_overrideReplacesTypeFieldsEntirely() throws {
          let json = """
          {
            "schemaOverrides": {
              "character": [
                { "key": "house", "label": "House", "type": "string" }
              ]
            }
          }
          """
          let data = json.data(using: .utf8)!
          let loaded = SchemaLoader.load(overridesJSON: data)
          XCTAssertEqual(loaded.fields(for: .character).map(\.key), ["house"])
          // Other types untouched
          XCTAssertEqual(loaded.fields(for: .location).map(\.key),
                         DefaultSchemas.fields(for: .location).map(\.key))
      }

      func test_overrideWithoutSchemaOverridesKey_returnsDefault() throws {
          let data = #"{"name":"Test"}"#.data(using: .utf8)!
          let loaded = SchemaLoader.load(overridesJSON: data)
          XCTAssertEqual(loaded.fields(for: .character).map(\.key),
                         DefaultSchemas.fields(for: .character).map(\.key))
      }

      func test_malformedJSON_returnsDefault() {
          let data = "not json".data(using: .utf8)!
          let loaded = SchemaLoader.load(overridesJSON: data)
          XCTAssertEqual(loaded, DefaultSchemas.schema)
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  ```bash
  swift test --package-path Packages/SchemaRegistry --filter SchemaLoaderTests 2>&1 | tail -20
  ```

  Expected: compile failure (`SchemaLoader` unknown).

- [ ] **Step 3: Implement**

  `Packages/SchemaRegistry/Sources/SchemaRegistry/SchemaLoader.swift`:

  ```swift
  import Foundation
  import EntityModel

  public enum SchemaLoader {
      private struct Envelope: Decodable {
          let schemaOverrides: [String: [FieldDefinition]]?
      }

      /// Load a Schema by merging defaults with overrides from a `world.json` document.
      /// Override rule: if a type key is present in `schemaOverrides`, it replaces the default
      /// field list for that type entirely. Missing keys fall back to defaults.
      public static func load(overridesJSON data: Data?) -> Schema {
          var result = DefaultSchemas.schema
          guard let data,
                let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                let overrides = envelope.schemaOverrides
          else { return result }
          for (key, defs) in overrides {
              result[key] = defs
          }
          return result
      }
  }
  ```

- [ ] **Step 4: Run tests**

  ```bash
  swift test --package-path Packages/SchemaRegistry 2>&1 | tail -10
  ```

  Expected: 15 tests pass total.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/SchemaRegistry
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(SchemaRegistry): SchemaLoader merges world.json overrides into defaults"
  ```

---

## Task 4: WorldStore exposes schema

**Files:**
- Modify: `Packages/WorldStore/Package.swift` (add SchemaRegistry dep)
- Modify: `Packages/WorldStore/Sources/WorldStore/WorldStore.swift` (load schema on open)
- Modify: `Packages/WorldStore/Tests/WorldStoreTests/WorldStoreTests.swift` (assert schema present)

- [ ] **Step 1: Add SchemaRegistry dep to Package.swift**

  Overwrite `Packages/WorldStore/Package.swift`:

  ```swift
  // swift-tools-version: 5.10
  import PackageDescription

  let package = Package(
      name: "WorldStore",
      platforms: [.macOS(.v14)],
      products: [
          .library(name: "WorldStore", targets: ["WorldStore"]),
      ],
      dependencies: [
          .package(path: "../EntityModel"),
          .package(path: "../SchemaRegistry"),
          .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.6"),
      ],
      targets: [
          .target(
              name: "WorldStore",
              dependencies: [
                  "EntityModel",
                  "SchemaRegistry",
                  .product(name: "Yams", package: "Yams"),
              ]
          ),
          .testTarget(
              name: "WorldStoreTests",
              dependencies: ["WorldStore"],
              resources: [.copy("Fixtures")]
          ),
      ]
  )
  ```

- [ ] **Step 2: Add failing test**

  Append to `Packages/WorldStore/Tests/WorldStoreTests/WorldStoreTests.swift`:

  ```swift
      func test_open_loadsSchemaWithDefaults() throws {
          let url = try copyFixtureWorld()
          let store = try WorldStore.open(url)
          XCTAssertEqual(store.schema.fields(for: .character).map(\.key),
                         ["race", "age", "alignment", "status"])
      }

      func test_open_appliesSchemaOverridesFromWorldJSON() throws {
          let url = try copyFixtureWorld()
          // Rewrite the fixture copy's world.json with an override
          let overrideJSON = """
          {
            "name": "Aetheria",
            "schemaOverrides": {
              "character": [
                { "key": "house", "label": "House", "type": "string" }
              ]
            }
          }
          """
          try overrideJSON.write(to: url.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
          let store = try WorldStore.open(url)
          XCTAssertEqual(store.schema.fields(for: .character).map(\.key), ["house"])
      }
  ```

  These tests need `import SchemaRegistry` at the top of the file — add it if not already present.

- [ ] **Step 3: Run to verify failure**

  ```bash
  swift test --package-path Packages/WorldStore --filter WorldStoreTests 2>&1 | tail -25
  ```

  Expected: compile failure (`store.schema` unknown).

- [ ] **Step 4: Wire schema into WorldStore**

  In `Packages/WorldStore/Sources/WorldStore/WorldStore.swift`:

  Add `import SchemaRegistry` after `import EntityModel`.

  Inside the `WorldStore` class, change `entities`/`world` properties so that schema is alongside:

  ```swift
  @Observable
  public final class WorldStore {
      public private(set) var world: World
      public private(set) var entities: [Entity]
      public private(set) var schema: Schema

      private init(world: World, entities: [Entity], schema: Schema) {
          self.world = world
          self.entities = entities
          self.schema = schema
      }
  ```

  Inside `open(_ folder: URL)`, capture the world.json data so it can be passed to `SchemaLoader.load`:

  ```swift
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
          let world = World(name: name, folder: folder, color: color)
          return WorldStore(world: world, entities: loaded.sorted { $0.name < $1.name }, schema: schema)
      }
  ```

- [ ] **Step 5: Run tests**

  ```bash
  swift test --package-path Packages/WorldStore 2>&1 | tail -10
  ```

  Expected: 18 tests pass total (16 prior + 2 new).

- [ ] **Step 6: Commit**

  ```bash
  git add Packages/WorldStore
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(WorldStore): expose Schema, honor world.json schemaOverrides"
  ```

---

## Task 5: project.yml — link SchemaRegistry into the app target

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add the package and dependency**

  Edit `project.yml`. Under `packages:`, append:

  ```yaml
    SchemaRegistry:
      path: Packages/SchemaRegistry
  ```

  Under `targets.FantasyTavernApp.dependencies:`, append:

  ```yaml
        - package: SchemaRegistry
  ```

- [ ] **Step 2: Regenerate + build**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  ```

  Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Confirm tests still green**

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: 9 prior app-target tests still pass.

- [ ] **Step 4: Commit**

  ```bash
  git add project.yml
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "chore(project): link SchemaRegistry into app target"
  ```

---

## Task 6: WorldSession — generic createEntity, expose schema

**Files:**
- Modify: `FantasyTavernApp/Sources/WorldSession.swift`
- Create: `FantasyTavernApp/Tests/WorldSessionEntityCoverageTests.swift`

- [ ] **Step 1: Write failing tests**

  `FantasyTavernApp/Tests/WorldSessionEntityCoverageTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  import WorldStore
  import SchemaRegistry
  @testable import FantasyTavernApp

  final class WorldSessionEntityCoverageTests: XCTestCase {
      private func makeTempWorld() throws -> URL {
          let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
          try #"{"name":"Test"}"#.write(to: url.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
          return url
      }

      func test_createEntity_supportsAllSevenTypes() throws {
          let session = WorldSession()
          try session.openWorld(at: makeTempWorld())
          for type in EntityType.allCases {
              let entity = try session.createEntity(type: type, name: "Untitled \(type.rawValue)")
              XCTAssertEqual(entity.type, type)
          }
          XCTAssertEqual(session.store?.entities.count, EntityType.allCases.count)
      }

      func test_session_exposesSchemaFromStore() throws {
          let session = WorldSession()
          try session.openWorld(at: makeTempWorld())
          XCTAssertEqual(session.fields(for: .character).map(\.key),
                         ["race", "age", "alignment", "status"])
      }

      func test_createCharacter_stillWorks_callsCreateEntity() throws {
          let session = WorldSession()
          try session.openWorld(at: makeTempWorld())
          let e = try session.createCharacter(name: "Lyra")
          XCTAssertEqual(e.type, .character)
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -20
  ```

  Expected: build failure (`createEntity` / `fields(for:)` unknown).

- [ ] **Step 3: Generalize `WorldSession`**

  Overwrite `FantasyTavernApp/Sources/WorldSession.swift`:

  ```swift
  import Foundation
  import Observation
  import EntityModel
  import WorldStore
  import WikiLinks
  import SchemaRegistry

  @Observable
  public final class WorldSession {
      public var store: WorldStore?
      public private(set) var backlinkIndex = BacklinkIndex(entities: [])

      public init() {}

      public func openWorld(at url: URL) throws {
          let store = try WorldStore.open(url)
          self.store = store
          rebuildLinks()
      }

      @discardableResult
      public func createEntity(type: EntityType, name: String) throws -> Entity {
          guard let store else { throw SessionError.noWorldOpen }
          let entity = try store.create(name: name, type: type)
          rebuildLinks()
          return entity
      }

      @discardableResult
      public func createCharacter(name: String) throws -> Entity {
          try createEntity(type: .character, name: name)
      }

      public func save(_ entity: Entity) throws {
          guard let store else { throw SessionError.noWorldOpen }
          try store.save(entity)
          rebuildLinks()
      }

      public func backlinks(to target: EntityID) -> [EntityID] {
          backlinkIndex.sources(linkingTo: target)
      }

      public func fields(for type: EntityType) -> [FieldDefinition] {
          store?.schema.fields(for: type) ?? []
      }

      private func rebuildLinks() {
          backlinkIndex = BacklinkIndex(entities: store?.entities ?? [])
      }

      public enum SessionError: Error { case noWorldOpen }
  }
  ```

- [ ] **Step 4: Run tests**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: 12 tests pass total (9 prior + 3 new).

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(app): WorldSession.createEntity + schema exposure"
  ```

---

## Task 7: AppCommands — New menu for all seven types

**Files:**
- Modify: `FantasyTavernApp/Sources/Commands/AppCommands.swift`

- [ ] **Step 1: Replace the `New Character` button with a per-type submenu**

  Overwrite `FantasyTavernApp/Sources/Commands/AppCommands.swift`:

  ```swift
  import SwiftUI
  import AppKit
  import EntityModel

  struct AppCommands: Commands {
      @Binding var session: WorldSession
      @Binding var tabs: TabsModel
      @Bindable var recents = RecentWorlds.shared

      var body: some Commands {
          CommandGroup(replacing: .newItem) {
              Button("Open World…") { openWorld() }
                  .keyboardShortcut("o", modifiers: [.command])
              Menu("Open Recent") {
                  if recents.urls.isEmpty {
                      Text("No Recent Worlds")
                  } else {
                      ForEach(recents.urls, id: \.self) { url in
                          Button(url.lastPathComponent) { tryOpen(url) }
                      }
                      Divider()
                      Button("Clear Menu") { recents.clear() }
                  }
              }
              Divider()
              Menu("New") {
                  ForEach(EntityType.allCases, id: \.self) { type in
                      Button(label(for: type)) { newEntity(type: type) }
                          .disabled(session.store == nil)
                  }
              }
              Button("New Character") { newEntity(type: .character) }
                  .keyboardShortcut("n", modifiers: [.command])
                  .disabled(session.store == nil)
          }
      }

      private func label(for type: EntityType) -> String {
          switch type {
          case .character:     return "Character"
          case .location:      return "Location"
          case .lore:          return "Lore Entry"
          case .item:          return "Item"
          case .language:      return "Language"
          case .journal:       return "Journal Entry"
          case .timelineEvent: return "Timeline Event"
          }
      }

      private func openWorld() {
          let panel = NSOpenPanel()
          panel.canChooseDirectories = true
          panel.canChooseFiles = false
          panel.allowsMultipleSelection = false
          if panel.runModal() == .OK, let url = panel.url {
              tryOpen(url)
          }
      }

      private func tryOpen(_ url: URL) {
          do {
              try session.openWorld(at: url)
              recents.add(url)
          } catch {
              NSSound.beep()
          }
      }

      private func newEntity(type: EntityType) {
          if let entity = try? session.createEntity(type: type, name: "Untitled \(label(for: type))") {
              tabs.open(entity.id)
          }
      }
  }
  ```

  Note: ⌘N still creates a Character (kept as the default for convenience). The submenu "New > X" covers all seven.

- [ ] **Step 2: Build**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  ```

  Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Tests still green**

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: 12 tests pass.

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(commands): New > submenu for all seven entity types"
  ```

---

## Task 8: SidebarView — all seven type sections

**Files:**
- Modify: `FantasyTavernApp/Sources/Sidebar/SidebarView.swift`

- [ ] **Step 1: Render all seven type groups, each with a count**

  Overwrite `FantasyTavernApp/Sources/Sidebar/SidebarView.swift`:

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
                                  Text("No entries yet")
                                      .foregroundStyle(.secondary)
                                      .font(.caption)
                              } else {
                                  ForEach(entries, id: \.id) { entity in
                                      Button(entity.name) { tabs.open(entity.id) }
                                          .buttonStyle(.plain)
                                  }
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

- [ ] **Step 2: Build + tests**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: build succeeds, 12 tests pass.

- [ ] **Step 3: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(sidebar): render all seven entity-type sections with counts"
  ```

---

## Task 9: FieldEditorView — per-type widget

**Files:**
- Create: `FantasyTavernApp/Sources/Inspector/FieldEditorView.swift`
- Create: `FantasyTavernApp/Tests/SchemaInspectorTests.swift`

This task ships the pure-logic helper used by the inspector. UI rendering is in Task 10.

- [ ] **Step 1: Write failing tests for the helper**

  `FantasyTavernApp/Tests/SchemaInspectorTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  import SchemaRegistry
  @testable import FantasyTavernApp

  final class SchemaInspectorTests: XCTestCase {
      func test_displayString_forValue() {
          XCTAssertEqual(FieldFormatter.display(.string("half-elf"), type: .string), "half-elf")
          XCTAssertEqual(FieldFormatter.display(.int(42),           type: .int),    "42")
          XCTAssertEqual(FieldFormatter.display(.bool(true),        type: .bool),   "true")
          XCTAssertEqual(FieldFormatter.display(nil,                type: .string), "")
      }

      func test_parseString_coercesToFieldValue() {
          XCTAssertEqual(FieldFormatter.parse("half-elf", as: .string), .string("half-elf"))
          XCTAssertEqual(FieldFormatter.parse("42",       as: .int),    .int(42))
          XCTAssertEqual(FieldFormatter.parse("true",     as: .bool),   .bool(true))
          XCTAssertEqual(FieldFormatter.parse("",         as: .string), nil) // empty clears
          XCTAssertEqual(FieldFormatter.parse("not-a-number", as: .int), nil)
      }

      func test_parseDate_iso8601() {
          let d = FieldFormatter.parse("2026-05-12T10:00:00Z", as: .date)
          if case .date(let date) = d {
              XCTAssertEqual(Int(date.timeIntervalSince1970), 1778587200) // 2026-05-12 10:00:00 UTC = 1778587200
          } else {
              XCTFail("expected .date")
          }
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -15
  ```

  Expected: build failure (`FieldFormatter` unknown).

- [ ] **Step 3: Implement `FieldFormatter` + `FieldEditorView`**

  `FantasyTavernApp/Sources/Inspector/FieldEditorView.swift`:

  ```swift
  import SwiftUI
  import EntityModel
  import SchemaRegistry

  /// Pure-logic helper that converts FieldValue <-> String for the inspector form.
  enum FieldFormatter {
      private static let iso: ISO8601DateFormatter = {
          let f = ISO8601DateFormatter()
          f.formatOptions = [.withInternetDateTime]
          return f
      }()

      static func display(_ value: FieldValue?, type: FieldType) -> String {
          guard let value else { return "" }
          switch (value, type) {
          case (.string(let s), .string), (.string(let s), .enum): return s
          case (.int(let i), .int):                                return String(i)
          case (.bool(let b), .bool):                              return String(b)
          case (.date(let d), .date):                              return iso.string(from: d)
          case (.ref(let id), .ref):                               return id.rawValue
          default: return ""
          }
      }

      static func parse(_ text: String, as type: FieldType) -> FieldValue? {
          let trimmed = text.trimmingCharacters(in: .whitespaces)
          if trimmed.isEmpty { return nil }
          switch type {
          case .string, .enum: return .string(trimmed)
          case .int:           return Int(trimmed).map(FieldValue.int)
          case .bool:          return Bool(trimmed).map(FieldValue.bool)
          case .date:          return iso.date(from: trimmed).map(FieldValue.date)
          case .ref:           return .ref(EntityID(trimmed))
          }
      }
  }

  /// SwiftUI widget for one field. Reads/writes the entity's `fields` dictionary by key.
  struct FieldEditorView: View {
      let definition: FieldDefinition
      @Binding var value: FieldValue?

      var body: some View {
          HStack(alignment: .firstTextBaseline) {
              Text(definition.label).frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
              switch definition.type {
              case .string:
                  TextField("", text: stringBinding).textFieldStyle(.roundedBorder)
              case .int:
                  TextField("", text: stringBinding).textFieldStyle(.roundedBorder)
              case .bool:
                  Toggle("", isOn: boolBinding).labelsHidden()
              case .date:
                  TextField("YYYY-MM-DDThh:mm:ssZ", text: stringBinding).textFieldStyle(.roundedBorder)
              case .enum:
                  Picker("", selection: stringBinding) {
                      Text("—").tag("")
                      ForEach(definition.options ?? [], id: \.self) { opt in
                          Text(opt).tag(opt)
                      }
                  }
                  .labelsHidden()
              case .ref:
                  TextField("entity id", text: stringBinding).textFieldStyle(.roundedBorder)
              }
          }
      }

      private var stringBinding: Binding<String> {
          Binding(
              get: { FieldFormatter.display(value, type: definition.type) },
              set: { value = FieldFormatter.parse($0, as: definition.type) }
          )
      }

      private var boolBinding: Binding<Bool> {
          Binding(
              get: {
                  if case .bool(let b) = value { return b }
                  return false
              },
              set: { value = .bool($0) }
          )
      }
  }
  ```

- [ ] **Step 4: Run tests**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: 16 tests pass total (12 prior + 4 new `SchemaInspectorTests`).

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(inspector): FieldFormatter + FieldEditorView per FieldType"
  ```

---

## Task 10: TagsEditorView + Inspector rewiring

**Files:**
- Create: `FantasyTavernApp/Sources/Inspector/TagsEditorView.swift`
- Modify: `FantasyTavernApp/Sources/Inspector/InspectorView.swift`
- Modify: `FantasyTavernApp/Sources/Editor/EditorView.swift` (move debounced save up so it covers fields/tags)

This task ties everything together.

- [ ] **Step 1: Write `TagsEditorView`**

  `FantasyTavernApp/Sources/Inspector/TagsEditorView.swift`:

  ```swift
  import SwiftUI

  /// Comma-separated tags editor. Stores lower-cased, trimmed, deduped tags.
  struct TagsEditorView: View {
      @Binding var tags: [String]

      var body: some View {
          VStack(alignment: .leading, spacing: 4) {
              Text("Tags").font(.headline)
              TextField("comma, separated", text: textBinding)
                  .textFieldStyle(.roundedBorder)
              if !tags.isEmpty {
                  HStack {
                      ForEach(tags, id: \.self) { tag in
                          Text("#\(tag)")
                              .font(.caption)
                              .padding(.horizontal, 6).padding(.vertical, 2)
                              .background(Color.secondary.opacity(0.15))
                              .clipShape(Capsule())
                      }
                  }
              }
          }
      }

      private var textBinding: Binding<String> {
          Binding(
              get: { tags.joined(separator: ", ") },
              set: { newRaw in
                  let parts = newRaw.split(separator: ",")
                      .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                      .filter { !$0.isEmpty }
                  var seen = Set<String>()
                  tags = parts.filter { seen.insert($0).inserted }
              }
          )
      }
  }
  ```

- [ ] **Step 2: Rewire `InspectorView`**

  Overwrite `FantasyTavernApp/Sources/Inspector/InspectorView.swift`:

  ```swift
  import SwiftUI
  import EntityModel
  import SchemaRegistry

  struct InspectorView: View {
      @Environment(WorldSession.self) private var session
      @Environment(TabsModel.self) private var tabs

      /// Bindings provided by EditorView so changes flow back into the same debounced save pipeline.
      @Binding var tags: [String]
      @Binding var fields: [String: FieldValue]

      let entity: Entity

      var body: some View {
          ScrollView {
              VStack(alignment: .leading, spacing: 16) {
                  let defs = session.fields(for: entity.type)
                  if !defs.isEmpty {
                      VStack(alignment: .leading, spacing: 6) {
                          Text("Fields").font(.headline)
                          ForEach(defs, id: \.key) { def in
                              FieldEditorView(definition: def, value: fieldBinding(def.key))
                          }
                      }
                  }

                  TagsEditorView(tags: $tags)

                  VStack(alignment: .leading, spacing: 4) {
                      Text("Backlinks").font(.headline)
                      let ids = session.backlinks(to: entity.id)
                      if ids.isEmpty {
                          Text("No incoming links yet.").foregroundStyle(.secondary).font(.caption)
                      } else {
                          ForEach(ids, id: \.self) { id in
                              Button(name(for: id)) { tabs.open(id) }.buttonStyle(.link)
                          }
                      }
                  }
                  Spacer(minLength: 0)
              }
              .padding()
          }
      }

      private func fieldBinding(_ key: String) -> Binding<FieldValue?> {
          Binding(
              get: { fields[key] },
              set: { newValue in
                  if let newValue { fields[key] = newValue }
                  else { fields.removeValue(forKey: key) }
              }
          )
      }

      private func name(for id: EntityID) -> String {
          session.store?.entities.first(where: { $0.id == id })?.name ?? id.rawValue
      }
  }
  ```

- [ ] **Step 3: Update `EditorView` — own tags & fields state, pass bindings to InspectorView**

  Overwrite `FantasyTavernApp/Sources/Editor/EditorView.swift`:

  ```swift
  import SwiftUI
  import EntityModel
  import WikiLinks

  struct EditorView: View {
      @Environment(WorldSession.self) private var session
      @Environment(TabsModel.self) private var tabs
      let entity: Entity

      @State private var nameDraft: String = ""
      @State private var bodyText: String = ""
      @State private var tags: [String] = []
      @State private var fields: [String: FieldValue] = [:]
      @State private var saveTask: Task<Void, Never>?

      var body: some View {
          HStack(spacing: 0) {
              VStack(alignment: .leading, spacing: 8) {
                  TextField("Name", text: $nameDraft)
                      .textFieldStyle(.plain)
                      .font(.title2)
                      .padding(.top, 8).padding(.horizontal, 12)
                      .onChange(of: nameDraft) { _, _ in scheduleSave() }
                  Divider()
                  MarkdownTextView(
                      text: $bodyText,
                      resolver: WikiLinkResolver(entities: session.store?.entities ?? []),
                      onOpenLink: { tabs.open($0) }
                  )
                  .onChange(of: bodyText) { _, _ in scheduleSave() }
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              Divider()
              InspectorView(tags: $tags, fields: $fields, entity: entity)
                  .frame(width: 280)
                  .onChange(of: tags) { _, _ in scheduleSave() }
                  .onChange(of: fields) { _, _ in scheduleSave() }
          }
          .onAppear { loadDrafts() }
          .onChange(of: entity.id) { _, _ in loadDrafts() }
      }

      private func loadDrafts() {
          nameDraft = entity.name
          bodyText = entity.body
          tags = entity.tags
          fields = entity.fields
      }

      private func scheduleSave() {
          saveTask?.cancel()
          let snapshot = (nameDraft, bodyText, tags, fields)
          let target = entity
          saveTask = Task {
              try? await Task.sleep(nanoseconds: 500_000_000)
              if Task.isCancelled { return }
              var copy = target
              copy.name = snapshot.0
              copy.body = snapshot.1
              copy.tags = snapshot.2
              copy.fields = snapshot.3
              try? session.save(copy)
          }
      }
  }
  ```

  Because `EditorView` now owns the inspector layout, **update `ContentView` to stop placing `InspectorView` itself**.

- [ ] **Step 4: Update `ContentView`**

  Overwrite `FantasyTavernApp/Sources/ContentView.swift`:

  ```swift
  import SwiftUI
  import EntityModel

  struct ContentView: View {
      @Environment(WorldSession.self) private var session
      @Environment(TabsModel.self) private var tabs

      var body: some View {
          NavigationSplitView {
              SidebarView()
                  .frame(minWidth: 220)
          } detail: {
              VStack(spacing: 0) {
                  TabBarView()
                  Divider()
                  if let id = tabs.selected, let entity = entity(for: id) {
                      EditorView(entity: entity)
                          .frame(maxWidth: .infinity, maxHeight: .infinity)
                  } else {
                      ContentUnavailableView("No tab open", systemImage: "doc.text",
                                             description: Text("Open an entity from the sidebar."))
                          .frame(maxWidth: .infinity, maxHeight: .infinity)
                  }
              }
          }
      }

      private func entity(for id: EntityID) -> Entity? {
          session.store?.entities.first(where: { $0.id == id })
      }
  }
  ```

- [ ] **Step 5: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: `** BUILD SUCCEEDED **`, 16 tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(inspector): schema-driven fields + tags editor wired through debounced save"
  ```

---

## Task 11: Manual acceptance & smoke test

**Files:** none.

- [ ] **Step 1: Run all tests**

  ```bash
  swift test --package-path Packages/EntityModel    2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
  swift test --package-path Packages/WorldStore     2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
  swift test --package-path Packages/WikiLinks      2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
  swift test --package-path Packages/SchemaRegistry 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: all packages green; app target 16 tests pass.

- [ ] **Step 2: Build + launch app**

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -3
  pkill -f FantasyTavernApp 2>/dev/null || true
  sleep 1
  open ~/Library/Developer/Xcode/DerivedData/FantasyTavern-cjpexdvcsmhrwcafqhtvzpbgihqg/Build/Products/Debug/FantasyTavernApp.app
  ```

  (DerivedData path may differ on your machine — check with `xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -showBuildSettings | grep BUILT_PRODUCTS_DIR`.)

- [ ] **Step 3: Walk through acceptance flow**

  1. File → Open World → `~/Documents/FantasyTavern/Aetheria`.
  2. Sidebar shows seven groups: `Characters (2)`, `Locations (0)`, `Lore (0)`, `Items (0)`, `Languages (0)`, `Journal (0)`, `Timeline (0)`.
  3. File → New → Location → an "Untitled Location" tab opens.
     - Rename it to "Silvermoon". The sidebar reflects the new name; `Locations (1)`.
     - In the inspector: Kind picker, Population field, Climate field appear. Set Kind=`city`, Population=`12000`. Verify the values stick after closing the tab and reopening it.
     - Inspect `~/Documents/FantasyTavern/Aetheria/locations/silvermoon.md` → front-matter has `kind: city`, `population: 12000`.
  4. File → New → Item → set Rarity=`rare`, Attunement=`true`. Confirm file front-matter reflects it.
  5. Edit "Lyra Stormwind". In the inspector, add tags: `noble, ranger`. Confirm tag pills appear and that the file's `tags: [noble, ranger]` is updated after the debounce.
  6. Open the link in Lyra's body — `[[Silvermoon]]` should now resolve (blue pill) because Silvermoon exists.
  7. Quit + relaunch. All edits persist.
  8. Custom-schema check: edit `~/Documents/FantasyTavern/Aetheria/world.json` to:

     ```json
     {
       "name": "Aetheria",
       "color": "#7a4ab8",
       "schemaOverrides": {
         "character": [
           { "key": "house", "label": "House", "type": "string" }
         ]
       }
     }
     ```

     Reopen the world. The Character inspector now shows a "House" field only (race/age/alignment/status gone). Set "House" = `Stormwind". Confirm the value persists.

- [ ] **Step 4: Tag the plan complete**

  ```bash
  git tag plan-2-full-entity-coverage-complete
  ```

---

## Deferred from Plan 2 (call out at review)

- "+ Add field" per-entity ad-hoc fields not in plan. Add later if needed; defaults + per-world overrides cover the common case.
- `list<T>` field type not supported by `FieldEditorView` (defaults schemas don't use it). `FrontMatter.serializeFields` already skips `.list`. If a later world needs list fields, extend both.
- Settings → Schemas form-driven editor for `world.json` (spec calls for this). Plan 2 expects users to hand-edit `world.json`; UI editor deferred.

## Self-Review notes

**Spec coverage:**
- Character/location/lore/item/language/journal + timeline event types now usable end-to-end via Tasks 6–10. ✓
- Schema-driven inspector form: Task 9 + Task 10. ✓
- Tags editor: Task 10. ✓
- Per-type "New …" menu: Task 7. ✓
- `world.json.schemaOverrides`: Task 3 (loader) + Task 4 (wired into `WorldStore`). ✓

**Placeholder scan:** no TBDs, no vague steps; every code block complete.

**Type consistency:**
- `WorldSession.createEntity(type:name:)` — referenced consistently in Tasks 6 and 7.
- `session.fields(for: .character)` — defined in Task 6, used in Task 9 (`InspectorView`).
- `WorldStore.schema` — added in Task 4, exposed via `session.fields(for:)` in Task 6.
- `FieldFormatter.display(_:type:)` / `parse(_:as:)` — used in `FieldEditorView` only; same signatures throughout.
- `RecentWorlds.shared` — pre-existing, untouched.
