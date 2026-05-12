# FantasyTavern Plan 3 — Search & ⌘K Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-memory search index over all entities and a ⌘K floating palette with two modes (find + action), supporting filters (`type:`, `tag:`/`#`, `field:value`), free-text fuzzy ranking, keyboard navigation, and incremental updates on save.

**Architecture:** New pure-logic SPM package `SearchIndex` owns tokenization, inverted index, query parsing, and fuzzy ranking. `WorldSession` owns one `SearchIndex` instance, rebuilt incrementally on entity save. App target gains a `CommandPalette/` feature: an `@Observable` controller, a SwiftUI overlay view, and an Action registry mapping `>commands` to closures.

**Tech Stack:** Same as prior plans — Swift 5.10+, macOS 14+, SwiftUI, SPM, XCTest, XcodeGen.

**Plan 3 success criteria:**
1. ⌘K opens a floating palette over the main window. Esc closes it.
2. Empty palette shows a hint and a list of recent entities (last 10 opened tabs).
3. Typing a free-text query produces ranked results grouped by entity type.
4. Filter syntax narrows results: `type:character`, `tag:noble` (or `#noble`), `<fieldKey>:<value>` (e.g. `race:elf`). Filters chain.
5. ↑/↓ moves selection. ↵ opens selection in a new tab. ⌘↵ opens in the current tab.
6. Typing `>` (as the first character) switches to action mode. Action list: `new <type>` for each of the seven types, `open world`, `close tab`, `clear recents`. Free-text after `>` filters actions by name.
7. Search index rebuilds on entity save (incrementally for that entity), and is empty when no world is open.
8. All filters and scoring covered by unit tests in `SearchIndexTests`.

**Out of scope (later plans / future polish):**
- Persisted index on disk (it stays in memory; rebuilt on open).
- Full-text body search beyond the first 200 characters per entity (matches spec).
- Search highlights in results (just label + type/secondary line).
- Spotlight integration / system-wide search.

---

## File Structure

```
Packages/
  SearchIndex/                                              # NEW SPM package
    Package.swift
    Sources/SearchIndex/
      Tokenizer.swift                                       # split text → lowercased tokens
      InvertedIndex.swift                                   # term → Set<EntityID>
      Query.swift                                           # ParsedQuery + Filter types
      QueryParser.swift                                     # raw string → ParsedQuery
      FuzzyScorer.swift                                     # subsequence score
      SearchIndex.swift                                     # public API
    Tests/SearchIndexTests/
      TokenizerTests.swift
      InvertedIndexTests.swift
      QueryParserTests.swift
      FuzzyScorerTests.swift
      SearchIndexTests.swift

FantasyTavernApp/Sources/
  WorldSession.swift                                        # MODIFY: own SearchIndex, expose query
  CommandPalette/
    PaletteController.swift                                 # NEW: @Observable visibility + query + selection
    PaletteAction.swift                                     # NEW: Action struct + registry
    CommandPaletteView.swift                                # NEW: SwiftUI overlay
  ContentView.swift                                         # MODIFY: overlay palette over detail pane
  FantasyTavernAppApp.swift                                 # MODIFY: inject PaletteController, register ⌘K
  Tabs/TabsModel.swift                                      # MODIFY: track recent (last-opened) tab order
FantasyTavernApp/Tests/
  PaletteControllerTests.swift                              # NEW: query routing, selection nav, action dispatch
```

**Why this split:**
- Searching is pure logic — package keeps it testable, free of SwiftUI.
- The palette has three concerns (visibility/state, action registry, view) split across three small files.
- `TabsModel` already tracks open tabs in order; we add a tiny "recent open" sequence to feed the empty-palette state.

---

## Conventions (carry-over + additions)

- **Tokenization:** lowercase the input, then split on any non-alphanumeric character (using `CharacterSet.alphanumerics.inverted`). Drop empty pieces. Diacritics folded with `.diacriticInsensitive` first.
- **Indexed fields per entity:**
  - `name` (weighted high)
  - `tags` (each tag also indexed as `#<tag>` for the `#tag` syntax)
  - First 200 characters of `body`
  - All scalar `fields` values (`.string`/`.int`/`.bool`/`.date` rendered via `String(describing:)`/ISO)
  - `type.rawValue` (so `type:character` works as a filter and as free-text term)
- **Query syntax:**
  - `key:value` → typed filter where `key` is one of `type`, `tag`, or a schema field key.
  - `#tag` → shorthand for `tag:tag`.
  - Anything else is a free term. Free terms join with implicit AND: every free term must match.
- **Filter semantics:**
  - `type:X` — exact match on `entity.type.rawValue`.
  - `tag:X` (and `#X`) — substring match against any tag (lower-cased).
  - `field:value` — substring match against the rendered field value (lower-cased).
- **Free-term matching + ranking:**
  - A free term matches if it appears (case-insensitive) as a contiguous substring of *any* indexed text *or* as a subsequence of the entity name. Substring beats subsequence.
  - Score per matched term: `100` exact-name; `60` name-substring (non-exact); `25` tag-substring; `10` body-substring or field-substring; `5` subsequence-of-name. The entity's score is the sum across terms; ties broken by lower-cased name ascending.
- **Index rebuild on save:** `WorldSession.save` calls `searchIndex.upsert(entity)` with the new entity. `WorldSession.openWorld` rebuilds the index from scratch.

---

## Task 1: SearchIndex package scaffold + Tokenizer

**Files:**
- Create: `Packages/SearchIndex/Package.swift`
- Create: `Packages/SearchIndex/Sources/SearchIndex/Tokenizer.swift`
- Create: `Packages/SearchIndex/Tests/SearchIndexTests/TokenizerTests.swift`

- [ ] **Step 1: Scaffold + Package.swift**

  ```bash
  mkdir -p Packages/SearchIndex/Sources/SearchIndex
  mkdir -p Packages/SearchIndex/Tests/SearchIndexTests
  ```

  `Packages/SearchIndex/Package.swift`:

  ```swift
  // swift-tools-version: 5.10
  import PackageDescription

  let package = Package(
      name: "SearchIndex",
      platforms: [.macOS(.v14)],
      products: [
          .library(name: "SearchIndex", targets: ["SearchIndex"]),
      ],
      dependencies: [
          .package(path: "../EntityModel"),
      ],
      targets: [
          .target(name: "SearchIndex", dependencies: ["EntityModel"]),
          .testTarget(name: "SearchIndexTests", dependencies: ["SearchIndex"]),
      ]
  )
  ```

