# FantasyTavern Plan 6 — Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three small UX wins: conflict banner when an open entity's disk file changes while user has unsaved drafts, always-visible pin labels with hover-emphasis on maps, and a snapshot preview that mounts a snapshot to a temp folder and opens it read-only.

**Architecture:**
- **Conflict banner**: `EditorView` snapshots the entity it last loaded drafts from. On `entity` value change (driven by `WorldSession.reloadFromDisk`), if current drafts differ from both the last-loaded entity AND the new entity → user has unsaved work that conflicts with disk. Show banner w/ `[Reload from disk]` and `[Keep my changes]`.
- **Pin labels**: change `MapView.pinView` to render a small label chip below each pin always (compact font, dim background). Hover still surfaces tooltip via `.help`.
- **Snapshot preview**: add a "Preview" action in `SnapshotsView` that extracts a snapshot to a temp dir and opens that folder as a read-only world in a separate floating window via a new `SnapshotPreviewWindow` SwiftUI scene.

**Tech Stack:** Same as prior plans — Swift 5.10+, macOS 14+, SwiftUI, AppKit, XCTest. No new SPM packages.

**Plan 6 success criteria:**
1. With Lyra's tab open, edit body but don't wait for save → externally modify the file → save your debounce → app reloads → banner appears at top of editor with two buttons.
2. `[Reload from disk]` discards drafts and loads the disk version. `[Keep my changes]` triggers an immediate save that overwrites disk.
3. Pins on maps show a labelled chip under each dot (uses `pin.label` or falls back to location name). Chip width capped, ellipsizes long labels.
4. From the Snapshots sheet, selecting a snapshot + clicking "Preview" opens a new window titled `"Preview — <snapshot name>"` displaying that snapshot's entities read-only in the same sidebar+editor shell. Closing the window cleans up the temp directory.
5. All existing tests stay green; new tests cover the conflict-decision helper and pin-label fallback logic.

**Out of scope (defer further):**
- Three-way diff view between drafts / disk / snapshot — banner only offers binary choice.
- Editable preview window (preview is strictly read-only).
- Hide-markdown-markers-when-caret-leaves (still deferred).
- Pin label drag to reposition independently of pin.

---

## File Structure

```
FantasyTavernApp/Sources/
  Editor/
    ConflictDecision.swift                  # NEW: pure-logic helper deciding banner state
    ConflictBanner.swift                    # NEW: SwiftUI banner view
    EditorView.swift                        # MODIFY: own banner state, hook into entity change
  Map/
    MapView.swift                           # MODIFY: pinView returns dot + label chip
  Snapshots/
    SnapshotsView.swift                     # MODIFY: add Preview button
    SnapshotPreviewWindow.swift             # NEW: standalone window scene
    SnapshotPreviewSession.swift            # NEW: lightweight @Observable read-only WorldSession-equivalent
  FantasyTavernAppApp.swift                 # MODIFY: open Preview window via NSWorkspace or a Window scene
FantasyTavernApp/Tests/
  ConflictDecisionTests.swift               # NEW
  MapPinLabelTests.swift                    # NEW
```

**Why this split:**
- `ConflictDecision` is a pure 3-line function; isolating it makes the banner predictable + testable.
- `SnapshotPreviewSession` mirrors `WorldSession`'s read API surface so SidebarView and the editor can render without code changes (read-only enforced by ignoring saves at the session layer).
- A separate `SnapshotPreviewWindow` scene avoids modal sheets / NSWindow plumbing — pure SwiftUI.

---

## Task 1: ConflictDecision (pure logic)

**Files:**
- Create: `FantasyTavernApp/Sources/Editor/ConflictDecision.swift`
- Create: `FantasyTavernApp/Tests/ConflictDecisionTests.swift`

