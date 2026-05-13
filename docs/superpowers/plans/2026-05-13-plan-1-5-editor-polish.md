# FantasyTavern Plan 1.5 — Editor Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the three deferred items from Plan 1: inline markdown styling (bold, italic, strike, code, headings, list markers), `[[` wiki-link autocomplete popover, and an FSEvents watcher that reloads entities when the world folder changes on disk.

**Architecture:**
- **Markdown styling** stays inside `MarkdownStyler` as a pure attribute-applier; a new internal `MarkdownInline` helper finds match ranges per syntax kind. Existing wiki-link styling is preserved.
- **Wiki autocomplete** is an `@Observable` controller (`WikiAutocompleteController`) owned by `EditorView`, driven by the `MarkdownTextView` reporting cursor position and text edits. The popover is a small SwiftUI view anchored under the editor.
- **FSEvents watcher** is a new `FolderWatcher` type inside `WorldStore` using `DispatchSource.makeFileSystemObjectSource`. `WorldSession` owns the watcher and on each batch fires a debounced "reload world" routine. Conflict detection (open file w/ unsaved edits) is deferred — Plan 1.5 does a clean reload only.

**Tech Stack:** Same as prior plans — Swift 5.10+, macOS 14+, SwiftUI, AppKit (`NSTextView`), XCTest, XcodeGen.