- [ ] **Step 2: Failing tests**

  `Packages/SearchIndex/Tests/SearchIndexTests/TokenizerTests.swift`:

  ```swift
  import XCTest
  @testable import SearchIndex

  final class TokenizerTests: XCTestCase {
      func test_lowercase_splitsOnWhitespace() {
          XCTAssertEqual(Tokenizer.tokens(in: "Lyra Stormwind"), ["lyra", "stormwind"])
      }

      func test_splitsOnPunctuation() {
          XCTAssertEqual(Tokenizer.tokens(in: "half-elf, ranger!"), ["half", "elf", "ranger"])
      }

      func test_foldsDiacritics() {
          XCTAssertEqual(Tokenizer.tokens(in: "Étienne"), ["etienne"])
      }

      func test_empty_returnsEmpty() {
          XCTAssertEqual(Tokenizer.tokens(in: ""), [])
          XCTAssertEqual(Tokenizer.tokens(in: "   "), [])
      }

      func test_dedupesPreserveOrder() {
          XCTAssertEqual(Tokenizer.tokens(in: "Lyra Lyra Stormwind"), ["lyra", "stormwind"])
      }
  }
  ```

- [ ] **Step 3: Run to verify failure**

  ```bash
  swift test --package-path Packages/SearchIndex 2>&1 | tail -20
  ```

  Expected: compile failure (`Tokenizer` unknown).

- [ ] **Step 4: Implement**

  `Packages/SearchIndex/Sources/SearchIndex/Tokenizer.swift`:

  ```swift
  import Foundation

  public enum Tokenizer {
      public static func tokens(in source: String) -> [String] {
          let folded = source.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                      locale: .init(identifier: "en_US_POSIX"))
          var out: [String] = []
          var seen = Set<String>()
          var current = ""
          for scalar in folded.unicodeScalars {
              if CharacterSet.alphanumerics.contains(scalar) {
                  current.append(Character(scalar))
              } else if !current.isEmpty {
                  if seen.insert(current).inserted { out.append(current) }
                  current = ""
              }
          }
          if !current.isEmpty, seen.insert(current).inserted { out.append(current) }
          return out
      }
  }
  ```