- [ ] **Step 1: Failing tests**

  `FantasyTavernApp/Tests/ConflictDecisionTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  @testable import FantasyTavernApp

  final class ConflictDecisionTests: XCTestCase {
      private func entity(name: String = "A", body: String = "") -> Entity {
          Entity(id: EntityID("a"), type: .character, name: name, body: body)
      }

      func test_noChange_noConflict_silentReload() {
          let baseline = entity(body: "old")
          let newDisk = entity(body: "new")
          let drafts = ("A", "old", [], [String: FieldValue]())
          let decision = ConflictDecision.decide(baseline: baseline, newDisk: newDisk, drafts: drafts)
          XCTAssertEqual(decision, .silentReload)
      }

      func test_draftsMatchNewDisk_inSync() {
          let baseline = entity(body: "old")
          let newDisk = entity(body: "new")
          let drafts = ("A", "new", [], [String: FieldValue]())
          let decision = ConflictDecision.decide(baseline: baseline, newDisk: newDisk, drafts: drafts)
          XCTAssertEqual(decision, .inSync)
      }

      func test_draftsDifferFromBoth_conflict() {
          let baseline = entity(body: "old")
          let newDisk = entity(body: "new")
          let drafts = ("A", "mine", [], [String: FieldValue]())
          let decision = ConflictDecision.decide(baseline: baseline, newDisk: newDisk, drafts: drafts)
          XCTAssertEqual(decision, .conflict)
      }

      func test_diskSameAsBaseline_andDraftsDiffer_inSyncDraftsKept() {
          // Disk did not change; user has local edits — no conflict, no reload.
          let baseline = entity(body: "old")
          let newDisk = entity(body: "old")
          let drafts = ("A", "mine", [], [String: FieldValue]())
          let decision = ConflictDecision.decide(baseline: baseline, newDisk: newDisk, drafts: drafts)
          XCTAssertEqual(decision, .inSync)
      }
  }
  ```

- [ ] **Step 2: Run to verify failure**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -15
  ```

  Expected: compile failure (`ConflictDecision` unknown).

- [ ] **Step 3: Implement**

  `FantasyTavernApp/Sources/Editor/ConflictDecision.swift`:

  ```swift
  import Foundation
  import EntityModel

  enum ConflictDecision: Equatable {
      /// New entity matches what user has — nothing to do.
      case inSync
      /// User had no local changes; reload silently.
      case silentReload
      /// User has local changes that differ from new disk state — prompt.
      case conflict

      typealias Drafts = (name: String, body: String, tags: [String], fields: [String: FieldValue])

      static func decide(baseline: Entity, newDisk: Entity, drafts: Drafts) -> ConflictDecision {
          let matches: (Entity) -> Bool = { e in
              e.name == drafts.name &&
              e.body == drafts.body &&
              e.tags == drafts.tags &&
              e.fields == drafts.fields
          }
          if matches(newDisk) { return .inSync }
          if matches(baseline) { return .silentReload }
          return .conflict
      }
  }
  ```

- [ ] **Step 4: Run** — expect 4 new tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(editor): ConflictDecision helper (silentReload/inSync/conflict)"
  ```

---

## Task 2: ConflictBanner + EditorView wiring

**Files:**
- Create: `FantasyTavernApp/Sources/Editor/ConflictBanner.swift`
- Modify: `FantasyTavernApp/Sources/Editor/EditorView.swift`

- [ ] **Step 1: `ConflictBanner`**

  ```swift
  import SwiftUI

  struct ConflictBanner: View {
      let onReload: () -> Void
      let onKeepMine: () -> Void

      var body: some View {
          HStack(spacing: 12) {
              Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(.orange)
              Text("File changed on disk while you were editing.")
                  .font(.callout)
              Spacer()
              Button("Reload from disk", action: onReload)
              Button("Keep my changes", action: onKeepMine)
                  .buttonStyle(.borderedProminent)
          }
          .padding(.horizontal, 12).padding(.vertical, 8)
          .background(Color.orange.opacity(0.12))
      }
  }
  ```

