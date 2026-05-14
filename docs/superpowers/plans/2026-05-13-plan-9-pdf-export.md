# FantasyTavern Plan 9 — PDF Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a File → Export → PDF submenu that writes either the current entity or the whole world to a user-chosen PDF file. Layout is a simple letter-size book: world title cover, then a section per entity type with each entity as a sub-heading + body.

**Architecture:**
- Pure-logic `PDFContent` builds an `NSAttributedString` from a `World` + `[Entity]`, applying heading/body styles. Easy to test against substring expectations.
- `PDFExporter` hosts an offscreen `NSTextView` sized to letter pages and runs `NSPrintOperation` configured to save directly as PDF (no dialog).
- `AppCommands` gets two new menu items inside the existing `Export` submenu: `PDF — Current Entity…` and `PDF — Whole World…`.

**Tech Stack:** Same as prior plans — Swift 5.10+, macOS 14+, SwiftUI, AppKit (`NSPrintOperation`, `NSTextView`, `NSPrintInfo`), XCTest. No new SPM packages.

**Plan 9 success criteria:**
1. With an entity tab focused, File → Export → PDF — Current Entity… opens a save panel defaulting to `<entityID>.pdf`. Saving writes a single-PDF document containing the entity's name (heading), type label (caption), and body.
2. File → Export → PDF — Whole World… opens save panel defaulting to `<worldName>.pdf`. Writes a multi-page PDF: world title cover; for each entity type with at least one entity, a section heading + each entity as sub-heading + body.
3. PDF is readable in Preview.app w/ proper page breaks and selectable text.
4. Existing markdown export untouched.
5. New unit tests cover `PDFContent` substring assertions (title/type-heading/entity-name in attributed string).

**Out of scope (later polish):**
- Custom typography / themes.
- Cover image.
- Wiki-link cross-references rendered as PDF hyperlinks.
- Inline markdown styling beyond plain body text (bold/italic/headings deferred — body renders as plain paragraph).
- Tables, images embedded in body.

---

## File Structure

```
FantasyTavernApp/Sources/
  Export/
    PDFContent.swift                 # NEW: builds NSAttributedString from world + entities
    PDFExporter.swift                # NEW: NSPrintOperation save-to-PDF wrapper
  Commands/AppCommands.swift         # MODIFY: add two PDF export menu items
FantasyTavernApp/Tests/
  PDFContentTests.swift              # NEW: substring assertions on attributed string
```

**Why this split:**
- `PDFContent` is pure logic over an `NSAttributedString`; easy to test without running a print operation.
- `PDFExporter` is the only file touching `NSPrintOperation`; keeps platform glue in one place.
- AppCommands stays declarative — just adds menu items pointing at `PDFExporter` calls.

---

## Conventions (carry-over + additions)

- **Page size:** US Letter (`612 × 792` pt), margins 0.5 inch (`36` pt) on all sides.
- **Fonts:** title 32pt bold; type heading 22pt bold; entity name 16pt bold; body 12pt regular. System font throughout.
- **Spacing:** 16pt above type-heading sections; 8pt above entity name; 4pt above body.
- **Entity type ordering on world export:** matches `EntityType.allCases` order from `EntityModel` (character → location → lore → item → language → journal → timelineEvent).
- **Filename defaults:** entity export = `<entity.id.rawValue>.pdf`; world export = `<world.name>.pdf` (no slugging — let user rename in panel).
- **Save panel content type:** `.pdf` (UTType from `UniformTypeIdentifiers`).

---

## Task 1: PDFContent — pure attributed-string builder

**Files:**
- Create: `FantasyTavernApp/Sources/Export/PDFContent.swift`
- Create: `FantasyTavernApp/Tests/PDFContentTests.swift`