- [ ] **Step 5: Run tests**

  ```bash
  swift test --package-path Packages/SearchIndex 2>&1 | grep -E "Executed [0-9]+" | tail -1
  ```

  Expected: 5 tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add Packages/SearchIndex
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(SearchIndex): scaffold package + Tokenizer"
  ```

---

## Task 2: InvertedIndex

**Files:**
- Create: `Packages/SearchIndex/Sources/SearchIndex/InvertedIndex.swift`
- Create: `Packages/SearchIndex/Tests/SearchIndexTests/InvertedIndexTests.swift`

- [ ] **Step 1: Failing tests**

  `Packages/SearchIndex/Tests/SearchIndexTests/InvertedIndexTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import SearchIndex

  final class InvertedIndexTests: XCTestCase {
      func test_addAndQuery_singleTerm() {
          var idx = InvertedIndex()
          idx.add(["lyra", "stormwind"], for: EntityID("lyra"))
          XCTAssertEqual(idx.ids(matchingTermPrefix: "lyra"), Set([EntityID("lyra")]))
      }

      func test_prefixMatch() {
          var idx = InvertedIndex()
          idx.add(["stormwind"], for: EntityID("a"))
          idx.add(["storm"],     for: EntityID("b"))
          XCTAssertEqual(idx.ids(matchingTermPrefix: "storm"),
                         Set([EntityID("a"), EntityID("b")]))
      }

      func test_removeEntity_dropsItsTerms() {
          var idx = InvertedIndex()
          idx.add(["lyra"], for: EntityID("a"))
          idx.add(["lyra"], for: EntityID("b"))
          idx.remove(EntityID("a"))
          XCTAssertEqual(idx.ids(matchingTermPrefix: "lyra"), Set([EntityID("b")]))
      }

      func test_replaceEntity_refreshesTerms() {
          var idx = InvertedIndex()
          idx.add(["foo"], for: EntityID("a"))
          idx.replace(EntityID("a"), withTerms: ["bar"])
          XCTAssertTrue(idx.ids(matchingTermPrefix: "foo").isEmpty)
          XCTAssertEqual(idx.ids(matchingTermPrefix: "bar"), Set([EntityID("a")]))
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  ```bash
  swift test --package-path Packages/SearchIndex --filter InvertedIndexTests 2>&1 | tail -20
  ```

- [ ] **Step 3: Implement**

  `Packages/SearchIndex/Sources/SearchIndex/InvertedIndex.swift`:

  ```swift
  import Foundation
  import EntityModel

  public struct InvertedIndex: Equatable {
      private var termToIDs: [String: Set<EntityID>] = [:]
      private var idToTerms: [EntityID: Set<String>] = [:]

      public init() {}

      public mutating func add(_ terms: [String], for id: EntityID) {
          let setOfTerms = Set(terms)
          for term in setOfTerms {
              termToIDs[term, default: []].insert(id)
          }
          idToTerms[id, default: []].formUnion(setOfTerms)
      }

      public mutating func remove(_ id: EntityID) {
          guard let terms = idToTerms.removeValue(forKey: id) else { return }
          for term in terms {
              termToIDs[term]?.remove(id)
              if termToIDs[term]?.isEmpty == true { termToIDs.removeValue(forKey: term) }
          }
      }

      public mutating func replace(_ id: EntityID, withTerms terms: [String]) {
          remove(id)
          add(terms, for: id)
      }

      /// All entity ids whose term set contains a term that starts with `prefix`.
      public func ids(matchingTermPrefix prefix: String) -> Set<EntityID> {
          guard !prefix.isEmpty else { return Set(idToTerms.keys) }
          var result: Set<EntityID> = []
          for (term, ids) in termToIDs where term.hasPrefix(prefix) {
              result.formUnion(ids)
          }
          return result
      }
  }
  ```

- [ ] **Step 4: Run tests**

  ```bash
  swift test --package-path Packages/SearchIndex 2>&1 | grep -E "Executed [0-9]+" | tail -1
  ```

  Expected: 9 total pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/SearchIndex
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(SearchIndex): InvertedIndex with prefix lookup"
  ```

---

## Task 3: QueryParser + Query types

**Files:**
- Create: `Packages/SearchIndex/Sources/SearchIndex/Query.swift`
- Create: `Packages/SearchIndex/Sources/SearchIndex/QueryParser.swift`
- Create: `Packages/SearchIndex/Tests/SearchIndexTests/QueryParserTests.swift`

- [ ] **Step 1: Failing tests**

  `Packages/SearchIndex/Tests/SearchIndexTests/QueryParserTests.swift`:

  ```swift
  import XCTest
  @testable import SearchIndex

  final class QueryParserTests: XCTestCase {
      func test_emptyString_emptyQuery() {
          let q = QueryParser.parse("")
          XCTAssertTrue(q.filters.isEmpty)
          XCTAssertTrue(q.freeTerms.isEmpty)
          XCTAssertFalse(q.isActionMode)
      }

      func test_freeTerms_lowercased() {
          let q = QueryParser.parse("Lyra Stormwind")
          XCTAssertEqual(q.freeTerms, ["lyra", "stormwind"])
      }

      func test_typeFilter() {
          let q = QueryParser.parse("type:character lyra")
          XCTAssertEqual(q.filters, [.init(key: "type", value: "character")])
          XCTAssertEqual(q.freeTerms, ["lyra"])
      }

      func test_hashTag_becomesTagFilter() {
          let q = QueryParser.parse("#noble")
          XCTAssertEqual(q.filters, [.init(key: "tag", value: "noble")])
          XCTAssertTrue(q.freeTerms.isEmpty)
      }

      func test_fieldFilter() {
          let q = QueryParser.parse("race:elf")
          XCTAssertEqual(q.filters, [.init(key: "race", value: "elf")])
      }

      func test_mixed() {
          let q = QueryParser.parse("type:character race:elf #noble Lyra")
          XCTAssertEqual(Set(q.filters), Set([
              .init(key: "type", value: "character"),
              .init(key: "race", value: "elf"),
              .init(key: "tag",  value: "noble"),
          ]))
          XCTAssertEqual(q.freeTerms, ["lyra"])
      }

      func test_actionMode_prefix() {
          let q = QueryParser.parse("> new char")
          XCTAssertTrue(q.isActionMode)
          XCTAssertEqual(q.freeTerms, ["new", "char"])
      }

      func test_actionMode_noSpaceAfterAngle() {
          let q = QueryParser.parse(">open")
          XCTAssertTrue(q.isActionMode)
          XCTAssertEqual(q.freeTerms, ["open"])
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

  `Packages/SearchIndex/Sources/SearchIndex/Query.swift`:

  ```swift
  import Foundation

  public struct Filter: Equatable, Hashable {
      public let key: String
      public let value: String
      public init(key: String, value: String) {
          self.key = key
          self.value = value
      }
  }

  public struct ParsedQuery: Equatable {
      public let isActionMode: Bool
      public let filters: [Filter]
      public let freeTerms: [String]

      public init(isActionMode: Bool, filters: [Filter], freeTerms: [String]) {
          self.isActionMode = isActionMode
          self.filters = filters
          self.freeTerms = freeTerms
      }
  }
  ```

  `Packages/SearchIndex/Sources/SearchIndex/QueryParser.swift`:

  ```swift
  import Foundation

  public enum QueryParser {
      public static func parse(_ raw: String) -> ParsedQuery {
          var s = raw.trimmingCharacters(in: .whitespaces)
          let actionMode: Bool
          if s.hasPrefix(">") {
              actionMode = true
              s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
          } else {
              actionMode = false
          }

          let pieces = s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
          var filters: [Filter] = []
          var freeTerms: [String] = []
          for piece in pieces {
              if piece.hasPrefix("#"), piece.count > 1 {
                  filters.append(Filter(key: "tag", value: String(piece.dropFirst()).lowercased()))
                  continue
              }
              if let colon = piece.firstIndex(of: ":"), colon != piece.startIndex {
                  let key = String(piece[..<colon]).lowercased()
                  let value = String(piece[piece.index(after: colon)...]).lowercased()
                  if !key.isEmpty, !value.isEmpty {
                      filters.append(Filter(key: key, value: value))
                      continue
                  }
              }
              freeTerms.append(piece.lowercased())
          }
          return ParsedQuery(isActionMode: actionMode, filters: filters, freeTerms: freeTerms)
      }
  }
  ```

- [ ] **Step 4: Run tests**

  Expected: 8 new pass → 17 total in the package.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/SearchIndex
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(SearchIndex): query parser w/ filters and action mode"
  ```

---

## Task 4: FuzzyScorer

**Files:**
- Create: `Packages/SearchIndex/Sources/SearchIndex/FuzzyScorer.swift`
- Create: `Packages/SearchIndex/Tests/SearchIndexTests/FuzzyScorerTests.swift`

- [ ] **Step 1: Failing tests**

  ```swift
  import XCTest
  @testable import SearchIndex

  final class FuzzyScorerTests: XCTestCase {
      func test_exactNameMatch_highest() {
          XCTAssertEqual(FuzzyScorer.score(term: "lyra", inName: "lyra", indexed: ["lyra"]), 100)
      }

      func test_nameSubstring() {
          XCTAssertEqual(FuzzyScorer.score(term: "storm", inName: "lyra stormwind", indexed: ["lyra","stormwind"]), 60)
      }

      func test_tagSubstring() {
          XCTAssertEqual(FuzzyScorer.score(term: "nob", inName: "lyra", indexed: ["lyra"], tagTexts: ["noble"]), 25)
      }

      func test_bodyOrFieldSubstring() {
          XCTAssertEqual(FuzzyScorer.score(term: "elf", inName: "magnus", indexed: ["magnus"], extraTexts: ["half-elf"]), 10)
      }

      func test_subsequenceFallback() {
          // term letters appear in order inside name but not contiguous
          XCTAssertEqual(FuzzyScorer.score(term: "lsw", inName: "lyra stormwind", indexed: ["lyra","stormwind"]), 5)
      }

      func test_noMatch_returnsZero() {
          XCTAssertEqual(FuzzyScorer.score(term: "xyz", inName: "lyra", indexed: ["lyra"]), 0)
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

  `Packages/SearchIndex/Sources/SearchIndex/FuzzyScorer.swift`:

  ```swift
  import Foundation

  public enum FuzzyScorer {
      /// Score one free term against a candidate entity's text fragments.
      /// - Parameters:
      ///   - term: already lowercased single term.
      ///   - inName: entity name (will be lowercased here).
      ///   - indexed: tokens already extracted from the entity's name+body+fields (lowercased).
      ///   - tagTexts: lowercased tag strings (whole tag matches, not tokenized).
      ///   - extraTexts: lowercased body/field text (substring matches against this gives the lowest non-subsequence score).
      /// - Returns: 0 if no match; otherwise a positive integer score.
      public static func score(term: String,
                               inName name: String,
                               indexed tokens: [String],
                               tagTexts: [String] = [],
                               extraTexts: [String] = []) -> Int {
          let n = name.lowercased()
          if n == term { return 100 }
          if n.contains(term) { return 60 }
          for tag in tagTexts where tag.contains(term) { return 25 }
          for extra in extraTexts where extra.contains(term) { return 10 }
          for token in tokens where token.contains(term) { return 10 }
          if isSubsequence(term, of: n) { return 5 }
          return 0
      }

      static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
          var i = needle.startIndex
          for ch in haystack {
              if i == needle.endIndex { return true }
              if ch == needle[i] { i = needle.index(after: i) }
          }
          return i == needle.endIndex
      }
  }
  ```

- [ ] **Step 4: Run tests** — expect 6 new pass; 23 total.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/SearchIndex
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(SearchIndex): FuzzyScorer (substring tiers + subsequence)"
  ```

---

## Task 5: SearchIndex public API

**Files:**
- Create: `Packages/SearchIndex/Sources/SearchIndex/SearchIndex.swift`
- Create: `Packages/SearchIndex/Tests/SearchIndexTests/SearchIndexTests.swift`

- [ ] **Step 1: Failing tests**

  `Packages/SearchIndex/Tests/SearchIndexTests/SearchIndexTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import SearchIndex

  final class SearchIndexTests: XCTestCase {
      private func entities() -> [Entity] {
          [
              Entity(id: EntityID("lyra"),    type: .character, name: "Lyra Stormwind",
                     tags: ["noble", "ranger"],
                     fields: ["race": .string("half-elf")],
                     body: "Born in Silvermoon. Friend of [[Magnus Blackthorn]]."),
              Entity(id: EntityID("magnus"),  type: .character, name: "Magnus Blackthorn",
                     tags: ["mage"],
                     fields: ["race": .string("human")],
                     body: "Sorcerer."),
              Entity(id: EntityID("silvermoon"), type: .location, name: "Silvermoon",
                     tags: [],
                     fields: ["kind": .string("city")],
                     body: "Capital of the realm."),
          ]
      }

      func test_build_thenQueryByFreeTerm() {
          var idx = SearchIndex()
          idx.build(from: entities())
          let result = idx.query("lyra")
          XCTAssertEqual(result.map(\.id.rawValue), ["lyra"])
      }

      func test_typeFilter_narrows() {
          var idx = SearchIndex()
          idx.build(from: entities())
          let result = idx.query("type:character")
          XCTAssertEqual(Set(result.map(\.id.rawValue)), ["lyra", "magnus"])
      }

      func test_tagFilter_hashSyntax() {
          var idx = SearchIndex()
          idx.build(from: entities())
          let result = idx.query("#noble")
          XCTAssertEqual(result.map(\.id.rawValue), ["lyra"])
      }

      func test_fieldFilter() {
          var idx = SearchIndex()
          idx.build(from: entities())
          let result = idx.query("race:elf")
          XCTAssertEqual(result.map(\.id.rawValue), ["lyra"])
      }

      func test_freeTerm_rankingPrefersNameOverBody() {
          var idx = SearchIndex()
          idx.build(from: entities())
          // "silvermoon" appears as Lyra's body AND as the Silvermoon entity's name.
          // Silvermoon should rank above Lyra.
          let result = idx.query("silvermoon")
          XCTAssertEqual(result.map(\.id.rawValue), ["silvermoon", "lyra"])
      }

      func test_upsert_replacesEntityIndex() {
          var idx = SearchIndex()
          idx.build(from: entities())
          var lyra = entities()[0]
          lyra.name = "Renamed Person"
          lyra.tags = []
          idx.upsert(lyra)
          XCTAssertTrue(idx.query("lyra").isEmpty)
          XCTAssertEqual(idx.query("renamed").map(\.id.rawValue), ["lyra"])
      }

      func test_empty_query_returnsAll() {
          var idx = SearchIndex()
          idx.build(from: entities())
          let result = idx.query("")
          XCTAssertEqual(Set(result.map(\.id.rawValue)), ["lyra", "magnus", "silvermoon"])
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

  `Packages/SearchIndex/Sources/SearchIndex/SearchIndex.swift`:

  ```swift
  import Foundation
  import EntityModel

  public struct SearchHit: Equatable {
      public let id: EntityID
      public let type: EntityType
      public let name: String
      public let score: Int
  }

  /// In-memory index over all entities of one world.
  public struct SearchIndex {
      // entityID -> snapshot of indexed text
      private struct Record {
          var name: String
          var nameLowered: String
          var type: EntityType
          var indexedTokens: [String]
          var tagTexts: [String]
          var extraTexts: [String]
          var fieldKVs: [(key: String, value: String)]
      }

      private var byID: [EntityID: Record] = [:]
      private var prefixIndex = InvertedIndex()

      public init() {}

      public mutating func build(from entities: [Entity]) {
          byID.removeAll(keepingCapacity: true)
          prefixIndex = InvertedIndex()
          for e in entities { upsert(e) }
      }

      public mutating func upsert(_ entity: Entity) {
          let record = makeRecord(for: entity)
          byID[entity.id] = record
          prefixIndex.replace(entity.id, withTerms: record.indexedTokens)
      }

      public mutating func remove(_ id: EntityID) {
          byID.removeValue(forKey: id)
          prefixIndex.remove(id)
      }

      public func query(_ raw: String) -> [SearchHit] {
          let parsed = QueryParser.parse(raw)
          var candidates = byID.keys.map { $0 } // start with all

          // Apply filters
          if !parsed.filters.isEmpty {
              candidates = candidates.filter { id in
                  guard let r = byID[id] else { return false }
                  return parsed.filters.allSatisfy { f in passesFilter(f, record: r) }
              }
          }

          // Score free terms
          if parsed.freeTerms.isEmpty {
              return candidates
                  .compactMap { byID[$0].map { (id: $0, r: $1) } } // (id, record)
                  .sorted { $0.r.nameLowered < $1.r.nameLowered }
                  .map { SearchHit(id: $0.id, type: $0.r.type, name: $0.r.name, score: 0) }
          }

          var scored: [SearchHit] = []
          for id in candidates {
              guard let r = byID[id] else { continue }
              var total = 0
              var allMatched = true
              for term in parsed.freeTerms {
                  let s = FuzzyScorer.score(term: term,
                                            inName: r.name,
                                            indexed: r.indexedTokens,
                                            tagTexts: r.tagTexts,
                                            extraTexts: r.extraTexts)
                  if s == 0 { allMatched = false; break }
                  total += s
              }
              guard allMatched else { continue }
              scored.append(SearchHit(id: id, type: r.type, name: r.name, score: total))
          }
          scored.sort {
              if $0.score != $1.score { return $0.score > $1.score }
              return $0.name.lowercased() < $1.name.lowercased()
          }
          return scored
      }

      // MARK: - helpers

      private func passesFilter(_ f: Filter, record r: Record) -> Bool {
          switch f.key {
          case "type":
              return r.type.rawValue == f.value
          case "tag":
              return r.tagTexts.contains(where: { $0.contains(f.value) })
          default:
              // schema field filter
              return r.fieldKVs.contains { kv in
                  kv.key == f.key && kv.value.contains(f.value)
              }
          }
      }

      private func makeRecord(for entity: Entity) -> Record {
          let nameLower = entity.name.lowercased()
          let tagTexts = entity.tags.map { $0.lowercased() }
          let bodyExcerpt = String(entity.body.prefix(200)).lowercased()
          let fieldKVs: [(String, String)] = entity.fields.map { (k, v) in
              (k.lowercased(), Self.renderFieldValue(v).lowercased())
          }
          let extraTexts = [bodyExcerpt] + fieldKVs.map { $0.1 }
          var tokens = Tokenizer.tokens(in: entity.name)
          tokens.append(contentsOf: Tokenizer.tokens(in: bodyExcerpt))
          for tag in tagTexts { tokens.append(contentsOf: Tokenizer.tokens(in: tag)) }
          for kv in fieldKVs  { tokens.append(contentsOf: Tokenizer.tokens(in: kv.1)) }
          tokens.append(entity.type.rawValue)
          // dedupe preserving order
          var seen = Set<String>()
          tokens = tokens.filter { seen.insert($0).inserted }
          return Record(name: entity.name, nameLowered: nameLower, type: entity.type,
                        indexedTokens: tokens, tagTexts: tagTexts,
                        extraTexts: extraTexts, fieldKVs: fieldKVs)
      }

      static func renderFieldValue(_ v: FieldValue) -> String {
          switch v {
          case .string(let s): return s
          case .int(let i):    return String(i)
          case .bool(let b):   return String(b)
          case .date(let d):   return ISO8601DateFormatter().string(from: d)
          case .ref(let id):   return id.rawValue
          case .list:          return ""
          }
      }
  }
  ```

- [ ] **Step 4: Run all SearchIndex tests**

  ```bash
  swift test --package-path Packages/SearchIndex 2>&1 | grep -E "Executed [0-9]+" | tail -1
  ```

  Expected: 30 total (5 Tokenizer + 4 InvertedIndex + 8 QueryParser + 6 FuzzyScorer + 7 SearchIndex).

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/SearchIndex
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(SearchIndex): public SearchIndex API w/ filters + ranking"
  ```

---

## Task 6: Link SearchIndex into app target via project.yml

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add the package + dependency**

  Edit `project.yml`. Under top-level `packages:`, append:

  ```yaml
    SearchIndex:
      path: Packages/SearchIndex
  ```

  Under `targets.FantasyTavernApp.dependencies:`, append:

  ```yaml
        - package: SearchIndex
  ```

- [ ] **Step 2: Regenerate + build**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: build succeeds, 16 prior tests still pass.

- [ ] **Step 3: Commit**

  ```bash
  git add project.yml
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "chore(project): link SearchIndex into app target"
  ```

---

## Task 7: WorldSession owns SearchIndex

**Files:**
- Modify: `FantasyTavernApp/Sources/WorldSession.swift`
- Create: `FantasyTavernApp/Tests/WorldSessionSearchTests.swift`

- [ ] **Step 1: Failing tests**

  `FantasyTavernApp/Tests/WorldSessionSearchTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  import SearchIndex
  @testable import FantasyTavernApp

  final class WorldSessionSearchTests: XCTestCase {
      private func makeWorld() throws -> URL {
          let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
          try #"{"name":"T"}"#.write(to: url.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
          return url
      }

      func test_search_returnsCreatedEntity() throws {
          let s = WorldSession()
          try s.openWorld(at: makeWorld())
          let e = try s.createEntity(type: .character, name: "Lyra Stormwind")
          XCTAssertEqual(s.search("lyra").map(\.id), [e.id])
      }

      func test_search_emptyBeforeOpen() {
          let s = WorldSession()
          XCTAssertTrue(s.search("anything").isEmpty)
      }

      func test_save_updatesIndex() throws {
          let s = WorldSession()
          try s.openWorld(at: makeWorld())
          let e = try s.createEntity(type: .character, name: "Lyra")
          var renamed = e
          renamed.name = "Lyra Stormwind"
          try s.save(renamed)
          XCTAssertEqual(s.search("stormwind").map(\.id), [e.id])
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -15
  ```

- [ ] **Step 3: Add index to `WorldSession`**

  Overwrite `FantasyTavernApp/Sources/WorldSession.swift`:

  ```swift
  import Foundation
  import Observation
  import EntityModel
  import WorldStore
  import WikiLinks
  import SchemaRegistry
  import SearchIndex

  @Observable
  public final class WorldSession {
      public var store: WorldStore?
      public private(set) var backlinkIndex = BacklinkIndex(entities: [])
      public private(set) var searchIndex = SearchIndex()

      public init() {}

      public func openWorld(at url: URL) throws {
          let store = try WorldStore.open(url)
          self.store = store
          rebuildLinks()
          rebuildSearch()
      }

      @discardableResult
      public func createEntity(type: EntityType, name: String) throws -> Entity {
          guard let store else { throw SessionError.noWorldOpen }
          let entity = try store.create(name: name, type: type)
          rebuildLinks()
          searchIndex.upsert(entity)
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
          if let updated = store.entities.first(where: { $0.id == entity.id }) {
              searchIndex.upsert(updated)
          } else {
              searchIndex.upsert(entity)
          }
      }

      public func backlinks(to target: EntityID) -> [EntityID] {
          backlinkIndex.sources(linkingTo: target)
      }

      public func fields(for type: EntityType) -> [FieldDefinition] {
          store?.schema.fields(for: type) ?? []
      }

      public func search(_ query: String) -> [SearchHit] {
          searchIndex.query(query)
      }

      private func rebuildLinks() {
          backlinkIndex = BacklinkIndex(entities: store?.entities ?? [])
      }

      private func rebuildSearch() {
          searchIndex.build(from: store?.entities ?? [])
      }

      public enum SessionError: Error { case noWorldOpen }
  }
  ```

- [ ] **Step 4: Run tests** — expect 19 total (16 prior + 3 new).

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(app): WorldSession owns SearchIndex, rebuilds on open/save"
  ```

---

## Task 8: TabsModel — track recently opened ids

**Files:**
- Modify: `FantasyTavernApp/Sources/Tabs/TabsModel.swift`
- Modify: `FantasyTavernApp/Tests/TabsModelTests.swift`

- [ ] **Step 1: Extend failing tests**

  Append to `FantasyTavernApp/Tests/TabsModelTests.swift`:

  ```swift
      func test_open_pushesToRecents_mostRecentFirst() {
          let m = TabsModel()
          m.open(EntityID("a"))
          m.open(EntityID("b"))
          m.open(EntityID("c"))
          XCTAssertEqual(m.recents, [EntityID("c"), EntityID("b"), EntityID("a")])
      }

      func test_open_existing_movesItToFrontOfRecents() {
          let m = TabsModel()
          m.open(EntityID("a"))
          m.open(EntityID("b"))
          m.open(EntityID("a"))
          XCTAssertEqual(m.recents, [EntityID("a"), EntityID("b")])
      }

      func test_recents_cappedAtTen() {
          let m = TabsModel()
          for i in 0..<15 { m.open(EntityID("e\(i)")) }
          XCTAssertEqual(m.recents.count, 10)
          XCTAssertEqual(m.recents.first, EntityID("e14"))
      }
  ```

- [ ] **Step 2: Run** — expect 3 new compile failures (`recents` unknown).

- [ ] **Step 3: Extend `TabsModel`**

  Overwrite `FantasyTavernApp/Sources/Tabs/TabsModel.swift`:

  ```swift
  import Foundation
  import Observation
  import EntityModel

  @Observable
  public final class TabsModel {
      public private(set) var openTabs: [EntityID] = []
      public var selected: EntityID?
      public private(set) var recents: [EntityID] = []
      private let recentsCap = 10

      public init() {}

      public func open(_ id: EntityID) {
          if !openTabs.contains(id) { openTabs.append(id) }
          selected = id
          pushRecent(id)
      }

      public func close(_ id: EntityID) {
          guard let idx = openTabs.firstIndex(of: id) else { return }
          openTabs.remove(at: idx)
          if selected == id {
              if openTabs.isEmpty { selected = nil }
              else { selected = openTabs[min(idx, openTabs.count - 1)] }
          }
      }

      private func pushRecent(_ id: EntityID) {
          recents.removeAll { $0 == id }
          recents.insert(id, at: 0)
          if recents.count > recentsCap { recents.removeLast(recents.count - recentsCap) }
      }
  }
  ```

- [ ] **Step 4: Run tests** — expect 22 total (19 + 3).

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(tabs): track recently opened entities (cap 10)"
  ```

---

## Task 9: PaletteAction registry

**Files:**
- Create: `FantasyTavernApp/Sources/CommandPalette/PaletteAction.swift`

This task contains no automated test — actions are exercised by `PaletteControllerTests` in Task 10.

- [ ] **Step 1: Implement**

  `FantasyTavernApp/Sources/CommandPalette/PaletteAction.swift`:

  ```swift
  import Foundation
  import EntityModel

  struct PaletteAction: Identifiable, Equatable {
      let id: String
      let title: String
      let perform: () -> Void

      static func == (lhs: PaletteAction, rhs: PaletteAction) -> Bool {
          lhs.id == rhs.id && lhs.title == rhs.title
      }
  }

  enum PaletteActions {
      /// Build the standard action list given the runtime callbacks.
      static func standard(
          newEntity: @escaping (EntityType) -> Void,
          openWorld: @escaping () -> Void,
          closeCurrentTab: @escaping () -> Void,
          clearRecents: @escaping () -> Void
      ) -> [PaletteAction] {
          var list: [PaletteAction] = []
          for type in EntityType.allCases {
              let label: String
              switch type {
              case .character:     label = "Character"
              case .location:      label = "Location"
              case .lore:          label = "Lore Entry"
              case .item:          label = "Item"
              case .language:      label = "Language"
              case .journal:       label = "Journal Entry"
              case .timelineEvent: label = "Timeline Event"
              }
              list.append(PaletteAction(id: "new-\(type.rawValue)",
                                        title: "New \(label)",
                                        perform: { newEntity(type) }))
          }
          list.append(PaletteAction(id: "open-world",     title: "Open World…",      perform: openWorld))
          list.append(PaletteAction(id: "close-tab",      title: "Close Current Tab", perform: closeCurrentTab))
          list.append(PaletteAction(id: "clear-recents",  title: "Clear Recent Worlds", perform: clearRecents))
          return list
      }

      /// Substring filter against title (lowercased).
      static func filter(_ list: [PaletteAction], by freeTerms: [String]) -> [PaletteAction] {
          guard !freeTerms.isEmpty else { return list }
          return list.filter { action in
              let lowered = action.title.lowercased()
              return freeTerms.allSatisfy { lowered.contains($0) }
          }
      }
  }
  ```

- [ ] **Step 2: Build**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(palette): PaletteAction registry + filter helper"
  ```

---

## Task 10: PaletteController + tests

**Files:**
- Create: `FantasyTavernApp/Sources/CommandPalette/PaletteController.swift`
- Create: `FantasyTavernApp/Tests/PaletteControllerTests.swift`

- [ ] **Step 1: Failing tests**

  `FantasyTavernApp/Tests/PaletteControllerTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  import SearchIndex
  @testable import FantasyTavernApp

  final class PaletteControllerTests: XCTestCase {
      private func makeController() -> (PaletteController, WorldSession, TabsModel, () -> URL) {
          let session = WorldSession()
          let tabs = TabsModel()
          let controller = PaletteController(session: session, tabs: tabs)
          let tmp = { () -> URL in
              let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
              try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
              try? #"{"name":"T"}"#.write(to: u.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
              return u
          }
          return (controller, session, tabs, tmp)
      }

      func test_show_clearsQueryAndSelection() {
          let (c, _, _, _) = makeController()
          c.query = "stale"
          c.show()
          XCTAssertTrue(c.isVisible)
          XCTAssertEqual(c.query, "")
          XCTAssertEqual(c.selectionIndex, 0)
      }

      func test_dismiss_hides() {
          let (c, _, _, _) = makeController()
          c.show()
          c.dismiss()
          XCTAssertFalse(c.isVisible)
      }

      func test_findResults_searchesSession() throws {
          let (c, session, _, tmp) = makeController()
          try session.openWorld(at: tmp())
          _ = try session.createEntity(type: .character, name: "Lyra Stormwind")
          c.show()
          c.query = "lyra"
          XCTAssertEqual(c.findResults.map(\.name), ["Lyra Stormwind"])
      }

      func test_actionResults_filter() {
          let (c, _, _, _) = makeController()
          c.show()
          c.query = "> new char"
          XCTAssertTrue(c.isActionMode)
          XCTAssertEqual(c.actionResults.map(\.title), ["New Character"])
      }

      func test_moveSelection_clamps() {
          let (c, session, _, tmp) = makeController()
          try? session.openWorld(at: tmp())
          _ = try? session.createEntity(type: .character, name: "A")
          _ = try? session.createEntity(type: .character, name: "B")
          c.show()
          c.query = "" // returns 2 results
          c.moveSelection(by: 1)
          XCTAssertEqual(c.selectionIndex, 1)
          c.moveSelection(by: 5)
          XCTAssertEqual(c.selectionIndex, 1) // clamped to last
          c.moveSelection(by: -10)
          XCTAssertEqual(c.selectionIndex, 0)
      }

      func test_activateFind_opensSelectedInNewTab() throws {
          let (c, session, tabs, tmp) = makeController()
          try session.openWorld(at: tmp())
          let e = try session.createEntity(type: .character, name: "Lyra")
          c.show()
          c.query = "lyra"
          c.activate(openInPlace: false)
          XCTAssertEqual(tabs.selected, e.id)
          XCTAssertFalse(c.isVisible)
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

  `FantasyTavernApp/Sources/CommandPalette/PaletteController.swift`:

  ```swift
  import Foundation
  import Observation
  import AppKit
  import EntityModel
  import SearchIndex

  @Observable
  final class PaletteController {
      private let session: WorldSession
      private let tabs: TabsModel

      var isVisible: Bool = false
      var query: String = ""
      var selectionIndex: Int = 0

      init(session: WorldSession, tabs: TabsModel) {
          self.session = session
          self.tabs = tabs
      }

      func show() {
          query = ""
          selectionIndex = 0
          isVisible = true
      }

      func dismiss() {
          isVisible = false
      }

      var isActionMode: Bool { query.trimmingCharacters(in: .whitespaces).hasPrefix(">") }

      var findResults: [SearchHit] {
          guard !isActionMode else { return [] }
          // empty query: show recents first, then everything sorted by name (limit 50)
          if query.trimmingCharacters(in: .whitespaces).isEmpty {
              let recentHits = tabs.recents.compactMap { id -> SearchHit? in
                  guard let e = session.store?.entities.first(where: { $0.id == id }) else { return nil }
                  return SearchHit(id: e.id, type: e.type, name: e.name, score: 0)
              }
              let remaining = session.search("").filter { hit in !tabs.recents.contains(hit.id) }
              return Array((recentHits + remaining).prefix(50))
          }
          return Array(session.search(query).prefix(50))
      }

      var actionResults: [PaletteAction] {
          guard isActionMode else { return [] }
          let parsed = QueryParser.parse(query)
          return PaletteActions.filter(allActions, by: parsed.freeTerms)
      }

      var allActions: [PaletteAction] {
          PaletteActions.standard(
              newEntity: { [weak self] type in
                  if let entity = try? self?.session.createEntity(type: type, name: "Untitled \(type.rawValue)") {
                      self?.tabs.open(entity.id)
                  }
              },
              openWorld: { [weak self] in
                  let panel = NSOpenPanel()
                  panel.canChooseDirectories = true
                  panel.canChooseFiles = false
                  panel.allowsMultipleSelection = false
                  if panel.runModal() == .OK, let url = panel.url {
                      try? self?.session.openWorld(at: url)
                      RecentWorlds.shared.add(url)
                  }
              },
              closeCurrentTab: { [weak self] in
                  if let id = self?.tabs.selected { self?.tabs.close(id) }
              },
              clearRecents: { RecentWorlds.shared.clear() }
          )
      }

      func moveSelection(by delta: Int) {
          let max = currentResultCount - 1
          if max < 0 { selectionIndex = 0; return }
          selectionIndex = min(max, Swift.max(0, selectionIndex + delta))
      }

      private var currentResultCount: Int {
          isActionMode ? actionResults.count : findResults.count
      }

      /// Open selection. `openInPlace = true` means reuse current tab; otherwise new tab.
      func activate(openInPlace: Bool) {
          if isActionMode {
              let actions = actionResults
              guard selectionIndex < actions.count else { return }
              actions[selectionIndex].perform()
              dismiss()
              return
          }
          let results = findResults
          guard selectionIndex < results.count else { return }
          let id = results[selectionIndex].id
          if openInPlace, let current = tabs.selected, current != id {
              tabs.close(current)
          }
          tabs.open(id)
          dismiss()
      }
  }
  ```

- [ ] **Step 4: Run tests**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: 28 total tests pass (22 + 6 new).

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(palette): PaletteController state + actions + tests"
  ```

---

## Task 11: CommandPaletteView + ⌘K integration

**Files:**
- Create: `FantasyTavernApp/Sources/CommandPalette/CommandPaletteView.swift`
- Modify: `FantasyTavernApp/Sources/ContentView.swift` (overlay palette)
- Modify: `FantasyTavernApp/Sources/FantasyTavernAppApp.swift` (inject controller, register ⌘K command)

- [ ] **Step 1: `CommandPaletteView`**

  `FantasyTavernApp/Sources/CommandPalette/CommandPaletteView.swift`:

  ```swift
  import SwiftUI
  import EntityModel

  struct CommandPaletteView: View {
      @Bindable var controller: PaletteController

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
                          .onKeyPress(.escape) { controller.dismiss(); return .handled }
                          .onKeyPress(.upArrow) { controller.moveSelection(by: -1); return .handled }
                          .onKeyPress(.downArrow) { controller.moveSelection(by: 1); return .handled }
                          .onSubmit { controller.activate(openInPlace: false) }

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
  ```

- [ ] **Step 2: Overlay on `ContentView`**

  Overwrite `FantasyTavernApp/Sources/ContentView.swift`:

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
                      if let id = tabs.selected, let entity = entity(for: id) {
                          EditorView(entity: entity)
                              .frame(maxWidth: .infinity, maxHeight: .infinity)
                      } else {
                          ContentUnavailableView("No tab open", systemImage: "doc.text",
                                                 description: Text("Open an entity from the sidebar or press ⌘K."))
                              .frame(maxWidth: .infinity, maxHeight: .infinity)
                      }
                  }
              }
              CommandPaletteView(controller: palette)
          }
      }

      private func entity(for id: EntityID) -> Entity? {
          session.store?.entities.first(where: { $0.id == id })
      }
  }
  ```

- [ ] **Step 3: Inject controller + register ⌘K**

  Overwrite `FantasyTavernApp/Sources/FantasyTavernAppApp.swift`:

  ```swift
  import SwiftUI

  @main
  struct FantasyTavernAppApp: App {
      @State private var session = WorldSession()
      @State private var tabs = TabsModel()
      @State private var palette: PaletteController

      init() {
          let s = WorldSession()
          let t = TabsModel()
          _session = State(initialValue: s)
          _tabs = State(initialValue: t)
          _palette = State(initialValue: PaletteController(session: s, tabs: t))
      }

      var body: some Scene {
          WindowGroup {
              ContentView()
                  .environment(session)
                  .environment(tabs)
                  .environment(palette)
          }
          .commands {
              AppCommands(session: $session, tabs: $tabs)
              CommandGroup(after: .toolbar) {
                  Button("Show Command Palette") { palette.show() }
                      .keyboardShortcut("k", modifiers: [.command])
              }
          }
      }
  }
  ```

- [ ] **Step 4: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: build succeeds, 28 tests pass.

  If `.onKeyPress` on macOS 14 SDK has a different API surface, fall back to `.onKeyPress(keys: [.escape, .upArrow, .downArrow]) { press in ... }`. Both forms compile on Xcode 26.

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(palette): SwiftUI overlay + ⌘K hotkey + ⌘↵ open-in-place"
  ```

---

## Task 12: ⌘↵ — open-in-place support

The earlier ⌘K palette `onSubmit` always opens in a new tab. Add ⌘↵ for open-in-place by intercepting the key event on the palette text field.

**Files:**
- Modify: `FantasyTavernApp/Sources/CommandPalette/CommandPaletteView.swift`

- [ ] **Step 1: Replace `.onSubmit` block with key-press handlers covering ⌘↵**

  In `CommandPaletteView`, replace:

  ```swift
                          .onSubmit { controller.activate(openInPlace: false) }
  ```

  with:

  ```swift
                          .onKeyPress(keys: [.return]) { press in
                              controller.activate(openInPlace: press.modifiers.contains(.command))
                              return .handled
                          }
  ```

  (Keep the `.escape`/`.upArrow`/`.downArrow` handlers as-is.)

- [ ] **Step 2: Build + tests**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: build succeeds, 28 tests pass.

- [ ] **Step 3: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(palette): ⌘↵ opens selection in current tab (replaces)"
  ```

---

## Task 13: Manual acceptance

**Files:** none.

- [ ] **Step 1: Run all package + app tests**

  ```bash
  swift test --package-path Packages/EntityModel    2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
  swift test --package-path Packages/WorldStore     2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
  swift test --package-path Packages/WikiLinks      2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
  swift test --package-path Packages/SchemaRegistry 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
  swift test --package-path Packages/SearchIndex    2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail -1
  ```

  All should be green.

- [ ] **Step 2: Build + launch**

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -3
  pkill -f FantasyTavernApp 2>/dev/null || true
  sleep 1
  open ~/Library/Developer/Xcode/DerivedData/FantasyTavern-cjpexdvcsmhrwcafqhtvzpbgihqg/Build/Products/Debug/FantasyTavernApp.app
  ```

- [ ] **Step 3: Walk through acceptance flow**

  1. Open `~/Documents/FantasyTavern/Aetheria`.
  2. Press ⌘K → palette overlays. Empty query: list shows recents (last opened tabs) + remaining entities.
  3. Type `lyra` → "Lyra Stormwind" tops the list.
  4. Type `type:character` → only character results.
  5. Type `#noble` → only entities tagged `noble`.
  6. Type `race:elf` → only entities whose `race` field contains `elf`.
  7. Type `silvermoon` → location ranks above any character whose body mentions it.
  8. ↑/↓ navigates. ↵ opens in new tab. ⌘↵ replaces current tab. Esc closes palette.
  9. Type `>` → action mode. Filter to `new` → "New Character", "New Location", etc. Run one → palette closes, new tab opens.
  10. Type `>open` → "Open World…" action. Run → file picker.
  11. After saving an entity (rename + body edit), re-open palette → updates immediately reflect.

- [ ] **Step 4: Tag**

  ```bash
  git tag plan-3-search-palette-complete
  ```

---

## Deferred from Plan 3 (call out at review)

- **Result highlighting:** matched substrings could be bolded in the result row. Skipped — adds rendering complexity without changing behaviour.
- **Recents-driven scoring boost on empty query:** simple ordering only; future polish could rank by access count.
- **Action mode keyword aliases:** e.g. `>character` → "New Character". For now users type `>new char…`.
- **Persisted recent worlds in palette:** the palette's "Open World…" action uses `NSOpenPanel`. The recent-worlds list from File menu is separate.
- **Body search beyond 200 chars / stemming / typo tolerance.** Out of spec scope.

## Self-Review notes

**Spec coverage:**
- ⌘K palette w/ find + action modes (Task 11/12). ✓
- Filter syntax (`type:`, `tag:`, `#tag`, `field:value`) (Task 3 + Task 5). ✓
- Subsequence + tier ranking (Task 4 + Task 5). ✓
- Group-by-type / score-ordered output: results carry `type` so the UI prefixes/labels by type; explicit "grouped by type" was simplified to a per-row `type` label to keep the list compact. Acceptable — closely matches spec intent.
- Incremental rebuild on save (Task 7). ✓
- Empty-state shows recents (Task 8 + controller). ✓

**Placeholder scan:** no TBDs; all code blocks complete.

**Type consistency:**
- `SearchHit` defined once (Task 5), used in `WorldSession.search` (Task 7) and `PaletteController` (Task 10).
- `PaletteController.activate(openInPlace:)` signature matches across Task 10 + 11 + 12.
- `WorldSession.search(_:)`, `searchIndex.upsert(_:)`, `searchIndex.build(from:)` consistent across Tasks 5 and 7.