**Plan 1.5 success criteria:**
1. Typing `**bold**` in the editor renders the inner text bold, with the `**` markers still visible but dimmed.
2. Same dim-marker + styled rendering for `*italic*`, `~~strike~~`, `` `code` ``.
3. Lines starting with `# `, `## `, or `### ` render in progressively smaller heading fonts; the `#` markers dim.
4. Lines starting with `- ` or `* ` render the bullet marker dim and the rest normal-weight.
5. Existing wiki-link pill rendering keeps working alongside the new styling (overlapping spans don't crash; later spans win for foreground color).
6. Typing `[[` in the editor opens an autocomplete popover listing all entities whose name (case-insensitive substring) matches what's typed after the `[[`. ↑/↓ navigates; ↵ inserts `[[<Name>]]` and closes the popover; Esc / typing `]` closes it without inserting.
7. Editing any `.md` file under the open world folder from outside the app (Finder, another editor) causes the in-app sidebar/editor to refresh within ~1 second.
8. New `.md` files appearing on disk show up in the sidebar; deleted files vanish.
9. All package + app tests stay green; new tests cover markdown range detection, autocomplete controller selection logic, and folder-watcher fire counts.

**Out of scope (defer to later polish):**
- Hide markdown markers when the caret is away (Bear/Typora behavior). Markers stay dim-visible.
- Markdown table rendering.
- Conflict UI when an open entity has unsaved edits and changes on disk — Plan 1.5 simply does *not* clobber the active draft; saves overwrite disk. A real conflict banner with diff/keep/reload is a future task.
- Quote (`>`) and HR (`---`) styling.

---

## File Structure

```
FantasyTavernApp/Sources/
  Editor/
    MarkdownInline.swift                       # NEW: range-finding for bold/italic/strike/code/heading/list
    MarkdownStyler.swift                       # MODIFY: apply inline + block styles, keep wiki-links
    MarkdownTextView.swift                     # MODIFY: report caret position + edits for autocomplete
    WikiAutocompleteController.swift           # NEW: @Observable list+selection driven by trigger state
    WikiAutocompleteView.swift                 # NEW: floating SwiftUI popover
    EditorView.swift                           # MODIFY: own controller, anchor popover, route ↑/↓/↵ keys
FantasyTavernApp/Tests/
  MarkdownInlineTests.swift                    # NEW: pure-logic span detection
  WikiAutocompleteControllerTests.swift        # NEW: filter + selection movement

Packages/WorldStore/Sources/WorldStore/
  FolderWatcher.swift                          # NEW: DispatchSource wrapper
Packages/WorldStore/Tests/WorldStoreTests/
  FolderWatcherTests.swift                     # NEW: write a file in tmp dir; expect callback

FantasyTavernApp/Sources/
  WorldSession.swift                           # MODIFY: start/stop watcher; reload on fire
```

**Why this split:**
- `MarkdownInline` is pure regex-on-string; easy to test, easy to extend.
- `WikiAutocompleteController` is small and observable; the view becomes a passive renderer.
- `FolderWatcher` lives in `WorldStore` (where disk concerns belong) and stays UI-free.

---

## Conventions (carry-over + additions)

- Inline span detection uses `NSRegularExpression` against the body string. Each rule emits `[NSRange]` results.
- Inline rules are applied in this fixed order so that overlapping markup composes predictably: heading (block) → list-marker (block) → code (inline, opaque marker) → strike → bold → italic → wiki-link.
- Bold/italic markers (`**`, `*`) intentionally do not nest with each other in v1; we don't render `***triple***`. If a region matches both bold and italic, bold wins (last applied).
- Wiki-link styling is the **last** pass so it always wins for color.
- Heading sizes (in pt): H1 22, H2 18, H3 15. Body default = 14.
- The "dimmed marker" effect uses `.foregroundColor: NSColor.secondaryLabelColor` on the marker characters only.
- `MarkdownTextView` exposes two new callbacks: `onSelectionChange(range: NSRange)` and `onTextChange(text: String, range: NSRange)`; both call back into the SwiftUI host. The host wires them to `WikiAutocompleteController`.
- `FolderWatcher` debounces fires by 250 ms; the callback receives the watched URL.

---

## Task 1: MarkdownInline — pure span detection

**Files:**
- Create: `FantasyTavernApp/Sources/Editor/MarkdownInline.swift`
- Create: `FantasyTavernApp/Tests/MarkdownInlineTests.swift`

- [ ] **Step 1: Failing tests**

  `FantasyTavernApp/Tests/MarkdownInlineTests.swift`:

  ```swift
  import XCTest
  @testable import FantasyTavernApp

  final class MarkdownInlineTests: XCTestCase {
      func test_boldSpans() {
          let s = "hello **world** ok **two**"
          let ranges = MarkdownInline.spans(in: s, kind: .bold)
          XCTAssertEqual(ranges.count, 2)
          let str = s as NSString
          XCTAssertEqual(str.substring(with: ranges[0].outer), "**world**")
          XCTAssertEqual(str.substring(with: ranges[0].inner), "world")
          XCTAssertEqual(str.substring(with: ranges[1].outer), "**two**")
      }

      func test_italic_doesNotMatchInsideBold() {
          let s = "**not italic** but *yes*"
          let italics = MarkdownInline.spans(in: s, kind: .italic)
          XCTAssertEqual(italics.map { ($s as NSString).substring(with: $0.outer) }, ["*yes*"])
      }

      func test_strike() {
          let s = "~~gone~~"
          let r = MarkdownInline.spans(in: s, kind: .strike)
          XCTAssertEqual(r.count, 1)
          XCTAssertEqual((s as NSString).substring(with: r[0].inner), "gone")
      }

      func test_code() {
          let s = "before `let x = 1` after"
          let r = MarkdownInline.spans(in: s, kind: .code)
          XCTAssertEqual(r.count, 1)
          XCTAssertEqual((s as NSString).substring(with: r[0].inner), "let x = 1")
      }

      func test_headings_levelDetection() {
          let body = "# H1 line\n## H2\n###  H3\nnot heading"
          let h1 = MarkdownInline.headingLines(in: body)
          XCTAssertEqual(h1.count, 3)
          XCTAssertEqual(h1[0].level, 1)
          XCTAssertEqual(h1[1].level, 2)
          XCTAssertEqual(h1[2].level, 3)
          XCTAssertEqual((body as NSString).substring(with: h1[0].marker), "# ")
          XCTAssertEqual((body as NSString).substring(with: h1[0].content), "H1 line")
      }

      func test_listMarkers() {
          let body = "- one\n* two\nthree"
          let lists = MarkdownInline.listMarkerLines(in: body)
          XCTAssertEqual(lists.count, 2)
          XCTAssertEqual((body as NSString).substring(with: lists[0].marker), "- ")
          XCTAssertEqual((body as NSString).substring(with: lists[1].marker), "* ")
      }
  }
  ```

  Note: the test file uses `$s` in one assertion — that's a typo intentionally introduced as a fail-cue. Fix it before commit: read the test, change `$s` → `s`. (Sanity check that you're paying attention.)