- [ ] **Step 1: Failing tests**

  `FantasyTavernApp/Tests/PDFContentTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  import WorldStore
  @testable import FantasyTavernApp

  final class PDFContentTests: XCTestCase {
      private func sampleWorld() -> World {
          World(name: "Aetheria", folder: URL(fileURLWithPath: "/tmp/world"), color: nil)
      }

      func test_entityDocument_includesNameAndBody() {
          let entity = Entity(id: EntityID("lyra"), type: .character, name: "Lyra Stormwind",
                              body: "Half-elven ranger from Silvermoon.")
          let str = PDFContent.entityDocument(entity).string
          XCTAssertTrue(str.contains("Lyra Stormwind"))
          XCTAssertTrue(str.contains("character"))
          XCTAssertTrue(str.contains("Half-elven ranger from Silvermoon."))
      }

      func test_worldDocument_groupsByType_andIncludesTitle() {
          let world = sampleWorld()
          let entities = [
              Entity(id: EntityID("lyra"),    type: .character, name: "Lyra",    body: "char body"),
              Entity(id: EntityID("magnus"),  type: .character, name: "Magnus",  body: "char body 2"),
              Entity(id: EntityID("silver"),  type: .location,  name: "Silver",  body: "loc body"),
          ]
          let str = PDFContent.worldDocument(world: world, entities: entities).string
          XCTAssertTrue(str.contains("Aetheria"))
          XCTAssertTrue(str.contains("Characters"))
          XCTAssertTrue(str.contains("Locations"))
          XCTAssertTrue(str.contains("Lyra"))
          XCTAssertTrue(str.contains("Magnus"))
          XCTAssertTrue(str.contains("Silver"))
          // characters section appears before locations
          let charIdx = str.range(of: "Characters")!.lowerBound
          let locIdx  = str.range(of: "Locations")!.lowerBound
          XCTAssertLessThan(charIdx, locIdx)
      }

      func test_worldDocument_skipsEmptyTypes() {
          let world = sampleWorld()
          let entities = [
              Entity(id: EntityID("lyra"), type: .character, name: "Lyra", body: "x"),
          ]
          let str = PDFContent.worldDocument(world: world, entities: entities).string
          XCTAssertFalse(str.contains("Locations"))
          XCTAssertFalse(str.contains("Lore"))
      }
  }
  ```

- [ ] **Step 2: Run** — expect compile failure (`PDFContent` unknown).

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -15
  ```

- [ ] **Step 3: Implement**

  `FantasyTavernApp/Sources/Export/PDFContent.swift`:

  ```swift
  import AppKit
  import EntityModel
  import WorldStore

  enum PDFContent {
      private static let titleFont   = NSFont.boldSystemFont(ofSize: 32)
      private static let typeFont    = NSFont.boldSystemFont(ofSize: 22)
      private static let nameFont    = NSFont.boldSystemFont(ofSize: 16)
      private static let captionFont = NSFont.systemFont(ofSize: 11)
      private static let bodyFont    = NSFont.systemFont(ofSize: 12)

      static func entityDocument(_ entity: Entity) -> NSAttributedString {
          let out = NSMutableAttributedString()
          appendName(entity.name, into: out)
          appendCaption(entity.type.rawValue, into: out)
          appendBody(entity.body, into: out)
          return out
      }

      static func worldDocument(world: World, entities: [Entity]) -> NSAttributedString {
          let out = NSMutableAttributedString()
          appendTitle(world.name, into: out)

          for type in EntityType.allCases {
              let inType = entities.filter { $0.type == type }.sorted { $0.name.lowercased() < $1.name.lowercased() }
              guard !inType.isEmpty else { continue }
              appendTypeHeading(label(for: type), into: out)
              for entity in inType {
                  appendName(entity.name, into: out)
                  appendBody(entity.body, into: out)
              }
          }
          return out
      }

      // MARK: - sections

      private static func appendTitle(_ text: String, into s: NSMutableAttributedString) {
          let para = NSMutableParagraphStyle()
          para.alignment = .center
          para.paragraphSpacing = 32
          let attrs: [NSAttributedString.Key: Any] = [.font: titleFont, .paragraphStyle: para]
          s.append(NSAttributedString(string: "\(text)\n", attributes: attrs))
      }

      private static func appendTypeHeading(_ text: String, into s: NSMutableAttributedString) {
          let para = NSMutableParagraphStyle()
          para.paragraphSpacingBefore = 24
          para.paragraphSpacing = 8
          let attrs: [NSAttributedString.Key: Any] = [.font: typeFont, .paragraphStyle: para]
          s.append(NSAttributedString(string: "\(text)\n", attributes: attrs))
      }

      private static func appendName(_ text: String, into s: NSMutableAttributedString) {
          let para = NSMutableParagraphStyle()
          para.paragraphSpacingBefore = 8
          let attrs: [NSAttributedString.Key: Any] = [.font: nameFont, .paragraphStyle: para]
          s.append(NSAttributedString(string: "\(text)\n", attributes: attrs))
      }

      private static func appendCaption(_ text: String, into s: NSMutableAttributedString) {
          let attrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: NSColor.secondaryLabelColor]
          s.append(NSAttributedString(string: "\(text)\n", attributes: attrs))
      }

      private static func appendBody(_ text: String, into s: NSMutableAttributedString) {
          let para = NSMutableParagraphStyle()
          para.paragraphSpacingBefore = 4
          para.paragraphSpacing = 6
          let attrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .paragraphStyle: para]
          s.append(NSAttributedString(string: "\(text)\n", attributes: attrs))
      }

      private static func label(for type: EntityType) -> String {
          switch type {
          case .character:     return "Characters"
          case .location:      return "Locations"
          case .lore:          return "Lore"
          case .item:          return "Items"
          case .language:      return "Languages"
          case .journal:       return "Journal"
          case .timelineEvent: return "Timeline"
          }
      }
  }
  ```

- [ ] **Step 4: Run tests** — expect 3 new pass.

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(export): PDFContent attributed-string builder for entity + world"
  ```