- [ ] **Step 2: Wire into `EditorView`**

  Read existing `FantasyTavernApp/Sources/Editor/EditorView.swift`. Add:
  - `@State private var baseline: Entity? = nil` — last entity passed to `loadDrafts`.
  - `@State private var showConflict: Bool = false`
  - Inside `loadDrafts()`, set `baseline = entity` after reading drafts.
  - Add `.onChange(of: entity)` modifier that calls `handleEntityChange(old:new:)` (Entity is Equatable since Plan 1).
  - `handleEntityChange` runs `ConflictDecision.decide(baseline: baseline ?? entity, newDisk: new, drafts: (nameDraft, bodyText, tags, fields))` and acts on the result.
  - Add a `ConflictBanner` view at the top of the left VStack inside `body`, conditionally rendered when `showConflict`.

  Final `EditorView.swift` (replace whole file — adapt the linter-modified prior version):

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

      @State private var baseline: Entity? = nil
      @State private var showConflict: Bool = false

      var body: some View {
          HStack(spacing: 0) {
              VStack(alignment: .leading, spacing: 0) {
                  if showConflict {
                      ConflictBanner(
                          onReload: { reloadFromDisk() },
                          onKeepMine: { keepMyChanges() }
                      )
                  }
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
          .onChange(of: entity) { old, new in handleEntityChange(old: old, new: new) }
      }

      private func loadDrafts() {
          nameDraft = entity.name
          bodyText = entity.body
          tags = entity.tags
          fields = entity.fields
          autocomplete.deactivate()
          baseline = entity
          showConflict = false
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

      // MARK: - conflict

      private func handleEntityChange(old: Entity, new: Entity) {
          guard old.id == new.id else { return }
          guard let baseline else { return }
          let drafts: ConflictDecision.Drafts = (nameDraft, bodyText, tags, fields)
          switch ConflictDecision.decide(baseline: baseline, newDisk: new, drafts: drafts) {
          case .inSync:
              self.baseline = new
              showConflict = false
          case .silentReload:
              nameDraft = new.name
              bodyText = new.body
              tags = new.tags
              fields = new.fields
              self.baseline = new
              showConflict = false
          case .conflict:
              showConflict = true
          }
      }

      private func reloadFromDisk() {
          nameDraft = entity.name
          bodyText = entity.body
          tags = entity.tags
          fields = entity.fields
          baseline = entity
          showConflict = false
      }

      private func keepMyChanges() {
          showConflict = false
          // Cancel any pending debounce then save immediately.
          saveTask?.cancel()
          var copy = entity
          copy.name = nameDraft
          copy.body = bodyText
          copy.tags = tags
          copy.fields = fields
          try? session.save(copy)
          baseline = copy
      }
  }
  ```

- [ ] **Step 3: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, all existing tests + 4 new = ~67+ tests pass.

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(editor): conflict banner on disk-changed-while-editing"
  ```

---

## Task 3: Pin labels visible by default

**Files:**
- Create: `FantasyTavernApp/Tests/MapPinLabelTests.swift`
- Modify: `FantasyTavernApp/Sources/Map/MapView.swift`

- [ ] **Step 1: Failing test**

  `FantasyTavernApp/Tests/MapPinLabelTests.swift`:

  ```swift
  import XCTest
  import EntityModel
  import WorldStore
  @testable import FantasyTavernApp

  final class MapPinLabelTests: XCTestCase {
      func test_pinLabel_prefersExplicit() {
          let pin = MapPin(x: 0, y: 0, locationId: EntityID("silver"), label: "Silvermoon")
          XCTAssertEqual(MapView.displayLabel(for: pin, entities: []), "Silvermoon")
      }

      func test_pinLabel_fallsBackToEntityName() {
          let pin = MapPin(x: 0, y: 0, locationId: EntityID("silver"), label: nil)
          let entities = [Entity(id: EntityID("silver"), type: .location, name: "Silvermoon")]
          XCTAssertEqual(MapView.displayLabel(for: pin, entities: entities), "Silvermoon")
      }

      func test_pinLabel_fallsBackToIdWhenNoEntity() {
          let pin = MapPin(x: 0, y: 0, locationId: EntityID("ruins"), label: nil)
          XCTAssertEqual(MapView.displayLabel(for: pin, entities: []), "ruins")
      }
  }
  ```

- [ ] **Step 2: Run** — expect compile failure (`MapView.displayLabel` unknown).

- [ ] **Step 3: Implement**

  In `MapView.swift`, add a `static func displayLabel(for:entities:) -> String` and update `pinView` to render a chip below the dot:

  ```swift
  extension MapView {
      static func displayLabel(for pin: MapPin, entities: [Entity]) -> String {
          if let label = pin.label, !label.isEmpty { return label }
          if let entity = entities.first(where: { $0.id == pin.locationId }) { return entity.name }
          return pin.locationId.rawValue
      }
  }
  ```

  Update the existing `pinView(idx:pin:fit:)` (or wrapper) so the returned view also includes the label chip beneath the dot. Replace the body that previously returned a `Circle().position(...)` with:

  ```swift
      private func pinView(idx: Int, pin: MapPin, fit: FitRect) -> some View {
          let px = fit.origin.x + CGFloat(pin.clampedX) * fit.size.width
          let py = fit.origin.y + CGFloat(pin.clampedY) * fit.size.height
          let label = Self.displayLabel(for: pin, entities: session.store?.entities ?? [])
          return ZStack(alignment: .top) {
              Circle()
                  .fill(Color.red)
                  .frame(width: 12, height: 12)
                  .overlay(Circle().stroke(Color.white, lineWidth: 1))
              Text(label)
                  .font(.caption2)
                  .lineLimit(1)
                  .truncationMode(.tail)
                  .padding(.horizontal, 4)
                  .padding(.vertical, 1)
                  .background(.regularMaterial)
                  .clipShape(RoundedRectangle(cornerRadius: 3))
                  .frame(maxWidth: 120)
                  .offset(y: 14)
          }
          .position(x: px, y: py + 8) // shift down so dot+label group sits around pin point
          .help(label)
          .onTapGesture { tabs.open(.entity(pin.locationId)) }
          .gesture(pinDragGesture(idx: idx, fit: fit))
          .contextMenu {
              Button(role: .destructive) { deletePin(idx: idx) } label: { Text("Delete pin") }
          }
      }
  ```

- [ ] **Step 4: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: 3 new tests pass; total ~70.

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(map): always-visible pin labels with entity-name fallback"
  ```

---

## Task 4: Snapshot preview window

**Files:**
- Create: `FantasyTavernApp/Sources/Snapshots/SnapshotPreviewSession.swift`
- Create: `FantasyTavernApp/Sources/Snapshots/SnapshotPreviewWindow.swift`
- Modify: `FantasyTavernApp/Sources/Snapshots/SnapshotsView.swift`
- Modify: `FantasyTavernApp/Sources/FantasyTavernAppApp.swift`

- [ ] **Step 1: `SnapshotPreviewSession`** — extracts a snapshot into a temp dir, opens a read-only `WorldStore`, deletes the temp dir on `close()`.

  ```swift
  import Foundation
  import Observation
  import EntityModel
  import WorldStore
  import SnapshotService

  @Observable
  final class SnapshotPreviewSession {
      private(set) var store: WorldStore?
      let archiveName: String
      private let tempFolder: URL

      init(snapshot url: URL) throws {
          self.archiveName = url.lastPathComponent
          let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
              .appendingPathComponent("ft-snapshot-preview-\(UUID().uuidString)")
          try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
          self.tempFolder = tmp
          try Zip.extract(archive: url, to: tmp)
          self.store = try WorldStore.open(tmp)
      }

      func close() {
          try? FileManager.default.removeItem(at: tempFolder)
          store = nil
      }

      deinit { close() }
  }
  ```

- [ ] **Step 2: `SnapshotPreviewWindow`** — read-only viewer using existing Sidebar + Editor pieces, but disabling save by skipping `WorldSession` entirely. Mount a stripped-down `ContentView`-like body:

  ```swift
  import SwiftUI
  import EntityModel

  struct SnapshotPreviewWindow: View {
      @Bindable var session: SnapshotPreviewSession
      @State private var selectedID: EntityID?

      var body: some View {
          NavigationSplitView {
              List {
                  if let world = session.store?.world {
                      Section("\(world.name) — \(session.archiveName)") {
                          ForEach(EntityType.allCases, id: \.self) { type in
                              let entries = session.store?.entities(of: type) ?? []
                              DisclosureGroup(title(for: type, count: entries.count)) {
                                  ForEach(entries, id: \.id) { entity in
                                      Button(entity.name) { selectedID = entity.id }
                                          .buttonStyle(.plain)
                                  }
                              }
                          }
                      }
                  }
              }
              .listStyle(.sidebar)
              .frame(minWidth: 220)
          } detail: {
              if let id = selectedID, let entity = session.store?.entities.first(where: { $0.id == id }) {
                  ScrollView {
                      VStack(alignment: .leading, spacing: 8) {
                          Text(entity.name).font(.title)
                          Text("Type: \(entity.type.rawValue)").font(.caption).foregroundStyle(.secondary)
                          Divider()
                          Text(entity.body).textSelection(.enabled)
                      }
                      .padding(16)
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }
              } else {
                  ContentUnavailableView("Pick an entity to preview", systemImage: "doc.text")
              }
          }
          .frame(minWidth: 720, minHeight: 480)
          .onDisappear { session.close() }
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

- [ ] **Step 3: Open the window from `SnapshotsView`**

  Update `SnapshotsView.swift`:

  Add `@Environment(\.openWindow) private var openWindow` and a "Preview" button alongside Restore:

  ```swift
              HStack {
                  Button("Snapshot Now") {
                      session.snapshotNow()
                      reload()
                  }
                  Spacer()
                  Button("Preview Selected") {
                      if let url = selected {
                          openWindow(value: url)
                      }
                  }
                  .disabled(selected == nil)
                  Button("Restore Selected") {
                      if let url = selected, let entry = entries.first(where: { $0.url == url }) {
                          confirmRestore = entry
                      }
                  }
                  .disabled(selected == nil)
                  Button("Close") { dismiss() }
                      .keyboardShortcut(.cancelAction)
              }
  ```

  `openWindow(value: url)` requires the app to register a `WindowGroup(for: URL.self)` keyed by the snapshot URL — wired in Step 4.

- [ ] **Step 4: Register the preview window in `FantasyTavernAppApp.swift`**

  Read current `FantasyTavernAppApp.swift`. Add a second scene after the main `WindowGroup`:

  ```swift
          WindowGroup("Snapshot Preview", for: URL.self) { $url in
              if let url, let session = try? SnapshotPreviewSession(snapshot: url) {
                  SnapshotPreviewWindow(session: session)
                      .navigationTitle("Preview — \(url.lastPathComponent)")
              } else {
                  ContentUnavailableView("Failed to load preview", systemImage: "exclamationmark.triangle")
              }
          }
  ```

  Place inside `var body: some Scene { … }` after the main `WindowGroup` block, but **inside** the same `body` (Scene composition supports multiple scenes via @SceneBuilder).

- [ ] **Step 5: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, all tests still pass (no new unit tests for the window — it's UI).

- [ ] **Step 6: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(snapshots): read-only Preview window mounted via temp dir"
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

- [ ] **Step 2: Conflict banner**

  1. Open Lyra. Type new text in body (don't wait 0.5s for save).
  2. From Terminal:
     ```
     printf "\nExternal edit at $(date)\n" >> ~/Documents/FantasyTavern/Aetheria/characters/lyra-stormwind.md
     ```
  3. FSEvents fires reload → banner appears: "File changed on disk while you were editing."
  4. Click "Reload from disk" → drafts replaced by disk version.
  5. Repeat steps 1–3. Click "Keep my changes" → your draft saved over disk version.

- [ ] **Step 3: Pin labels**

  1. Maps → overworld. Confirm each pin shows a label chip beneath. Long labels ellipsize.
  2. Hover still shows full tooltip via help.

- [ ] **Step 4: Snapshot preview**

  1. File → Show Snapshots…
  2. Select a snapshot → "Preview Selected" → new window opens titled "Preview — <name>"
  3. Sidebar shows entity types from that snapshot. Click entries → editor pane renders read-only.
  4. Close window → temp dir under `/var/folders/.../ft-snapshot-preview-*` is removed.

- [ ] **Step 5: Tag**

  ```bash
  git tag plan-6-polish-complete
  ```

---

## Deferred from Plan 6 (call out at review)

- Three-way diff view between drafts/disk/snapshot.
- Editable preview (open snapshot as restorable working copy).
- Hide-markdown-markers when caret leaves (Bear/Typora style).
- Pin label drag-to-position.

## Self-Review notes

**Spec coverage:**
- Conflict banner: Tasks 1 + 2. ✓
- Pin labels: Task 3. ✓
- Snapshot preview: Task 4. ✓

**Placeholder scan:** clean.

**Type consistency:**
- `ConflictDecision.decide(baseline:newDisk:drafts:)` consistent Tasks 1 + 2.
- `SnapshotPreviewSession.init(snapshot:)` / `close()` consistent Tasks 1 + 2 + 4.
- `MapView.displayLabel(for:entities:)` consistent Tasks 3.
- `openWindow(value: URL)` matches `WindowGroup("Snapshot Preview", for: URL.self)` typing.