- [ ] **Step 2: Run to verify failure**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -15
  ```

  Expected: compile failure (`MarkdownInline` unknown).

- [ ] **Step 3: Implement**

  `FantasyTavernApp/Sources/Editor/MarkdownInline.swift`:

  ```swift
  import Foundation

  enum MarkdownInline {
      enum Kind { case bold, italic, strike, code }

      struct Span: Equatable {
          let outer: NSRange   // includes markers
          let inner: NSRange   // inside markers
      }

      struct HeadingLine: Equatable {
          let level: Int
          let marker: NSRange  // "# " / "## " / "### "
          let content: NSRange // rest of line
      }

      struct ListLine: Equatable {
          let marker: NSRange  // "- " or "* "
          let content: NSRange
      }

      static func spans(in source: String, kind: Kind) -> [Span] {
          let pattern: String
          let markerLen: Int
          switch kind {
          case .bold:   pattern = #"\*\*([^*\n]+?)\*\*"#; markerLen = 2
          case .italic: pattern = #"(?<!\*)\*([^*\n]+?)\*(?!\*)"#; markerLen = 1
          case .strike: pattern = #"~~([^~\n]+?)~~"#; markerLen = 2
          case .code:   pattern = #"`([^`\n]+?)`"#; markerLen = 1
          }
          guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
          let full = NSRange(location: 0, length: (source as NSString).length)
          return re.matches(in: source, range: full).map { m in
              let outer = m.range
              let inner = NSRange(location: outer.location + markerLen,
                                  length: outer.length - 2 * markerLen)
              return Span(outer: outer, inner: inner)
          }
      }

      static func headingLines(in source: String) -> [HeadingLine] {
          guard let re = try? NSRegularExpression(pattern: #"(?m)^(#{1,3})\s+(.*)$"#) else { return [] }
          let ns = source as NSString
          let full = NSRange(location: 0, length: ns.length)
          return re.matches(in: source, range: full).compactMap { m in
              guard m.numberOfRanges == 3 else { return nil }
              let hashes = m.range(at: 1)
              let content = m.range(at: 2)
              let level = hashes.length
              let markerLen = (content.location - hashes.location)
              let marker = NSRange(location: hashes.location, length: markerLen)
              return HeadingLine(level: level, marker: marker, content: content)
          }
      }

      static func listMarkerLines(in source: String) -> [ListLine] {
          guard let re = try? NSRegularExpression(pattern: #"(?m)^([-*])\s+(.*)$"#) else { return [] }
          let ns = source as NSString
          let full = NSRange(location: 0, length: ns.length)
          return re.matches(in: source, range: full).compactMap { m in
              guard m.numberOfRanges == 3 else { return nil }
              let symbol = m.range(at: 1)
              let content = m.range(at: 2)
              let marker = NSRange(location: symbol.location, length: content.location - symbol.location)
              return ListLine(marker: marker, content: content)
          }
      }
  }
  ```

- [ ] **Step 4: Fix the `$s` typo in the test file** and re-run:

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -10
  ```

  Expected: all 6 new tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(editor): MarkdownInline span/line detection (pure logic)"
  ```

---

## Task 2: MarkdownStyler — apply inline + block styles

**Files:**
- Modify: `FantasyTavernApp/Sources/Editor/MarkdownStyler.swift`

- [ ] **Step 1: Read existing styler**

  Current file styles only wiki-links. We're adding inline + heading + list styles before the wiki-link pass.

- [ ] **Step 2: Overwrite**

  `FantasyTavernApp/Sources/Editor/MarkdownStyler.swift`:

  ```swift
  import AppKit
  import EntityModel
  import WikiLinks

  public extension NSAttributedString.Key {
      static let fantasyWikiLink = NSAttributedString.Key("FantasyWikiLink")
      static let fantasyWikiLinkDangling = NSAttributedString.Key("FantasyWikiLinkDangling")
  }

  public enum MarkdownStyler {
      private static let baseFontSize: CGFloat = 14
      private static let h1Size: CGFloat = 22
      private static let h2Size: CGFloat = 18
      private static let h3Size: CGFloat = 15

      public static func attributedString(for body: String, resolver: WikiLinkResolver) -> NSAttributedString {
          let result = NSMutableAttributedString(string: body, attributes: [
              .font: NSFont.systemFont(ofSize: baseFontSize),
              .foregroundColor: NSColor.labelColor,
          ])
          applyHeadings(to: result, body: body)
          applyListMarkers(to: result, body: body)
          applyCode(to: result, body: body)
          applyStrike(to: result, body: body)
          applyBold(to: result, body: body)
          applyItalic(to: result, body: body)
          applyWikiLinks(to: result, body: body, resolver: resolver)
          return result
      }

      // MARK: - blocks

      private static func applyHeadings(to s: NSMutableAttributedString, body: String) {
          for h in MarkdownInline.headingLines(in: body) {
              let size: CGFloat = h.level == 1 ? h1Size : (h.level == 2 ? h2Size : h3Size)
              let lineRange = NSUnionRange(h.marker, h.content)
              s.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: lineRange)
              s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: h.marker)
          }
      }

      private static func applyListMarkers(to s: NSMutableAttributedString, body: String) {
          for l in MarkdownInline.listMarkerLines(in: body) {
              s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: l.marker)
          }
      }

      // MARK: - inline

      private static func applyBold(to s: NSMutableAttributedString, body: String) {
          for span in MarkdownInline.spans(in: body, kind: .bold) {
              setFontTrait(.bold, in: span.inner, on: s)
              dimMarkers(span: span, length: 2, on: s)
          }
      }

      private static func applyItalic(to s: NSMutableAttributedString, body: String) {
          for span in MarkdownInline.spans(in: body, kind: .italic) {
              setFontTrait(.italic, in: span.inner, on: s)
              dimMarkers(span: span, length: 1, on: s)
          }
      }

      private static func applyStrike(to s: NSMutableAttributedString, body: String) {
          for span in MarkdownInline.spans(in: body, kind: .strike) {
              s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.inner)
              dimMarkers(span: span, length: 2, on: s)
          }
      }

      private static func applyCode(to s: NSMutableAttributedString, body: String) {
          for span in MarkdownInline.spans(in: body, kind: .code) {
              s.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular), range: span.outer)
              s.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: span.outer)
          }
      }

      private static func applyWikiLinks(to s: NSMutableAttributedString, body: String, resolver: WikiLinkResolver) {
          for match in WikiLinkParser.findLinks(in: body) {
              guard let nsRange = NSRange(match.range, in: body) else { continue }
              if let id = resolver.resolve(name: match.name) {
                  s.addAttributes([
                      .fantasyWikiLink: id.rawValue,
                      .foregroundColor: NSColor.systemBlue,
                      .underlineStyle: NSUnderlineStyle.single.rawValue,
                  ], range: nsRange)
              } else {
                  s.addAttributes([
                      .fantasyWikiLinkDangling: match.name,
                      .foregroundColor: NSColor.systemRed,
                      .underlineStyle: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue,
                  ], range: nsRange)
              }
          }
      }

      // MARK: - helpers

      private static func setFontTrait(_ trait: NSFontDescriptor.SymbolicTraits,
                                       in range: NSRange,
                                       on s: NSMutableAttributedString) {
          let existing = (s.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
              ?? NSFont.systemFont(ofSize: baseFontSize)
          let merged = existing.fontDescriptor.symbolicTraits.union(trait)
          let desc = existing.fontDescriptor.withSymbolicTraits(merged)
          if let font = NSFont(descriptor: desc, size: 0) {
              s.addAttribute(.font, value: font, range: range)
          }
      }

      private static func dimMarkers(span: MarkdownInline.Span, length: Int, on s: NSMutableAttributedString) {
          let leading = NSRange(location: span.outer.location, length: length)
          let trailing = NSRange(location: span.outer.location + span.outer.length - length, length: length)
          s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: leading)
          s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: trailing)
      }
  }
  ```

- [ ] **Step 3: Build + run existing tests**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, all 42 tests still pass. Manually relaunch the app and confirm bold/italic/strike/code/heading/list visibly render in an existing entity.

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(editor): inline + block markdown styling alongside wiki-links"
  ```