---

## Task 2: PDFExporter — NSPrintOperation save-to-PDF

**Files:**
- Create: `FantasyTavernApp/Sources/Export/PDFExporter.swift`

No automated test for this task — exercised via Task 4 smoke + downstream menu. The function is a thin glue over AppKit.

- [ ] **Step 1: Implement**

  `FantasyTavernApp/Sources/Export/PDFExporter.swift`:

  ```swift
  import AppKit

  enum PDFExporter {
      enum ExportError: Error {
          case printOperationFailed
      }

      /// Render `content` to a PDF file at `url`. Uses US Letter w/ 0.5" margins.
      static func write(_ content: NSAttributedString, to url: URL) throws {
          let info = NSPrintInfo()
          info.paperSize = NSSize(width: 612, height: 792)
          info.topMargin = 36
          info.bottomMargin = 36
          info.leftMargin = 36
          info.rightMargin = 36
          info.horizontalPagination = .fit
          info.verticalPagination = .automatic
          info.isHorizontallyCentered = true
          info.isVerticallyCentered = false
          info.jobDisposition = .save
          info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url as NSURL

          let textWidth  = info.paperSize.width  - info.leftMargin - info.rightMargin
          let textHeight = info.paperSize.height - info.topMargin  - info.bottomMargin

          // Build a tall NSTextView; NSPrintOperation paginates it across pages.
          let frame = NSRect(x: 0, y: 0, width: textWidth, height: textHeight)
          let textView = NSTextView(frame: frame)
          textView.isEditable = false
          textView.isHorizontallyResizable = false
          textView.isVerticallyResizable = true
          textView.autoresizingMask = [.width]
          textView.textContainer?.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
          textView.textContainer?.widthTracksTextView = true
          textView.textStorage?.setAttributedString(content)
          textView.layoutManager?.ensureLayout(for: textView.textContainer!)
          let used = textView.layoutManager?.usedRect(for: textView.textContainer!).size ?? .zero
          textView.frame = NSRect(x: 0, y: 0, width: textWidth, height: max(textHeight, used.height))

          let op = NSPrintOperation(view: textView, printInfo: info)
          op.showsPrintPanel = false
          op.showsProgressPanel = false
          if !op.run() {
              throw ExportError.printOperationFailed
          }
      }
  }
  ```

