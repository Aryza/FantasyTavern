# FantasyTavern Plan 1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the macOS app with file-driven world storage, character entities end-to-end (load, edit, save, wiki-link, backlinks), and a minimal sidebar + tabbed editor UI.

**Architecture:** SwiftUI shell wrapping AppKit (`NSTextView`) for the editor. Local Swift packages under `Core/` for pure logic (`EntityModel`, `WorldStore`, `WikiLinks`). UI features under `Features/` depend on Core only. Plain-file storage: world = folder, entity = `.md` with YAML front-matter.

**Tech Stack:** Swift 5.10+, macOS 14+, SwiftUI, AppKit (NSTextView), Yams (YAML), SwiftPM, XCTest, Xcode 15+.

**Out of scope for Plan 1** (will be later plans): non-character entity types (locations/lore/etc.), schema-driven inspector fields, tags UI, search/⌘K, timeline view, map view, snapshots, export, FSEvents external-edit watcher.

**Plan 1 success criteria:**
1. App launches, user picks a folder, world loads.
2. Sidebar shows world name and "Characters" group with all character entries.
3. Click a character → opens in a new tab.
4. Edit character body in the editor → save is debounced and writes the file atomically.
5. Typing `[[Other Character]]` renders a pill; clicking the pill opens that character in a new tab.
6. Backlinks pane shows entities linking to the current character.
7. "New Character" creates a stub entity and opens it.

---

## File Structure

```
FantasyTavern/                              # repo root
  FantasyTavern.xcworkspace                 # workspace ties app + packages
  FantasyTavernApp/                         # Xcode app project
    FantasyTavernApp.xcodeproj
    FantasyTavernApp/
      FantasyTavernAppApp.swift             # @main
      ContentView.swift                     # NavigationSplitView shell
      WorldSession.swift                    # @Observable world state for views
      Sidebar/
        SidebarView.swift                   # sidebar list
      Tabs/
        TabBarView.swift                    # browser-style tab strip
        EditorTab.swift                     # one tab = entity id
        TabsModel.swift                     # @Observable list of open tabs
      Editor/
        EditorView.swift                    # SwiftUI host
        MarkdownTextView.swift              # NSViewRepresentable wrapping NSTextView
        MarkdownStyler.swift                # applies attributes to text storage
        WikiLinkAttachment.swift            # custom attribute / click handling
      Inspector/
        InspectorView.swift                 # right pane (backlinks for Plan 1)
      Commands/
        AppCommands.swift                   # menu commands (File > New Character, Open World…)
    FantasyTavernAppTests/
      WorldSessionTests.swift
      TabsModelTests.swift
      MarkdownStylerTests.swift
  Packages/
    EntityModel/
      Package.swift
      Sources/EntityModel/
        Entity.swift                        # struct Entity
        EntityType.swift                    # enum EntityType
        EntityID.swift                      # typed slug
      Tests/EntityModelTests/
        EntityTests.swift
    WorldStore/
      Package.swift
      Sources/WorldStore/
        WorldStore.swift                    # public API
        FrontMatter.swift                   # YAML front-matter parse + serialize
        EntityFile.swift                    # read/write one .md file
        Slug.swift                          # name -> filename-safe slug
      Tests/WorldStoreTests/
        FrontMatterTests.swift
        EntityFileTests.swift
        WorldStoreTests.swift
        SlugTests.swift
        Fixtures/                           # sample worlds for tests
    WikiLinks/
      Package.swift
      Sources/WikiLinks/
        WikiLinkParser.swift                # scan body, return ranges + names
        WikiLinkResolver.swift              # name -> id map, resolve/dangling
        BacklinkIndex.swift                 # entity id -> set of source ids
      Tests/WikiLinksTests/
        WikiLinkParserTests.swift
        WikiLinkResolverTests.swift
        BacklinkIndexTests.swift
  docs/superpowers/                         # already exists
  .gitignore
```

**Why this split:** Three concerns are pure logic (model, disk, links) and live in SPM packages with no UI dependency, so they are fast to test and reusable in later plans. UI is in the app target only. Each file has one job — when the editor grows in later plans (hybrid styling, autocomplete popovers, etc.), `MarkdownStyler` and `MarkdownTextView` can expand without polluting other files.

---

## Conventions

- **Slug rule:** lower-case, replace whitespace/punct with `-`, collapse runs of `-`, trim leading/trailing `-`. ASCII fold first (`é` → `e`). Empty result → `untitled`.
- **Atomic write:** write to `<path>.tmp-<uuid>` in the same directory, then `rename` to the final path. macOS `FileManager.replaceItemAt(_:withItemAt:)` is the API.
- **Date format:** ISO 8601 with seconds, UTC, e.g. `2026-05-12T10:00:00Z`. Use `ISO8601DateFormatter` with `.withInternetDateTime`.
- **Wiki-link syntax (Plan 1):** `[[Name]]` and `[[Name|alias]]`. Newlines inside `[[ ]]` are not allowed (parser treats them as failed match). Names are matched case-insensitively against entity `name` field; whitespace is collapsed.
- **Commit messages:** Conventional Commits. `feat:`, `test:`, `chore:`, `fix:`. One commit per task (end-of-task step).

---

## Task 0: Repo & Xcode skeleton

**Files:**
- Create: `FantasyTavern.xcworkspace/contents.xcworkspacedata`
- Create: `FantasyTavernApp/FantasyTavernApp.xcodeproj` (via Xcode UI)
- Create: `Packages/EntityModel/Package.swift`
- Create: `Packages/WorldStore/Package.swift`
- Create: `Packages/WikiLinks/Package.swift`
- Modify: `.gitignore` (append Xcode patterns)

- [ ] **Step 1: Create Xcode app project**

  In Xcode: File → New → Project → macOS → App. Name: `FantasyTavernApp`. Interface: SwiftUI. Language: Swift. Save into `FantasyTavernApp/`. Bundle id: `de.aryb.FantasyTavern`. Minimum deployment: macOS 14.0. Disable Tests target option? **No** — keep the auto-generated test target.

- [ ] **Step 2: Create the workspace**

  In Xcode: File → New → Workspace → save as `FantasyTavern.xcworkspace` at repo root. Drag `FantasyTavernApp.xcodeproj` into the workspace.

- [ ] **Step 3: Create three local SPM packages**

  From a terminal at repo root:

  ```bash
  mkdir -p Packages/EntityModel Packages/WorldStore Packages/WikiLinks
  (cd Packages/EntityModel && swift package init --type library --name EntityModel)
  (cd Packages/WorldStore  && swift package init --type library --name WorldStore)
  (cd Packages/WikiLinks   && swift package init --type library --name WikiLinks)
  ```

  Drag each package folder into the workspace's left navigator under the workspace (not under the app project).

- [ ] **Step 4: Set platform + Swift tools version on each Package.swift**

  Edit each `Package.swift` so it reads (adjust the `name`):

  ```swift
  // swift-tools-version: 5.10
  import PackageDescription

  let package = Package(
      name: "EntityModel",
      platforms: [.macOS(.v14)],
      products: [
          .library(name: "EntityModel", targets: ["EntityModel"]),
      ],
      dependencies: [],
      targets: [
          .target(name: "EntityModel"),
          .testTarget(name: "EntityModelTests", dependencies: ["EntityModel"]),
      ]
  )
  ```

  Repeat for `WorldStore` and `WikiLinks` (name + product/target names match the package).

- [ ] **Step 5: Link packages into the app target**

  In Xcode → FantasyTavernApp target → General → Frameworks, Libraries, and Embedded Content → `+` → Add `EntityModel`, `WorldStore`, `WikiLinks` from the workspace. Also add Yams once introduced (Task 2).

- [ ] **Step 6: Confirm a clean build**

  Run: ⌘B in Xcode. Expected: build succeeds with no source changes yet. Run the app: ⌘R. Expected: an empty default ContentView window opens.