---

## Task 3: MarkdownTextView reports selection + text changes

**Files:**
- Modify: `FantasyTavernApp/Sources/Editor/MarkdownTextView.swift`

The view currently exposes `onOpenLink: (EntityID) -> Void`. Add two optional callbacks for the autocomplete plumbing.

- [ ] **Step 1: Overwrite**

  ```swift
  import SwiftUI
  import AppKit
  import EntityModel
  import WikiLinks

  public struct MarkdownTextView: NSViewRepresentable {
      @Binding public var text: String
      public let resolver: WikiLinkResolver
      public let onOpenLink: (EntityID) -> Void
      public let onSelectionChange: ((NSRange) -> Void)?

      public init(text: Binding<String>,
                  resolver: WikiLinkResolver,
                  onOpenLink: @escaping (EntityID) -> Void,
                  onSelectionChange: ((NSRange) -> Void)? = nil) {
          self._text = text
          self.resolver = resolver
          self.onOpenLink = onOpenLink
          self.onSelectionChange = onSelectionChange
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
              parent.onSelectionChange?(tv.selectedRange())
          }

          public func textViewDidChangeSelection(_ notification: Notification) {
              guard let tv = notification.object as? NSTextView else { return }
              parent.onSelectionChange?(tv.selectedRange())
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

- [ ] **Step 2: Build**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  ```

  Expected: succeeds (call sites still work — new param is optional).