- [ ] **Step 2: Build**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  ```

  Expected: build succeeds.

- [ ] **Step 3: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(export): PDFExporter wraps NSPrintOperation save-as-PDF"
  ```

---

## Task 3: AppCommands — PDF export menu

**Files:**
- Modify: `FantasyTavernApp/Sources/Commands/AppCommands.swift`

- [ ] **Step 1: Edit menu**

  Read existing `AppCommands.swift`. Inside the existing `Menu("Export") { … }` block, append:

  ```swift
                  Divider()
                  Button("PDF — Current Entity…") { exportCurrentEntityPDF() }
                      .disabled(currentEntity() == nil)
                  Button("PDF — Whole World…") { exportWholeWorldPDF() }
                      .disabled(session.store == nil)
  ```

  Then add two methods to the struct (alongside `exportCurrentEntity` etc.):

  ```swift
      private func exportCurrentEntityPDF() {
          guard let e = currentEntity() else { return }
          let panel = NSSavePanel()
          panel.allowedContentTypes = [.pdf]
          panel.nameFieldStringValue = "\(e.id.rawValue).pdf"
          guard panel.runModal() == .OK, let url = panel.url else { return }
          let doc = PDFContent.entityDocument(e)
          try? PDFExporter.write(doc, to: url)
      }

      private func exportWholeWorldPDF() {
          guard let store = session.store else { return }
          let panel = NSSavePanel()
          panel.allowedContentTypes = [.pdf]
          panel.nameFieldStringValue = "\(store.world.name).pdf"
          guard panel.runModal() == .OK, let url = panel.url else { return }
          let doc = PDFContent.worldDocument(world: store.world, entities: store.entities)
          try? PDFExporter.write(doc, to: url)
      }
  ```

- [ ] **Step 2: Build + run tests**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, all tests pass.

- [ ] **Step 3: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(export): PDF — Current Entity / Whole World menu items"
  ```

---

## Task 4: Manual acceptance

- [ ] **Step 1: Build + launch**

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -3
  pkill -f FantasyTavernApp 2>/dev/null || true
  sleep 1
  open ~/Library/Developer/Xcode/DerivedData/FantasyTavern-cjpexdvcsmhrwcafqhtvzpbgihqg/Build/Products/Debug/FantasyTavernApp.app
  ```

- [ ] **Step 2: Walkthrough**

  1. Open Aetheria. Open Lyra. File → Export → PDF — Current Entity… → save to Desktop as `lyra.pdf`.
  2. Open `lyra.pdf` in Preview. Expect: bold "Lyra Stormwind" title, dim "character" caption, body text.
  3. File → Export → PDF — Whole World… → save as `aetheria.pdf`. Open in Preview.
  4. First page: centered "Aetheria" title. Subsequent pages: type headings ("Characters", "Locations", etc.) for each non-empty type, followed by entity sub-headings + bodies. Text wraps and paginates correctly.
  5. Long bodies span multiple pages without truncation.

- [ ] **Step 3: Tag**

  ```bash
  git tag plan-9-pdf-export-complete
  ```

---

## Deferred from Plan 9 (call out at review)

- Theme / typography customization.
- Cover image / color from `world.color`.
- Wiki-links → in-PDF hyperlinks via Apple's text linking.
- Inline markdown rendering (bold/italic/headings).
- Embedded images.

## Self-Review notes

**Spec coverage:**
- PDF export single entity: Tasks 1 + 2 + 3. ✓
- PDF export whole world: same. ✓
- PDF deferral resolved (was last spec-deferred v2 feature).

**Placeholder scan:** clean.

**Type consistency:**
- `PDFContent.entityDocument(_:)` / `PDFContent.worldDocument(world:entities:)` consistent Tasks 1, 3.
- `PDFExporter.write(_:to:)` consistent Tasks 2, 3.
- `NSPrintInfo.AttributeKey.jobSavingURL` key correct for save-to-file disposition.