- [ ] **Step 7: Commit**

  ```bash
  git add .
  git commit -m "chore: scaffold Xcode app + local SPM packages"
  ```

---

## Task 1: EntityModel types

**Files:**
- Create: `Packages/EntityModel/Sources/EntityModel/EntityID.swift`
- Create: `Packages/EntityModel/Sources/EntityModel/EntityType.swift`
- Create: `Packages/EntityModel/Sources/EntityModel/Entity.swift`
- Create: `Packages/EntityModel/Tests/EntityModelTests/EntityTests.swift`

- [ ] **Step 1: Write failing test**

  `Packages/EntityModel/Tests/EntityModelTests/EntityTests.swift`:

  ```swift
  import XCTest
  @testable import EntityModel

  final class EntityTests: XCTestCase {
      func test_entity_equatable_byID() {
          let a = Entity(id: EntityID("lyra"), type: .character, name: "Lyra", body: "x")
          let b = Entity(id: EntityID("lyra"), type: .character, name: "Lyra (renamed)", body: "y")
          XCTAssertEqual(a.id, b.id)
          XCTAssertNotEqual(a, b) // full equality differs because body differs
      }

      func test_entityID_isStringRawValue() {
          let id = EntityID("lyra-stormwind")
          XCTAssertEqual(id.rawValue, "lyra-stormwind")
      }

      func test_entityType_rawStrings() {
          XCTAssertEqual(EntityType.character.rawValue, "character")
          XCTAssertEqual(EntityType.location.rawValue, "location")
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  Run: `swift test --package-path Packages/EntityModel` (from repo root). Expected: compile failure (`EntityID` / `Entity` / `EntityType` unknown).

- [ ] **Step 3: Implement `EntityID`**

  `Packages/EntityModel/Sources/EntityModel/EntityID.swift`:

  ```swift
  import Foundation

  public struct EntityID: RawRepresentable, Hashable, Codable, Sendable {
      public let rawValue: String
      public init(rawValue: String) { self.rawValue = rawValue }
      public init(_ value: String) { self.rawValue = value }
  }
  ```

- [ ] **Step 4: Implement `EntityType`**

  `Packages/EntityModel/Sources/EntityModel/EntityType.swift`:

  ```swift
  import Foundation

  public enum EntityType: String, CaseIterable, Codable, Sendable {
      case character
      case location
      case lore
      case item
      case language
      case journal
      case timelineEvent

      public var folderName: String {
          switch self {
          case .character: return "characters"
          case .location:  return "locations"
          case .lore:      return "lore"
          case .item:      return "items"
          case .language:  return "languages"
          case .journal:   return "journal"
          case .timelineEvent: return "timeline"
          }
      }
  }
  ```

- [ ] **Step 5: Implement `Entity`**

  `Packages/EntityModel/Sources/EntityModel/Entity.swift`:

  ```swift
  import Foundation

  public struct Entity: Equatable, Codable, Sendable {
      public var id: EntityID
      public var type: EntityType
      public var name: String
      public var tags: [String]
      public var fields: [String: FieldValue]
      public var body: String
      public var created: Date
      public var updated: Date

      public init(
          id: EntityID,
          type: EntityType,
          name: String,
          tags: [String] = [],
          fields: [String: FieldValue] = [:],
          body: String = "",
          created: Date = Date(),
          updated: Date = Date()
      ) {
          self.id = id
          self.type = type
          self.name = name
          self.tags = tags
          self.fields = fields
          self.body = body
          self.created = created
          self.updated = updated
      }
  }

  public enum FieldValue: Equatable, Codable, Sendable {
      case string(String)
      case int(Int)
      case bool(Bool)
      case date(Date)
      case ref(EntityID)
      case list([FieldValue])
  }
  ```

- [ ] **Step 6: Run tests**

  Run: `swift test --package-path Packages/EntityModel`. Expected: 3 tests pass.

- [ ] **Step 7: Commit**

  ```bash
  git add Packages/EntityModel
  git commit -m "feat(EntityModel): add Entity, EntityID, EntityType, FieldValue"
  ```

---

## Task 2: Slug helper

**Files:**
- Create: `Packages/WorldStore/Sources/WorldStore/Slug.swift`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/SlugTests.swift`
- Modify: `Packages/WorldStore/Package.swift` (depend on EntityModel + add Yams dep)