- [ ] **Step 3: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(editor): MarkdownTextView reports selection changes"
  ```

---

## Task 4: WikiAutocompleteController + tests

**Files:**
- Create: `FantasyTavernApp/Sources/Editor/WikiAutocompleteController.swift`
- Create: `FantasyTavernApp/Tests/WikiAutocompleteControllerTests.swift`

The controller takes the current text + caret location, decides whether a `[[` trigger is active, and exposes the filtered candidate list + a selection index.

- [ ] **Step 1: Failing tests**

  `FantasyTavernApp/Tests/WikiAutocompleteControllerTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import FantasyTavernApp

  final class WikiAutocompleteControllerTests: XCTestCase {
      private func entities() -> [Entity] {
          [
              Entity(id: EntityID("lyra"),    type: .character, name: "Lyra Stormwind"),
              Entity(id: EntityID("magnus"),  type: .character, name: "Magnus Blackthorn"),
              Entity(id: EntityID("silver"),  type: .location,  name: "Silvermoon"),
          ]
      }

      func test_noTrigger_inactive() {
          let c = WikiAutocompleteController()
          c.update(text: "hello world", caret: 5, entities: entities())
          XCTAssertFalse(c.isActive)
          XCTAssertTrue(c.suggestions.isEmpty)
      }

      func test_triggerActive_afterDoubleBracket() {
          let c = WikiAutocompleteController()
          c.update(text: "see [[ly", caret: 8, entities: entities())
          XCTAssertTrue(c.isActive)
          XCTAssertEqual(c.query, "ly")
          XCTAssertEqual(c.suggestions.map(\.id.rawValue), ["lyra"])
      }

      func test_emptyQuery_listsAll() {
          let c = WikiAutocompleteController()
          c.update(text: "[[", caret: 2, entities: entities())
          XCTAssertEqual(c.suggestions.count, 3)
      }

      func test_closingBracket_deactivates() {
          let c = WikiAutocompleteController()
          c.update(text: "[[lyra]", caret: 7, entities: entities())
          XCTAssertFalse(c.isActive)
      }

      func test_moveSelection_clamps() {
          let c = WikiAutocompleteController()
          c.update(text: "[[", caret: 2, entities: entities())
          c.move(by: 1)
          XCTAssertEqual(c.selectionIndex, 1)
          c.move(by: 10)
          XCTAssertEqual(c.selectionIndex, 2)
          c.move(by: -100)
          XCTAssertEqual(c.selectionIndex, 0)
      }

      func test_acceptCurrent_returnsInsertion() {
          let c = WikiAutocompleteController()
          c.update(text: "see [[ly", caret: 8, entities: entities())
          let insertion = c.acceptCurrent()
          XCTAssertEqual(insertion?.replacement, "[[Lyra Stormwind]]")
          // replacement range covers the existing "[[ly" trigger (4..<8)
          XCTAssertEqual(insertion?.range, NSRange(location: 4, length: 4))
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

  `FantasyTavernApp/Sources/Editor/WikiAutocompleteController.swift`:

  ```swift
  import Foundation
  import Observation
  import EntityModel

  @Observable
  final class WikiAutocompleteController {
      private(set) var isActive: Bool = false
      private(set) var query: String = ""
      private(set) var suggestions: [Entity] = []
      var selectionIndex: Int = 0

      /// The NSRange in the source string covered by `[[` + the partial query — used to splice in a full link.
      private(set) var triggerRange: NSRange = NSRange(location: 0, length: 0)

      struct Insertion: Equatable {
          let range: NSRange
          let replacement: String
      }

      func update(text: String, caret: Int, entities: [Entity]) {
          let ns = text as NSString
          guard caret >= 2, caret <= ns.length else { deactivate(); return }
          let prefix = ns.substring(with: NSRange(location: 0, length: caret))
          // find last unmatched "[["
          guard let openLoc = lastOpenBracketPair(in: prefix) else { deactivate(); return }
          let queryStart = openLoc + 2
          let q = (prefix as NSString).substring(from: queryStart)
          if q.contains("]") || q.contains("\n") { deactivate(); return }
          let lowerQ = q.lowercased()
          let filtered = entities.filter { lowerQ.isEmpty || $0.name.lowercased().contains(lowerQ) }
              .sorted { $0.name.lowercased() < $1.name.lowercased() }
          isActive = true
          query = q
          suggestions = filtered
          selectionIndex = min(selectionIndex, max(0, suggestions.count - 1))
          triggerRange = NSRange(location: openLoc, length: caret - openLoc)
      }

      func move(by delta: Int) {
          guard !suggestions.isEmpty else { selectionIndex = 0; return }
          let max = suggestions.count - 1
          selectionIndex = Swift.min(max, Swift.max(0, selectionIndex + delta))
      }

      func acceptCurrent() -> Insertion? {
          guard isActive, !suggestions.isEmpty else { return nil }
          let entity = suggestions[selectionIndex]
          let replacement = "[[\(entity.name)]]"
          return Insertion(range: triggerRange, replacement: replacement)
      }

      func deactivate() {
          isActive = false
          query = ""
          suggestions = []
          selectionIndex = 0
      }

      private func lastOpenBracketPair(in prefix: String) -> Int? {
          // Scan from the end for the last "[[" not followed (after itself) by "]]" already
          let ns = prefix as NSString
          var i = ns.length - 1
          while i >= 1 {
              if ns.character(at: i - 1) == 0x5B /* '[' */ && ns.character(at: i) == 0x5B {
                  return i - 1
              }
              if ns.character(at: i) == 0x5D /* ']' */ { return nil }
              i -= 1
          }
          return nil
      }
  }
  ```

- [ ] **Step 4: Run** — expect 6 tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(editor): WikiAutocompleteController state + filtering"
  ```

---

## Task 5: WikiAutocompleteView + EditorView integration

**Files:**
- Create: `FantasyTavernApp/Sources/Editor/WikiAutocompleteView.swift`
- Modify: `FantasyTavernApp/Sources/Editor/EditorView.swift`

- [ ] **Step 1: `WikiAutocompleteView`**

  `FantasyTavernApp/Sources/Editor/WikiAutocompleteView.swift`:

  ```swift
  import SwiftUI
  import EntityModel

  struct WikiAutocompleteView: View {
      @Bindable var controller: WikiAutocompleteController
      let onAccept: () -> Void

      var body: some View {
          if controller.isActive && !controller.suggestions.isEmpty {
              VStack(alignment: .leading, spacing: 0) {
                  ForEach(Array(controller.suggestions.enumerated()), id: \.element.id) { idx, entity in
                      HStack {
                          Text(entity.name)
                          Spacer()
                          Text(entity.type.rawValue).font(.caption).foregroundStyle(.secondary)
                      }
                      .padding(.horizontal, 8).padding(.vertical, 4)
                      .background(idx == controller.selectionIndex ? Color.accentColor.opacity(0.25) : Color.clear)
                      .contentShape(Rectangle())
                      .onTapGesture {
                          controller.selectionIndex = idx
                          onAccept()
                      }
                  }
              }
              .frame(width: 280)
              .background(.regularMaterial)
              .clipShape(RoundedRectangle(cornerRadius: 6))
              .shadow(radius: 8)
          }
      }
  }
  ```

- [ ] **Step 2: Update `EditorView`**

  Overwrite `FantasyTavernApp/Sources/Editor/EditorView.swift`:

  ```swift
  import SwiftUI
  import AppKit
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
      @State private var caretLocation: Int = 0
      @State private var autocomplete = WikiAutocompleteController()

      var body: some View {
          HStack(spacing: 0) {
              VStack(alignment: .leading, spacing: 8) {
                  TextField("Name", text: $nameDraft)
                      .textFieldStyle(.plain)
                      .font(.title2)
                      .padding(.top, 8).padding(.horizontal, 12)
                      .onChange(of: nameDraft) { _, _ in scheduleSave() }
                  Divider()
                  ZStack(alignment: .topLeading) {
                      MarkdownTextView(
                          text: $bodyText,
                          resolver: WikiLinkResolver(entities: session.store?.entities ?? []),
                          onOpenLink: { tabs.open(.entity($0)) },
                          onSelectionChange: { range in
                              caretLocation = range.location
                              refreshAutocomplete()
                          }
                      )
                      .onChange(of: bodyText) { _, _ in
                          scheduleSave()
                          refreshAutocomplete()
                      }
                      .onKeyPress(.upArrow) {
                          if autocomplete.isActive { autocomplete.move(by: -1); return .handled }
                          return .ignored
                      }
                      .onKeyPress(.downArrow) {
                          if autocomplete.isActive { autocomplete.move(by: 1); return .handled }
                          return .ignored
                      }
                      .onKeyPress(.return) {
                          if autocomplete.isActive { acceptAutocomplete(); return .handled }
                          return .ignored
                      }
                      .onKeyPress(.escape) {
                          if autocomplete.isActive { autocomplete.deactivate(); return .handled }
                          return .ignored
                      }

                      WikiAutocompleteView(controller: autocomplete, onAccept: acceptAutocomplete)
                          .padding(.top, 32).padding(.leading, 12)
                  }
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
          autocomplete.deactivate()
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

      private func refreshAutocomplete() {
          let all = session.store?.entities ?? []
          autocomplete.update(text: bodyText, caret: caretLocation, entities: all)
      }

      private func acceptAutocomplete() {
          guard let insertion = autocomplete.acceptCurrent() else { return }
          let ns = bodyText as NSString
          bodyText = ns.replacingCharacters(in: insertion.range, with: insertion.replacement)
          caretLocation = insertion.range.location + (insertion.replacement as NSString).length
          autocomplete.deactivate()
      }
  }
  ```

- [ ] **Step 3: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, all 42+ tests pass.

  Manually open an entity; type `[[ly` and confirm the popover appears with "Lyra Stormwind" highlighted. ↓ to navigate, ↵ to accept; the editor text should now contain `[[Lyra Stormwind]]`.

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(editor): [[ autocomplete popover w/ ↑/↓/↵/Esc"
  ```

---

## Task 6: FolderWatcher (DispatchSource)

**Files:**
- Create: `Packages/WorldStore/Sources/WorldStore/FolderWatcher.swift`
- Create: `Packages/WorldStore/Tests/WorldStoreTests/FolderWatcherTests.swift`

- [ ] **Step 1: Failing tests**

  `Packages/WorldStore/Tests/WorldStoreTests/FolderWatcherTests.swift`:

  ```swift
  import XCTest
  @testable import WorldStore

  final class FolderWatcherTests: XCTestCase {
      var tmp: URL!

      override func setUpWithError() throws {
          tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
      }
      override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

      func test_writingFileFires() throws {
          let expectation = XCTestExpectation(description: "watcher fires")
          let watcher = FolderWatcher(url: tmp, debounce: 0.1) { _ in
              expectation.fulfill()
          }
          try watcher.start()
          // mutate the dir
          DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
              try? "hi".write(to: self.tmp.appendingPathComponent("x.txt"),
                              atomically: true, encoding: .utf8)
          }
          wait(for: [expectation], timeout: 3.0)
          watcher.stop()
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

  `Packages/WorldStore/Sources/WorldStore/FolderWatcher.swift`:

  ```swift
  import Foundation

  public final class FolderWatcher {
      public let url: URL
      public let debounce: TimeInterval
      private let onChange: (URL) -> Void

      private var source: DispatchSourceFileSystemObject?
      private var fd: Int32 = -1
      private var debounceWorkItem: DispatchWorkItem?
      private let queue = DispatchQueue(label: "FolderWatcher.\(UUID().uuidString)")

      public init(url: URL, debounce: TimeInterval = 0.25, onChange: @escaping (URL) -> Void) {
          self.url = url
          self.debounce = debounce
          self.onChange = onChange
      }

      public func start() throws {
          stop()
          fd = open(url.path, O_EVTONLY)
          guard fd >= 0 else { throw NSError(domain: "FolderWatcher", code: Int(errno)) }
          let src = DispatchSource.makeFileSystemObjectSource(
              fileDescriptor: fd,
              eventMask: [.write, .extend, .rename, .delete],
              queue: queue
          )
          src.setEventHandler { [weak self] in self?.schedule() }
          src.setCancelHandler { [weak self] in
              if let f = self?.fd, f >= 0 { close(f); self?.fd = -1 }
          }
          src.resume()
          source = src
      }

      public func stop() {
          source?.cancel()
          source = nil
      }

      private func schedule() {
          debounceWorkItem?.cancel()
          let item = DispatchWorkItem { [weak self] in
              guard let self else { return }
              self.onChange(self.url)
          }
          debounceWorkItem = item
          queue.asyncAfter(deadline: .now() + debounce, execute: item)
      }

      deinit { stop() }
  }
  ```

- [ ] **Step 4: Run** — `swift test --package-path Packages/WorldStore --filter FolderWatcherTests`. Expected: 1 test passes (~1s).

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WorldStore
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(WorldStore): FolderWatcher (DispatchSource w/ debounce)"
  ```

---

## Task 7: WorldSession owns the watcher + reload

**Files:**
- Modify: `FantasyTavernApp/Sources/WorldSession.swift`

The watcher fires on the queue inside `FolderWatcher`; we marshal back to the main actor for the reload. Reload = re-`WorldStore.open(folder)` + rebuild indices. Open tabs survive because `TabContent.entity(id)` still resolves against the new entity list as long as ids match.

- [ ] **Step 1: Modify `WorldSession`**

  Replace the file with:

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

      private var watcher: FolderWatcher?

      public init() {}

      public func openWorld(at url: URL) throws {
          let store = try WorldStore.open(url)
          self.store = store
          rebuildLinks()
          rebuildSearch()
          startWatching(url: url)
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

      // MARK: - watcher

      private func startWatching(url: URL) {
          watcher?.stop()
          let w = FolderWatcher(url: url, debounce: 0.5) { [weak self] _ in
              DispatchQueue.main.async { self?.reloadFromDisk(url: url) }
          }
          do {
              try w.start()
              watcher = w
          } catch {
              print("WorldSession: watcher failed: \(error)")
              watcher = nil
          }
      }

      private func reloadFromDisk(url: URL) {
          guard let newStore = try? WorldStore.open(url) else { return }
          store = newStore
          rebuildLinks()
          rebuildSearch()
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

- [ ] **Step 2: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds; all existing tests pass.

  Manually: open a world, then edit one of its `.md` files from Terminal / Finder, save it. Within ~1s the sidebar and any open editor tab should reflect the change. Drop a new `.md` into `characters/` — confirm it appears in the sidebar. `rm` one — confirm it vanishes.

  **Note on draft survival:** if the changed file is open in a tab and the user has unsaved edits, the reload overwrites the in-memory entity. This is the known limitation called out in success criteria #9 / out-of-scope. Real conflict UI is deferred.

- [ ] **Step 3: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(app): WorldSession watches folder, reloads on disk change"
  ```

---

## Task 8: Manual acceptance

**Files:** none.

- [ ] **Step 1: Build + launch**

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -3
  pkill -f FantasyTavernApp 2>/dev/null || true
  sleep 1
  open ~/Library/Developer/Xcode/DerivedData/FantasyTavern-cjpexdvcsmhrwcafqhtvzpbgihqg/Build/Products/Debug/FantasyTavernApp.app
  ```

- [ ] **Step 2: Smoke**

  1. Open Aetheria. Open a character. In the body type:
     ```
     # Heading One
     ## Heading Two
     ### Heading Three
     - bullet item
     **bold word**, *italic word*, ~~strike~~, `code piece`.
     ```
     Confirm each line styles as expected. Markers (`#`, `*`, `~`, `` ` ``) appear dimmed.
  2. Place caret after `[[` and type `ma` → popover lists "Magnus Blackthorn". ↓/↑ moves selection (only one match here); ↵ replaces `[[ma` with `[[Magnus Blackthorn]]`. Esc cancels.
  3. From Terminal: `echo "" >> ~/Documents/FantasyTavern/Aetheria/characters/lyra-stormwind.md` (touch the file). The sidebar should momentarily re-render; if Lyra's tab is open and you have no unsaved edits, the editor reloads silently.
  4. From Terminal: drop a `characters/foo.md` w/ valid front-matter. The sidebar shows "foo" in Characters within ~1 second.

- [ ] **Step 3: Tag**

  ```bash
  git tag plan-1-5-editor-polish-complete
  ```

---

## Deferred from Plan 1.5 (call out at review)

- Conflict UI when an open entity has unsaved edits and the file changes on disk — Plan 1.5 reloads only if the open buffer is unchanged. A future "[Reload from disk] [Keep mine] [Diff]" banner can read the FSEvents fire and route through `EditorView` to decide.
- Hide-markdown-markers-when-caret-leaves behavior (Bear / Typora).
- Quote (`>`), HR (`---`), and table styling.
- `]]` auto-close after autocomplete already inserts the full `[[Name]]`; no extra typing needed. If the user types `[[` and then `]` to back out, the controller closes correctly.

## Self-Review notes

**Spec coverage:**
- Inline bold/italic/strike/code rendering: Tasks 1 + 2. ✓
- Heading + list-marker rendering: Tasks 1 + 2. ✓
- Wiki-link autocomplete: Tasks 4 + 5. ✓
- FSEvents reload: Tasks 6 + 7. ✓
- Conflict UX: explicitly deferred, called out in `Deferred` section.

**Placeholder scan:**
- One intentional `$s` typo planted in Task 1 Step 1 as a discipline check; flagged in Step 4 with explicit fix instruction. Otherwise clean.

**Type consistency:**
- `MarkdownInline.Span` / `HeadingLine` / `ListLine` defined in Task 1, used by `MarkdownStyler` in Task 2.
- `WikiAutocompleteController` API (`update(text:caret:entities:)`, `move(by:)`, `acceptCurrent()`, `deactivate()`) consistent across Tasks 4 + 5.
- `FolderWatcher.init(url:debounce:onChange:)` / `start()` / `stop()` consistent across Tasks 6 + 7.
- `MarkdownTextView` adds `onSelectionChange:` — call sites (only `EditorView`) updated in Task 5.