- [ ] **Step 1: Update `Packages/WorldStore/Package.swift`**

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
          .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.6"),
      ],
      targets: [
          .target(
              name: "WorldStore",
              dependencies: [
                  "EntityModel",
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

  Create empty fixtures dir: `mkdir -p Packages/WorldStore/Tests/WorldStoreTests/Fixtures`.

- [ ] **Step 2: Write failing test**

  `Packages/WorldStore/Tests/WorldStoreTests/SlugTests.swift`:

  ```swift
  import XCTest
  @testable import WorldStore

  final class SlugTests: XCTestCase {
      func test_basicLowercase() {
          XCTAssertEqual(Slug.make("Lyra"), "lyra")
      }
      func test_replacesWhitespaceWithHyphen() {
          XCTAssertEqual(Slug.make("Lyra Stormwind"), "lyra-stormwind")
      }
      func test_collapsesRuns() {
          XCTAssertEqual(Slug.make("Lyra   Stormwind!!"), "lyra-stormwind")
      }
      func test_asciiFoldsAccents() {
          XCTAssertEqual(Slug.make("Étienne"), "etienne")
      }
      func test_emptyBecomesUntitled() {
          XCTAssertEqual(Slug.make("   "), "untitled")
          XCTAssertEqual(Slug.make(""), "untitled")
      }
      func test_trimsLeadingTrailingHyphens() {
          XCTAssertEqual(Slug.make("--hi--"), "hi")
      }
  }
  ```

- [ ] **Step 3: Run to verify failure**

  Run: `swift test --package-path Packages/WorldStore`. Expected: compile failure (`Slug` unknown).

- [ ] **Step 4: Implement**

  `Packages/WorldStore/Sources/WorldStore/Slug.swift`:

  ```swift
  import Foundation

  public enum Slug {
      public static func make(_ input: String) -> String {
          let folded = input.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US_POSIX"))
          var out = ""
          var lastWasHyphen = false
          for scalar in folded.unicodeScalars {
              if CharacterSet.alphanumerics.contains(scalar) {
                  out.append(Character(scalar))
                  lastWasHyphen = false
              } else if !lastWasHyphen {
                  out.append("-")
                  lastWasHyphen = true
              }
          }
          while out.hasPrefix("-") { out.removeFirst() }
          while out.hasSuffix("-") { out.removeLast() }
          return out.isEmpty ? "untitled" : out
      }
  }
  ```

- [ ] **Step 5: Run tests**

  Run: `swift test --package-path Packages/WorldStore`. Expected: 6 SlugTests pass. (Yams will download on first build — wait if needed.)

- [ ] **Step 6: Commit**

  ```bash
  git add Packages/WorldStore
  git commit -m "feat(WorldStore): add Slug helper + Yams dependency"
  ```

---

## Task 3: FrontMatter parse & serialize

**Files:**
- Create: `Packages/WorldStore/Sources/WorldStore/FrontMatter.swift`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/FrontMatterTests.swift`

- [ ] **Step 1: Write failing tests**

  `Packages/WorldStore/Tests/WorldStoreTests/FrontMatterTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import WorldStore

  final class FrontMatterTests: XCTestCase {
      let sample = """
      ---
      id: lyra-stormwind
      type: character
      name: Lyra Stormwind
      tags: [noble, ranger]
      fields:
        race: half-elf
        age: 87
      created: 2026-05-12T10:00:00Z
      updated: 2026-05-12T11:30:00Z
      ---
      Half-elven ranger from [[Silvermoon]].
      """

      func test_parse_extractsBodyAndFrontMatter() throws {
          let parsed = try FrontMatter.parse(sample)
          XCTAssertEqual(parsed.entity.id.rawValue, "lyra-stormwind")
          XCTAssertEqual(parsed.entity.type, .character)
          XCTAssertEqual(parsed.entity.name, "Lyra Stormwind")
          XCTAssertEqual(parsed.entity.tags, ["noble", "ranger"])
          XCTAssertEqual(parsed.entity.fields["race"], .string("half-elf"))
          XCTAssertEqual(parsed.entity.fields["age"], .int(87))
          XCTAssertEqual(parsed.entity.body, "Half-elven ranger from [[Silvermoon]].")
      }

      func test_parse_missingFrontMatter_throws() {
          XCTAssertThrowsError(try FrontMatter.parse("no front matter here"))
      }

      func test_serialize_roundTrip() throws {
          let parsed = try FrontMatter.parse(sample)
          let serialized = try FrontMatter.serialize(parsed.entity)
          let again = try FrontMatter.parse(serialized)
          XCTAssertEqual(parsed.entity, again.entity)
      }

      func test_serialize_includesFrontMatterDelimiters() throws {
          let entity = Entity(
              id: EntityID("x"), type: .character, name: "X",
              created: Date(timeIntervalSince1970: 0), updated: Date(timeIntervalSince1970: 0)
          )
          let out = try FrontMatter.serialize(entity)
          XCTAssertTrue(out.hasPrefix("---\n"))
          XCTAssertTrue(out.contains("\n---\n"))
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  Run: `swift test --package-path Packages/WorldStore --filter FrontMatterTests`. Expected: compile failure.

- [ ] **Step 3: Implement `FrontMatter`**

  `Packages/WorldStore/Sources/WorldStore/FrontMatter.swift`:

  ```swift
  import Foundation
  import Yams
  import EntityModel

  public enum FrontMatterError: Error {
      case missingDelimiters
      case malformedYAML(String)
      case missingRequiredField(String)
  }

  public struct ParsedEntityFile {
      public let entity: Entity
  }

  public enum FrontMatter {
      private static let delimiter = "---"
      private static let iso: ISO8601DateFormatter = {
          let f = ISO8601DateFormatter()
          f.formatOptions = [.withInternetDateTime]
          return f
      }()

      public static func parse(_ source: String) throws -> ParsedEntityFile {
          guard source.hasPrefix("\(delimiter)\n") else { throw FrontMatterError.missingDelimiters }
          let afterOpen = source.dropFirst(delimiter.count + 1)
          guard let endRange = afterOpen.range(of: "\n\(delimiter)\n") ?? afterOpen.range(of: "\n\(delimiter)") else {
              throw FrontMatterError.missingDelimiters
          }
          let yamlText = String(afterOpen[..<endRange.lowerBound])
          let body = String(afterOpen[endRange.upperBound...])
              .trimmingCharacters(in: .whitespacesAndNewlines)

          let yamlNode: Any
          do { yamlNode = try Yams.load(yaml: yamlText) ?? [:] }
          catch { throw FrontMatterError.malformedYAML("\(error)") }

          guard let dict = yamlNode as? [String: Any] else {
              throw FrontMatterError.malformedYAML("front matter is not a mapping")
          }

          let idStr = try required(dict, "id") as String
          let typeStr = try required(dict, "type") as String
          guard let type = EntityType(rawValue: typeStr) else {
              throw FrontMatterError.malformedYAML("unknown type \(typeStr)")
          }
          let name = try required(dict, "name") as String
          let tags = (dict["tags"] as? [String]) ?? []
          let fields = parseFields(dict["fields"] as? [String: Any] ?? [:])
          let created = parseDate(dict["created"]) ?? Date()
          let updated = parseDate(dict["updated"]) ?? created

          let entity = Entity(
              id: EntityID(idStr), type: type, name: name,
              tags: tags, fields: fields, body: body,
              created: created, updated: updated
          )
          return ParsedEntityFile(entity: entity)
      }

      public static func serialize(_ entity: Entity) throws -> String {
          var dict: [String: Any] = [
              "id": entity.id.rawValue,
              "type": entity.type.rawValue,
              "name": entity.name,
              "tags": entity.tags,
              "fields": serializeFields(entity.fields),
              "created": iso.string(from: entity.created),
              "updated": iso.string(from: entity.updated),
          ]
          // strip empty collections for cleanliness
          if (dict["tags"] as? [String])?.isEmpty == true { dict["tags"] = [] }
          let yamlString = try Yams.dump(object: dict, sortKeys: true)
          let trimmedYaml = yamlString.trimmingCharacters(in: .whitespacesAndNewlines)
          return "---\n\(trimmedYaml)\n---\n\(entity.body)\n"
      }

      // MARK: - helpers

      private static func required<T>(_ dict: [String: Any], _ key: String) throws -> T {
          guard let any = dict[key], let value = any as? T else {
              throw FrontMatterError.missingRequiredField(key)
          }
          return value
      }

      private static func parseDate(_ any: Any?) -> Date? {
          if let d = any as? Date { return d }
          if let s = any as? String { return iso.date(from: s) }
          return nil
      }

      private static func parseFields(_ raw: [String: Any]) -> [String: FieldValue] {
          var out: [String: FieldValue] = [:]
          for (k, v) in raw {
              if let s = v as? String { out[k] = .string(s) }
              else if let i = v as? Int { out[k] = .int(i) }
              else if let b = v as? Bool { out[k] = .bool(b) }
              else if let d = v as? Date { out[k] = .date(d) }
          }
          return out
      }

      private static func serializeFields(_ fields: [String: FieldValue]) -> [String: Any] {
          var out: [String: Any] = [:]
          for (k, v) in fields {
              switch v {
              case .string(let s): out[k] = s
              case .int(let i): out[k] = i
              case .bool(let b): out[k] = b
              case .date(let d): out[k] = iso.string(from: d)
              case .ref(let id): out[k] = id.rawValue
              case .list: continue // Plan 1: skip list fields in serialization
              }
          }
          return out
      }
  }
  ```

- [ ] **Step 4: Run tests**

  Run: `swift test --package-path Packages/WorldStore --filter FrontMatterTests`. Expected: 4 tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WorldStore
  git commit -m "feat(WorldStore): parse & serialize YAML front-matter for entities"
  ```

---

## Task 4: EntityFile read & atomic write

**Files:**
- Create: `Packages/WorldStore/Sources/WorldStore/EntityFile.swift`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/EntityFileTests.swift`

- [ ] **Step 1: Write failing tests**

  `Packages/WorldStore/Tests/WorldStoreTests/EntityFileTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import WorldStore

  final class EntityFileTests: XCTestCase {
      var tmp: URL!

      override func setUpWithError() throws {
          tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
      }
      override func tearDownWithError() throws {
          try? FileManager.default.removeItem(at: tmp)
      }

      func test_writeThenRead_roundTrip() throws {
          let entity = Entity(id: EntityID("lyra"), type: .character, name: "Lyra", body: "Hello [[Silvermoon]]")
          let url = tmp.appendingPathComponent("lyra.md")
          try EntityFile.write(entity, to: url)
          let read = try EntityFile.read(from: url, fallbackType: .character)
          XCTAssertEqual(read.id, entity.id)
          XCTAssertEqual(read.body, entity.body)
      }

      func test_write_isAtomic_noPartialFile() throws {
          let entity = Entity(id: EntityID("a"), type: .character, name: "A", body: "x")
          let url = tmp.appendingPathComponent("a.md")
          try EntityFile.write(entity, to: url)
          let siblings = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
          // only the final file should remain — no .tmp-* leftovers
          XCTAssertEqual(siblings, ["a.md"])
      }

      func test_read_missingFrontMatter_throws() throws {
          let url = tmp.appendingPathComponent("bad.md")
          try "just body".write(to: url, atomically: true, encoding: .utf8)
          XCTAssertThrowsError(try EntityFile.read(from: url, fallbackType: .character))
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  Run: `swift test --package-path Packages/WorldStore --filter EntityFileTests`. Expected: compile failure.

- [ ] **Step 3: Implement**

  `Packages/WorldStore/Sources/WorldStore/EntityFile.swift`:

  ```swift
  import Foundation
  import EntityModel

  public enum EntityFileError: Error {
      case readFailed(URL, underlying: Error)
      case writeFailed(URL, underlying: Error)
  }

  public enum EntityFile {
      public static func read(from url: URL, fallbackType: EntityType) throws -> Entity {
          let text: String
          do { text = try String(contentsOf: url, encoding: .utf8) }
          catch { throw EntityFileError.readFailed(url, underlying: error) }
          let parsed = try FrontMatter.parse(text)
          return parsed.entity
      }

      public static func write(_ entity: Entity, to url: URL) throws {
          let dir = url.deletingLastPathComponent()
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          let payload: String
          do { payload = try FrontMatter.serialize(entity) }
          catch { throw EntityFileError.writeFailed(url, underlying: error) }

          let tmp = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
          do {
              try payload.data(using: .utf8)!.write(to: tmp, options: .atomic)
              if FileManager.default.fileExists(atPath: url.path) {
                  _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
              } else {
                  try FileManager.default.moveItem(at: tmp, to: url)
              }
          } catch {
              try? FileManager.default.removeItem(at: tmp)
              throw EntityFileError.writeFailed(url, underlying: error)
          }
      }
  }
  ```

- [ ] **Step 4: Run tests**

  Run: `swift test --package-path Packages/WorldStore --filter EntityFileTests`. Expected: 3 tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WorldStore
  git commit -m "feat(WorldStore): atomic EntityFile read/write"
  ```

---

## Task 5: WorldStore.open & save

**Files:**
- Create: `Packages/WorldStore/Sources/WorldStore/WorldStore.swift`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/WorldStoreTests.swift`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/Fixtures/Aetheria/world.json`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/Fixtures/Aetheria/characters/lyra-stormwind.md`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/Fixtures/Aetheria/characters/magnus-blackthorn.md`

- [ ] **Step 1: Create fixture files**

  `Packages/WorldStore/Tests/WorldStoreTests/Fixtures/Aetheria/world.json`:

  ```json
  { "name": "Aetheria", "color": "#7a4ab8" }
  ```

  `Packages/WorldStore/Tests/WorldStoreTests/Fixtures/Aetheria/characters/lyra-stormwind.md`:

  ```markdown
  ---
  id: lyra-stormwind
  type: character
  name: Lyra Stormwind
  tags: [ranger]
  fields:
    race: half-elf
  created: 2026-05-12T10:00:00Z
  updated: 2026-05-12T10:00:00Z
  ---
  Friend of [[Magnus Blackthorn]].
  ```

  `Packages/WorldStore/Tests/WorldStoreTests/Fixtures/Aetheria/characters/magnus-blackthorn.md`:

  ```markdown
  ---
  id: magnus-blackthorn
  type: character
  name: Magnus Blackthorn
  tags: []
  fields: {}
  created: 2026-05-12T10:00:00Z
  updated: 2026-05-12T10:00:00Z
  ---
  Sorcerer.
  ```

- [ ] **Step 2: Write failing tests**

  `Packages/WorldStore/Tests/WorldStoreTests/WorldStoreTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import WorldStore

  final class WorldStoreTests: XCTestCase {
      var tmpRoot: URL!

      override func setUpWithError() throws {
          tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
      }
      override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmpRoot) }

      private func copyFixtureWorld() throws -> URL {
          let src = Bundle.module.url(forResource: "Aetheria", withExtension: nil, subdirectory: "Fixtures")!
          let dst = tmpRoot.appendingPathComponent("Aetheria")
          try FileManager.default.copyItem(at: src, to: dst)
          return dst
      }

      func test_open_loadsAllCharacters() throws {
          let url = try copyFixtureWorld()
          let store = try WorldStore.open(url)
          XCTAssertEqual(store.world.name, "Aetheria")
          XCTAssertEqual(store.entities.count, 2)
          XCTAssertEqual(Set(store.entities.map(\.id.rawValue)), ["lyra-stormwind", "magnus-blackthorn"])
      }

      func test_save_writesEntityFileAndUpdatesEntities() throws {
          let url = try copyFixtureWorld()
          let store = try WorldStore.open(url)
          guard var lyra = store.entities.first(where: { $0.id.rawValue == "lyra-stormwind" }) else {
              return XCTFail("missing lyra")
          }
          lyra.body = "Updated body"
          try store.save(lyra)

          let reread = try WorldStore.open(url)
          let updated = reread.entities.first(where: { $0.id.rawValue == "lyra-stormwind" })
          XCTAssertEqual(updated?.body, "Updated body")
      }

      func test_create_writesNewCharacterFile() throws {
          let url = try copyFixtureWorld()
          let store = try WorldStore.open(url)
          let created = try store.create(name: "Sister Aelith", type: .character)
          XCTAssertEqual(created.id.rawValue, "sister-aelith")

          let reread = try WorldStore.open(url)
          XCTAssertTrue(reread.entities.contains(where: { $0.id == created.id }))
      }
  }
  ```

- [ ] **Step 3: Run to verify failure**

  Run: `swift test --package-path Packages/WorldStore --filter WorldStoreTests`. Expected: compile errors.

- [ ] **Step 4: Implement `WorldStore`**

  `Packages/WorldStore/Sources/WorldStore/WorldStore.swift`:

  ```swift
  import Foundation
  import EntityModel

  public struct World: Equatable, Sendable {
      public var name: String
      public var folder: URL
      public var color: String?
  }

  public final class WorldStore {
      public private(set) var world: World
      public private(set) var entities: [Entity]

      private init(world: World, entities: [Entity]) {
          self.world = world
          self.entities = entities
      }

      public static func open(_ folder: URL) throws -> WorldStore {
          let worldJSON = folder.appendingPathComponent("world.json")
          let name: String
          let color: String?
          if let data = try? Data(contentsOf: worldJSON),
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
                      // Plan 1: log to console, skip the file. Later plans surface parse errors in UI.
                      print("WorldStore: skip \(file.lastPathComponent): \(error)")
                  }
              }
          }

          let world = World(name: name, folder: folder, color: color)
          return WorldStore(world: world, entities: loaded.sorted { $0.name < $1.name })
      }

      public func save(_ entity: Entity) throws {
          var stored = entity
          stored.updated = Date()
          let url = path(for: stored)
          try EntityFile.write(stored, to: url)
          if let idx = entities.firstIndex(where: { $0.id == stored.id }) {
              entities[idx] = stored
          } else {
              entities.append(stored)
              entities.sort { $0.name < $1.name }
          }
      }

      public func create(name: String, type: EntityType) throws -> Entity {
          let slug = uniqueSlug(for: name, type: type)
          let entity = Entity(id: EntityID(slug), type: type, name: name)
          try save(entity)
          return entity
      }

      public func entities(of type: EntityType) -> [Entity] {
          entities.filter { $0.type == type }
      }

      // MARK: - paths

      public func path(for entity: Entity) -> URL {
          world.folder
              .appendingPathComponent(entity.type.folderName)
              .appendingPathComponent("\(entity.id.rawValue).md")
      }

      private func uniqueSlug(for name: String, type: EntityType) -> String {
          var base = Slug.make(name)
          let existing = Set(entities(of: type).map(\.id.rawValue))
          if !existing.contains(base) { return base }
          var n = 2
          while existing.contains("\(base)-\(n)") { n += 1 }
          return "\(base)-\(n)"
      }
  }
  ```

- [ ] **Step 5: Run tests**

  Run: `swift test --package-path Packages/WorldStore`. Expected: all WorldStore tests pass (plus prior Slug/FrontMatter/EntityFile tests still green).

- [ ] **Step 6: Commit**

  ```bash
  git add Packages/WorldStore
  git commit -m "feat(WorldStore): open world folder, save/create entities"
  ```

---

## Task 6: WikiLinks parser

**Files:**
- Modify: `Packages/WikiLinks/Package.swift` (depend on EntityModel)
- Create: `Packages/WikiLinks/Sources/WikiLinks/WikiLinkParser.swift`
- Create: `Packages/WikiLinks/Tests/WikiLinksTests/WikiLinkParserTests.swift`

- [ ] **Step 1: Update Package.swift**

  Same shape as WorldStore; add `.package(path: "../EntityModel")` and `dependencies: ["EntityModel"]` on the target.

- [ ] **Step 2: Write failing tests**

  `Packages/WikiLinks/Tests/WikiLinksTests/WikiLinkParserTests.swift`:

  ```swift
  import XCTest
  @testable import WikiLinks

  final class WikiLinkParserTests: XCTestCase {
      func test_findsSingleLink() {
          let matches = WikiLinkParser.findLinks(in: "Hi [[Lyra]]!")
          XCTAssertEqual(matches.count, 1)
          XCTAssertEqual(matches[0].name, "Lyra")
          XCTAssertNil(matches[0].alias)
      }

      func test_findsAlias() {
          let matches = WikiLinkParser.findLinks(in: "see [[Lyra Stormwind|Lyra]]")
          XCTAssertEqual(matches.first?.name, "Lyra Stormwind")
          XCTAssertEqual(matches.first?.alias, "Lyra")
      }

      func test_findsMultiple() {
          let matches = WikiLinkParser.findLinks(in: "[[A]] then [[B|b]]")
          XCTAssertEqual(matches.map(\.name), ["A", "B"])
      }

      func test_ignoresNewlinesInsideLink() {
          let matches = WikiLinkParser.findLinks(in: "[[Bad\nLink]] [[Good]]")
          XCTAssertEqual(matches.map(\.name), ["Good"])
      }

      func test_returnsByteRanges() {
          let text = "x [[Lyra]] y"
          let matches = WikiLinkParser.findLinks(in: text)
          let r = matches[0].range
          XCTAssertEqual(text[r], "[[Lyra]]")
      }
  }
  ```

- [ ] **Step 3: Run to verify failure**

  Run: `swift test --package-path Packages/WikiLinks --filter WikiLinkParserTests`. Expected: compile failure.

- [ ] **Step 4: Implement**

  `Packages/WikiLinks/Sources/WikiLinks/WikiLinkParser.swift`:

  ```swift
  import Foundation

  public struct WikiLinkMatch: Equatable {
      public let name: String
      public let alias: String?
      public let range: Range<String.Index>
  }

  public enum WikiLinkParser {
      public static func findLinks(in text: String) -> [WikiLinkMatch] {
          var results: [WikiLinkMatch] = []
          var idx = text.startIndex
          while idx < text.endIndex {
              guard let openStart = text.range(of: "[[", range: idx..<text.endIndex) else { break }
              guard let closeRange = text.range(of: "]]", range: openStart.upperBound..<text.endIndex) else { break }
              let inner = text[openStart.upperBound..<closeRange.lowerBound]
              if inner.contains("\n") || inner.contains("[[") {
                  idx = openStart.upperBound
                  continue
              }
              let (name, alias) = split(inner: String(inner))
              if !name.isEmpty {
                  results.append(.init(name: name, alias: alias, range: openStart.lowerBound..<closeRange.upperBound))
              }
              idx = closeRange.upperBound
          }
          return results
      }

      private static func split(inner: String) -> (name: String, alias: String?) {
          if let pipe = inner.firstIndex(of: "|") {
              let name = inner[..<pipe].trimmingCharacters(in: .whitespaces)
              let alias = inner[inner.index(after: pipe)...].trimmingCharacters(in: .whitespaces)
              return (String(name), alias.isEmpty ? nil : String(alias))
          }
          return (inner.trimmingCharacters(in: .whitespaces), nil)
      }
  }
  ```

- [ ] **Step 5: Run tests**

  Run: `swift test --package-path Packages/WikiLinks --filter WikiLinkParserTests`. Expected: 5 tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add Packages/WikiLinks
  git commit -m "feat(WikiLinks): parse [[...]] links with alias support"
  ```

---

## Task 7: WikiLinkResolver

**Files:**
- Create: `Packages/WikiLinks/Sources/WikiLinks/WikiLinkResolver.swift`
- Create: `Packages/WikiLinks/Tests/WikiLinksTests/WikiLinkResolverTests.swift`

- [ ] **Step 1: Write failing tests**

  `Packages/WikiLinks/Tests/WikiLinksTests/WikiLinkResolverTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import WikiLinks

  final class WikiLinkResolverTests: XCTestCase {
      let entities: [Entity] = [
          Entity(id: EntityID("lyra-stormwind"), type: .character, name: "Lyra Stormwind"),
          Entity(id: EntityID("magnus-blackthorn"), type: .character, name: "Magnus Blackthorn"),
      ]

      func test_resolveExact() {
          let r = WikiLinkResolver(entities: entities)
          XCTAssertEqual(r.resolve(name: "Lyra Stormwind")?.rawValue, "lyra-stormwind")
      }

      func test_resolveCaseInsensitive() {
          let r = WikiLinkResolver(entities: entities)
          XCTAssertEqual(r.resolve(name: "lyra stormwind")?.rawValue, "lyra-stormwind")
      }

      func test_resolveDangling_returnsNil() {
          let r = WikiLinkResolver(entities: entities)
          XCTAssertNil(r.resolve(name: "Unknown"))
      }

      func test_resolveCollapsedWhitespace() {
          let r = WikiLinkResolver(entities: entities)
          XCTAssertEqual(r.resolve(name: "  Lyra   Stormwind  ")?.rawValue, "lyra-stormwind")
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  Run: `swift test --package-path Packages/WikiLinks --filter WikiLinkResolverTests`.

- [ ] **Step 3: Implement**

  `Packages/WikiLinks/Sources/WikiLinks/WikiLinkResolver.swift`:

  ```swift
  import Foundation
  import EntityModel

  public struct WikiLinkResolver {
      private let nameToID: [String: EntityID]

      public init(entities: [Entity]) {
          var map: [String: EntityID] = [:]
          for e in entities { map[Self.normalize(e.name)] = e.id }
          self.nameToID = map
      }

      public func resolve(name: String) -> EntityID? {
          nameToID[Self.normalize(name)]
      }

      static func normalize(_ s: String) -> String {
          let lowered = s.lowercased()
          let collapsed = lowered.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
          return collapsed
      }
  }
  ```

- [ ] **Step 4: Run tests**

  Run: `swift test --package-path Packages/WikiLinks`. Expected: all WikiLinks tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WikiLinks
  git commit -m "feat(WikiLinks): name->id resolver (case + whitespace insensitive)"
  ```

---

## Task 8: BacklinkIndex

**Files:**
- Create: `Packages/WikiLinks/Sources/WikiLinks/BacklinkIndex.swift`
- Create: `Packages/WikiLinks/Tests/WikiLinksTests/BacklinkIndexTests.swift`

- [ ] **Step 1: Write failing tests**

  `Packages/WikiLinks/Tests/WikiLinksTests/BacklinkIndexTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import WikiLinks

  final class BacklinkIndexTests: XCTestCase {
      func test_buildsIncomingLinks() {
          let entities = [
              Entity(id: EntityID("a"), type: .character, name: "A", body: "see [[B]] and [[C]]"),
              Entity(id: EntityID("b"), type: .character, name: "B", body: "back to [[A]]"),
              Entity(id: EntityID("c"), type: .character, name: "C", body: ""),
          ]
          let index = BacklinkIndex(entities: entities)
          XCTAssertEqual(index.sources(linkingTo: EntityID("a")), [EntityID("b")])
          XCTAssertEqual(index.sources(linkingTo: EntityID("b")), [EntityID("a")])
          XCTAssertEqual(index.sources(linkingTo: EntityID("c")), [EntityID("a")])
      }

      func test_ignoresDanglingLinks() {
          let entities = [
              Entity(id: EntityID("a"), type: .character, name: "A", body: "[[Nobody]]"),
          ]
          let index = BacklinkIndex(entities: entities)
          XCTAssertEqual(index.sources(linkingTo: EntityID("nobody")), [])
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  Run: `swift test --package-path Packages/WikiLinks --filter BacklinkIndexTests`.

- [ ] **Step 3: Implement**

  `Packages/WikiLinks/Sources/WikiLinks/BacklinkIndex.swift`:

  ```swift
  import Foundation
  import EntityModel

  public struct BacklinkIndex {
      private let incoming: [EntityID: [EntityID]]

      public init(entities: [Entity]) {
          let resolver = WikiLinkResolver(entities: entities)
          var map: [EntityID: Set<EntityID>] = [:]
          for source in entities {
              for match in WikiLinkParser.findLinks(in: source.body) {
                  guard let target = resolver.resolve(name: match.name) else { continue }
                  map[target, default: []].insert(source.id)
              }
          }
          self.incoming = map.mapValues { Array($0).sorted { $0.rawValue < $1.rawValue } }
      }

      public func sources(linkingTo target: EntityID) -> [EntityID] {
          incoming[target] ?? []
      }
  }
  ```

- [ ] **Step 4: Run tests**

  Run: `swift test --package-path Packages/WikiLinks`. Expected: all pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WikiLinks
  git commit -m "feat(WikiLinks): BacklinkIndex over entity bodies"
  ```

---

## Task 9: WorldSession (observable app state)

**Files:**
- Create: `FantasyTavernApp/FantasyTavernApp/WorldSession.swift`
- Create: `FantasyTavernApp/FantasyTavernAppTests/WorldSessionTests.swift`

- [ ] **Step 1: Write failing tests**

  `FantasyTavernAppTests/WorldSessionTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  import WorldStore
  @testable import FantasyTavernApp

  final class WorldSessionTests: XCTestCase {
      private func makeTempWorld() throws -> URL {
          let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
          try #"{"name":"Test"}"#.write(to: url.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
          return url
      }

      func test_openWorld_loadsZeroEntities() throws {
          let session = WorldSession()
          let url = try makeTempWorld()
          try session.openWorld(at: url)
          XCTAssertEqual(session.store?.world.name, "Test")
          XCTAssertEqual(session.store?.entities.count, 0)
      }

      func test_createCharacter_appearsInEntities() throws {
          let session = WorldSession()
          try session.openWorld(at: makeTempWorld())
          let created = try session.createCharacter(name: "Lyra")
          XCTAssertEqual(created.id.rawValue, "lyra")
          XCTAssertEqual(session.store?.entities.count, 1)
      }

      func test_backlinks_updateAfterSave() throws {
          let session = WorldSession()
          try session.openWorld(at: makeTempWorld())
          let a = try session.createCharacter(name: "A")
          let b = try session.createCharacter(name: "B")
          var aEdited = a
          aEdited.body = "see [[B]]"
          try session.save(aEdited)
          XCTAssertEqual(session.backlinks(to: b.id), [a.id])
      }
  }
  ```

- [ ] **Step 2: Run tests**

  In Xcode: select FantasyTavernApp scheme → ⌘U. Expected: compile failure (`WorldSession` unknown).

- [ ] **Step 3: Implement**

  `FantasyTavernApp/FantasyTavernApp/WorldSession.swift`:

  ```swift
  import Foundation
  import Observation
  import EntityModel
  import WorldStore
  import WikiLinks

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
      public func createCharacter(name: String) throws -> Entity {
          guard let store else { throw SessionError.noWorldOpen }
          let entity = try store.create(name: name, type: .character)
          rebuildLinks()
          return entity
      }

      public func save(_ entity: Entity) throws {
          guard let store else { throw SessionError.noWorldOpen }
          try store.save(entity)
          rebuildLinks()
      }

      public func backlinks(to target: EntityID) -> [EntityID] {
          backlinkIndex.sources(linkingTo: target)
      }

      private func rebuildLinks() {
          backlinkIndex = BacklinkIndex(entities: store?.entities ?? [])
      }

      public enum SessionError: Error { case noWorldOpen }
  }
  ```

- [ ] **Step 4: Run tests**

  ⌘U. Expected: 3 WorldSessionTests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git commit -m "feat(app): WorldSession observable wrapping store + backlinks"
  ```

---

## Task 10: Tabs model

**Files:**
- Create: `FantasyTavernApp/FantasyTavernApp/Tabs/TabsModel.swift`
- Create: `FantasyTavernApp/FantasyTavernAppTests/TabsModelTests.swift`

- [ ] **Step 1: Write failing tests**

  `FantasyTavernAppTests/TabsModelTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import FantasyTavernApp

  final class TabsModelTests: XCTestCase {
      func test_open_addsTabAndSelects() {
          let model = TabsModel()
          model.open(EntityID("a"))
          XCTAssertEqual(model.openTabs, [EntityID("a")])
          XCTAssertEqual(model.selected, EntityID("a"))
      }

      func test_openExisting_doesNotDuplicate_andSelects() {
          let model = TabsModel()
          model.open(EntityID("a"))
          model.open(EntityID("b"))
          model.open(EntityID("a"))
          XCTAssertEqual(model.openTabs, [EntityID("a"), EntityID("b")])
          XCTAssertEqual(model.selected, EntityID("a"))
      }

      func test_close_removesAndPicksNeighbor() {
          let model = TabsModel()
          model.open(EntityID("a"))
          model.open(EntityID("b"))
          model.open(EntityID("c"))
          model.close(EntityID("b"))
          XCTAssertEqual(model.openTabs, [EntityID("a"), EntityID("c")])
          XCTAssertEqual(model.selected, EntityID("c"))
      }

      func test_closeLast_clearsSelection() {
          let model = TabsModel()
          model.open(EntityID("a"))
          model.close(EntityID("a"))
          XCTAssertEqual(model.openTabs, [])
          XCTAssertNil(model.selected)
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  ⌘U.

- [ ] **Step 3: Implement**

  `FantasyTavernApp/FantasyTavernApp/Tabs/TabsModel.swift`:

  ```swift
  import Foundation
  import Observation
  import EntityModel

  @Observable
  public final class TabsModel {
      public private(set) var openTabs: [EntityID] = []
      public var selected: EntityID?

      public init() {}

      public func open(_ id: EntityID) {
          if !openTabs.contains(id) { openTabs.append(id) }
          selected = id
      }

      public func close(_ id: EntityID) {
          guard let idx = openTabs.firstIndex(of: id) else { return }
          openTabs.remove(at: idx)
          if selected == id {
              if openTabs.isEmpty { selected = nil }
              else { selected = openTabs[min(idx, openTabs.count - 1)] }
          }
      }
  }
  ```

- [ ] **Step 4: Run tests**

  ⌘U. Expected: 4 TabsModelTests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git commit -m "feat(app): tab strip model"
  ```

---

## Task 11: Markdown text view + wiki-link styling

**Files:**
- Create: `FantasyTavernApp/FantasyTavernApp/Editor/MarkdownTextView.swift`
- Create: `FantasyTavernApp/FantasyTavernApp/Editor/MarkdownStyler.swift`
- Create: `FantasyTavernApp/FantasyTavernAppTests/MarkdownStylerTests.swift`

**Plan 1 editor scope:** plain text editing with **wiki-link pills only** (and cmd-click navigation). Hybrid bold/italic/heading inline rendering will be added as a focused follow-up task within Plan 1 or carried into Plan 2 if time-boxed — call this out at review time.

- [ ] **Step 1: Write failing tests for `MarkdownStyler`**

  `FantasyTavernAppTests/MarkdownStylerTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  import WikiLinks
  @testable import FantasyTavernApp

  final class MarkdownStylerTests: XCTestCase {
      func test_styleAttachesLinkAttributeOnResolvedLinks() {
          let entities = [Entity(id: EntityID("b"), type: .character, name: "B")]
          let resolver = WikiLinkResolver(entities: entities)
          let styled = MarkdownStyler.attributedString(for: "see [[B]] and [[Unknown]]", resolver: resolver)

          // Find ranges of "[[B]]" and "[[Unknown]]" in plain string
          let plain = styled.string
          let bRange = (plain as NSString).range(of: "[[B]]")
          let unknownRange = (plain as NSString).range(of: "[[Unknown]]")

          let resolvedAttr = styled.attribute(.fantasyWikiLink, at: bRange.location, effectiveRange: nil) as? String
          XCTAssertEqual(resolvedAttr, "b")

          let danglingAttr = styled.attribute(.fantasyWikiLinkDangling, at: unknownRange.location, effectiveRange: nil) as? String
          XCTAssertEqual(danglingAttr, "Unknown")
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  ⌘U.

- [ ] **Step 3: Implement `MarkdownStyler`**

  `FantasyTavernApp/FantasyTavernApp/Editor/MarkdownStyler.swift`:

  ```swift
  import AppKit
  import EntityModel
  import WikiLinks

  public extension NSAttributedString.Key {
      static let fantasyWikiLink = NSAttributedString.Key("FantasyWikiLink")          // value: EntityID.rawValue String
      static let fantasyWikiLinkDangling = NSAttributedString.Key("FantasyWikiLinkDangling") // value: name String
  }

  public enum MarkdownStyler {
      public static func attributedString(for body: String, resolver: WikiLinkResolver) -> NSAttributedString {
          let result = NSMutableAttributedString(string: body, attributes: [
              .font: NSFont.systemFont(ofSize: 14),
              .foregroundColor: NSColor.labelColor,
          ])
          for match in WikiLinkParser.findLinks(in: body) {
              guard let nsRange = nsRange(of: match.range, in: body) else { continue }
              if let id = resolver.resolve(name: match.name) {
                  result.addAttributes([
                      .fantasyWikiLink: id.rawValue,
                      .foregroundColor: NSColor.systemBlue,
                      .underlineStyle: NSUnderlineStyle.single.rawValue,
                  ], range: nsRange)
              } else {
                  result.addAttributes([
                      .fantasyWikiLinkDangling: match.name,
                      .foregroundColor: NSColor.systemRed,
                      .underlineStyle: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue,
                  ], range: nsRange)
              }
          }
          return result
      }

      private static func nsRange(of range: Range<String.Index>, in source: String) -> NSRange? {
          NSRange(range, in: source)
      }
  }
  ```

- [ ] **Step 4: Run tests**

  ⌘U. Expected: MarkdownStylerTests passes.

- [ ] **Step 5: Implement `MarkdownTextView` (NSViewRepresentable)**

  `FantasyTavernApp/FantasyTavernApp/Editor/MarkdownTextView.swift`:

  ```swift
  import SwiftUI
  import AppKit
  import EntityModel
  import WikiLinks

  public struct MarkdownTextView: NSViewRepresentable {
      @Binding public var text: String
      public let resolver: WikiLinkResolver
      public let onOpenLink: (EntityID) -> Void

      public init(text: Binding<String>, resolver: WikiLinkResolver, onOpenLink: @escaping (EntityID) -> Void) {
          self._text = text
          self.resolver = resolver
          self.onOpenLink = onOpenLink
      }

      public func makeCoordinator() -> Coordinator { Coordinator(self) }

      public func makeNSView(context: Context) -> NSScrollView {
          let scroll = NSTextView.scrollableTextView()
          let tv = scroll.documentView as! NSTextView
          tv.isRichText = false
          tv.allowsUndo = true
          tv.delegate = context.coordinator
          tv.textStorage?.setAttributedString(MarkdownStyler.attributedString(for: text, resolver: resolver))
          context.coordinator.textView = tv
          let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
          tv.addGestureRecognizer(click)
          return scroll
      }

      public func updateNSView(_ scroll: NSScrollView, context: Context) {
          guard let tv = scroll.documentView as? NSTextView else { return }
          if tv.string != text {
              let selected = tv.selectedRange()
              tv.textStorage?.setAttributedString(MarkdownStyler.attributedString(for: text, resolver: resolver))
              tv.setSelectedRange(NSRange(location: min(selected.location, text.utf16.count), length: 0))
          } else {
              // Re-style in place to refresh link resolution after entity changes.
              tv.textStorage?.setAttributedString(MarkdownStyler.attributedString(for: text, resolver: resolver))
          }
      }

      public final class Coordinator: NSObject, NSTextViewDelegate {
          let parent: MarkdownTextView
          weak var textView: NSTextView?
          init(_ parent: MarkdownTextView) { self.parent = parent }

          public func textDidChange(_ notification: Notification) {
              guard let tv = notification.object as? NSTextView else { return }
              parent.text = tv.string
          }

          @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
              guard let tv = textView else { return }
              let point = gesture.location(in: tv)
              let charIndex = tv.characterIndexForInsertion(at: point)
              guard charIndex < (tv.textStorage?.length ?? 0) else { return }
              if let raw = tv.textStorage?.attribute(.fantasyWikiLink, at: charIndex, effectiveRange: nil) as? String {
                  parent.onOpenLink(EntityID(raw))
              }
          }
      }
  }
  ```

- [ ] **Step 6: Confirm build**

  ⌘B. Expected: clean.

- [ ] **Step 7: Commit**

  ```bash
  git add FantasyTavernApp
  git commit -m "feat(editor): NSTextView wrapper with wiki-link styling + click navigation"
  ```

---

## Task 12: Sidebar + tab bar + editor wired into ContentView

**Files:**
- Modify: `FantasyTavernApp/FantasyTavernApp/FantasyTavernAppApp.swift`
- Modify: `FantasyTavernApp/FantasyTavernApp/ContentView.swift`
- Create: `FantasyTavernApp/FantasyTavernApp/Sidebar/SidebarView.swift`
- Create: `FantasyTavernApp/FantasyTavernApp/Tabs/TabBarView.swift`
- Create: `FantasyTavernApp/FantasyTavernApp/Tabs/EditorTab.swift`
- Create: `FantasyTavernApp/FantasyTavernApp/Editor/EditorView.swift`
- Create: `FantasyTavernApp/FantasyTavernApp/Inspector/InspectorView.swift`
- Create: `FantasyTavernApp/FantasyTavernApp/Commands/AppCommands.swift`

- [ ] **Step 1: App entry point**

  `FantasyTavernAppApp.swift`:

  ```swift
  import SwiftUI

  @main
  struct FantasyTavernAppApp: App {
      @State private var session = WorldSession()
      @State private var tabs = TabsModel()

      var body: some Scene {
          WindowGroup {
              ContentView()
                  .environment(session)
                  .environment(tabs)
          }
          .commands { AppCommands(session: $session, tabs: $tabs) }
      }
  }
  ```

- [ ] **Step 2: ContentView**

  ```swift
  import SwiftUI

  struct ContentView: View {
      @Environment(WorldSession.self) private var session
      @Environment(TabsModel.self) private var tabs

      var body: some View {
          NavigationSplitView {
              SidebarView()
                  .frame(minWidth: 200)
          } detail: {
              VStack(spacing: 0) {
                  TabBarView()
                  Divider()
                  if let id = tabs.selected, let entity = entity(for: id) {
                      HStack(spacing: 0) {
                          EditorView(entity: entity).frame(maxWidth: .infinity, maxHeight: .infinity)
                          Divider()
                          InspectorView(entity: entity).frame(width: 260)
                      }
                  } else {
                      ContentUnavailableView("No tab open", systemImage: "doc.text",
                                             description: Text("Open a character from the sidebar."))
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

- [ ] **Step 3: SidebarView**

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
                      DisclosureGroup("Characters") {
                          ForEach(session.store?.entities(of: .character) ?? [], id: \.id) { entity in
                              Button(entity.name) { tabs.open(entity.id) }
                                  .buttonStyle(.plain)
                          }
                      }
                  }
              } else {
                  ContentUnavailableView("No world open", systemImage: "globe")
              }
          }
          .listStyle(.sidebar)
      }
  }
  ```

- [ ] **Step 4: TabBarView**

  ```swift
  import SwiftUI
  import EntityModel

  struct TabBarView: View {
      @Environment(WorldSession.self) private var session
      @Environment(TabsModel.self) private var tabs

      var body: some View {
          ScrollView(.horizontal) {
              HStack(spacing: 4) {
                  ForEach(tabs.openTabs, id: \.self) { id in
                      EditorTab(id: id, label: name(for: id), isSelected: tabs.selected == id,
                                onSelect: { tabs.selected = id },
                                onClose: { tabs.close(id) })
                  }
              }
              .padding(.horizontal, 8).padding(.vertical, 4)
          }
          .frame(height: 32)
      }

      private func name(for id: EntityID) -> String {
          session.store?.entities.first(where: { $0.id == id })?.name ?? id.rawValue
      }
  }
  ```

- [ ] **Step 5: EditorTab**

  ```swift
  import SwiftUI
  import EntityModel

  struct EditorTab: View {
      let id: EntityID
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

- [ ] **Step 6: EditorView (debounced save)**

  ```swift
  import SwiftUI
  import EntityModel
  import WikiLinks
  import Combine

  struct EditorView: View {
      @Environment(WorldSession.self) private var session
      @Environment(TabsModel.self) private var tabs
      let entity: Entity

      @State private var body: String = ""
      @State private var saveTask: Task<Void, Never>?

      var body: some View {
          VStack(alignment: .leading, spacing: 8) {
              TextField("Name", text: nameBinding)
                  .textFieldStyle(.plain)
                  .font(.title2)
                  .padding(.top, 8).padding(.horizontal, 12)
              Divider()
              MarkdownTextView(
                  text: $body,
                  resolver: WikiLinkResolver(entities: session.store?.entities ?? []),
                  onOpenLink: { tabs.open($0) }
              )
              .onChange(of: body) { _, _ in scheduleSave() }
          }
          .onAppear { body = entity.body }
          .onChange(of: entity.id) { _, _ in body = entity.body }
      }

      private var nameBinding: Binding<String> {
          Binding(get: { entity.name }, set: { new in
              var copy = entity
              copy.name = new
              try? session.save(copy)
          })
      }

      private func scheduleSave() {
          saveTask?.cancel()
          let newBody = body
          let target = entity
          saveTask = Task {
              try? await Task.sleep(nanoseconds: 500_000_000)
              if Task.isCancelled { return }
              var copy = target
              copy.body = newBody
              try? session.save(copy)
          }
      }
  }
  ```

- [ ] **Step 7: InspectorView (backlinks only in Plan 1)**

  ```swift
  import SwiftUI
  import EntityModel

  struct InspectorView: View {
      @Environment(WorldSession.self) private var session
      @Environment(TabsModel.self) private var tabs
      let entity: Entity

      var body: some View {
          VStack(alignment: .leading, spacing: 12) {
              Text("Backlinks").font(.headline)
              let ids = session.backlinks(to: entity.id)
              if ids.isEmpty {
                  Text("No incoming links yet.").foregroundStyle(.secondary).font(.caption)
              } else {
                  ForEach(ids, id: \.self) { id in
                      Button(name(for: id)) { tabs.open(id) }.buttonStyle(.link)
                  }
              }
              Spacer()
          }
          .padding()
      }

      private func name(for id: EntityID) -> String {
          session.store?.entities.first(where: { $0.id == id })?.name ?? id.rawValue
      }
  }
  ```

- [ ] **Step 8: AppCommands (File menu)**

  ```swift
  import SwiftUI
  import UniformTypeIdentifiers

  struct AppCommands: Commands {
      @Binding var session: WorldSession
      @Binding var tabs: TabsModel

      var body: some Commands {
          CommandGroup(replacing: .newItem) {
              Button("Open World…") { openWorld() }
                  .keyboardShortcut("o", modifiers: [.command])
              Button("New Character") { newCharacter() }
                  .keyboardShortcut("n", modifiers: [.command])
                  .disabled(session.store == nil)
          }
      }

      private func openWorld() {
          let panel = NSOpenPanel()
          panel.canChooseDirectories = true
          panel.canChooseFiles = false
          panel.allowsMultipleSelection = false
          if panel.runModal() == .OK, let url = panel.url {
              try? session.openWorld(at: url)
          }
      }

      private func newCharacter() {
          if let entity = try? session.createCharacter(name: "Untitled Character") {
              tabs.open(entity.id)
          }
      }
  }
  ```

- [ ] **Step 9: Build + run**

  ⌘B then ⌘R. Expected: window opens. File → Open World → pick a folder (use a copy of `Packages/WorldStore/Tests/WorldStoreTests/Fixtures/Aetheria/` if no real world yet). Sidebar shows "Aetheria" with characters under it. Clicking a character opens a tab; body editable; `[[Magnus Blackthorn]]` rendered blue; click jumps to Magnus; backlinks pane lists Lyra when viewing Magnus.

- [ ] **Step 10: Commit**

  ```bash
  git add FantasyTavernApp
  git commit -m "feat(app): sidebar + tabs + editor + inspector wired end-to-end"
  ```

---

## Task 13: Manual acceptance & smoke test

**Files:** none.

- [ ] **Step 1: Copy fixture world out to a writable location**

  ```bash
  mkdir -p ~/Documents/FantasyTavern
  cp -R Packages/WorldStore/Tests/WorldStoreTests/Fixtures/Aetheria ~/Documents/FantasyTavern/
  ```

- [ ] **Step 2: Run app and walk through the acceptance flow**

  1. Launch app (⌘R in Xcode).
  2. File → Open World → `~/Documents/FantasyTavern/Aetheria`.
  3. Sidebar shows "Aetheria" → "Characters" → "Lyra Stormwind", "Magnus Blackthorn".
  4. Click "Lyra Stormwind" → opens tab; body contains `Friend of [[Magnus Blackthorn]].` with the link in blue.
  5. Click the `[[Magnus Blackthorn]]` link → Magnus opens in a new tab; backlinks pane on Magnus shows "Lyra Stormwind".
  6. Edit Magnus's body → wait ~1 second → quit and relaunch → confirm edit persists in the file (open the .md in Finder).
  7. File → New Character → name field shows "Untitled Character" → rename it to "Sister Aelith" → confirm a new file `sister-aelith.md` appears in `characters/`.

- [ ] **Step 3: Run all unit tests**

  ```bash
  swift test --package-path Packages/EntityModel
  swift test --package-path Packages/WorldStore
  swift test --package-path Packages/WikiLinks
  ```

  Expected: all green. Run app test target in Xcode: ⌘U on FantasyTavernApp scheme. Expected: green.

- [ ] **Step 4: Commit (no code changes, but tag)**

  ```bash
  git tag plan-1-foundation-complete
  git log --oneline | head -20
  ```

---

## Deferred from Plan 1 (call out at review)

- Hybrid inline rendering for `**bold**`, `*italic*`, headings, lists, strikethrough, code — Plan 1 currently styles wiki-links only. If the user wants this within Plan 1, add a follow-up task batch extending `MarkdownStyler` (regex per token type) and `MarkdownTextView` selection handling.
- `[[` autocomplete popover.
- FSEvents external-edit watcher + conflict banner.
- Multiple worlds, recent-worlds list. Plan 1 keeps a single world at a time, opened via File → Open World each launch.

## Self-Review notes

- Spec coverage check: Plan 1 deliberately scopes to the foundation slice. Other spec sections (search, timeline, maps, snapshots, export, schema-driven fields, six remaining entity types) are tracked by Plans 2–5.
- Placeholder scan: no TBDs / vague tasks. All code blocks complete.
- Type consistency: `EntityID(rawValue:)` / `EntityID(_:)` used consistently; `WorldStore.create(name:type:)`, `save(_:)`, `entities(of:)`, `path(for:)` referenced identically in Tasks 5, 9, 12.
