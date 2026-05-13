# FantasyTavern Plan 4.5 — Timeline & Map Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish Plan 4's timeline + map views: add map zoom & pan, draggable & deletable pins, and ⌘-scroll zoom + "Fit to events" on the timeline.

**Architecture:**
- **Map zoom/pan**: introduce `@State` `mapScale: Double` and `mapPan: CGSize` in `MapView`; apply via `.scaleEffect` + `.offset` to a wrapper that contains the image and the pin overlay together so pins stay anchored. Gestures: `MagnifyGesture` for pinch zoom, `DragGesture` for pan; ⌘-click still creates pins.
- **Pin drag**: each pin has its own `DragGesture` that updates its normalized x/y in `MapDoc.pins` and persists via `WorldStore.saveMap`.
- **Pin delete**: per-pin `.contextMenu` w/ "Delete pin" action.
- **Timeline ⌘-scroll**: bind a small `NSViewRepresentable` over the `ScrollView` content that captures `NSEvent.modifierFlags.contains(.command)` on scroll wheel events and cycles `granularity`.
- **Timeline "Fit to events"**: a toolbar button picks the right granularity for the current event year-span.

**Tech Stack:** Same as prior plans — Swift 5.10+, macOS 14+, SwiftUI, AppKit (`NSEvent`), XCTest.

**Plan 4.5 success criteria:**
1. Pinch (or trackpad pinch) on the map zooms in/out. ⌘scroll on the map also zooms (mac convention). Zoom range clamped to `0.5`–`8`.
2. When zoomed in, dragging anywhere on the empty image pans the view. Pan reset to `.zero` on zoom level `1`.
3. Pins stay glued to their image position during zoom + pan.
4. Drag a pin to move it. On release, the pin's normalized x/y is updated and the map JSON is saved atomically.
5. Right-click a pin → "Delete pin" action removes it (saves JSON immediately).
6. Existing ⌘-click on the image still adds a pin via the location picker.
7. Timeline: ⌘scroll cycles granularity year → decade → century (and back).
8. Timeline: a "Fit" toolbar button picks the smallest granularity whose ticks comfortably span the events.
9. All existing tests stay green; new tests cover the geometry helpers added for zoom math.

**Out of scope (later polish):**
- Multi-touch pinch on Magic Trackpad pinch-zoom precision tuning (use the SwiftUI default).
- Snap-to-grid pin placement.
- Multi-select pin drag.
- Map layer toggling — still deferred to a later plan.
- Timeline drag-to-pan (the ScrollView already handles horizontal pan).

---

## File Structure

```
FantasyTavernApp/Sources/
  Map/
    MapView.swift                 # MODIFY: add scale/pan state, pinch + drag, pin drag/delete
    MapGeometry.swift             # NEW: pure-logic clamping + zoom-anchor math
  Timeline/
    TimelineView.swift            # MODIFY: ⌘scroll zoom; Fit-to-events button
    TimelineWheelCatcher.swift    # NEW: NSViewRepresentable that forwards ⌘scroll events
    TimelineGeometry.swift        # MODIFY: add `fittedGranularity(for: range:)`
FantasyTavernApp/Tests/
  MapGeometryTests.swift          # NEW
  TimelineGeometryTests.swift     # MODIFY: cover fittedGranularity
```

**Why this split:**
- `MapGeometry` keeps the zoom-clamp + pin-anchor math testable without SwiftUI.
- `TimelineWheelCatcher` is a tiny representable; isolating it keeps the timeline view's body readable.
- The fit-to-events logic is pure; extends `TimelineGeometry` which already lives there.

---

## Conventions (carry-over + additions)

- Zoom clamps in `MapGeometry.clamp(scale:)` to `[0.5, 8.0]`.
- When zoom returns to `1.0` (via fit-to-screen or programmatic reset), `mapPan` resets to `.zero`.
- Pin normalized coordinates stay in `[0, 1]`. The drag handler clamps via `MapPin.clampedX`/`clampedY`.
- ⌘scroll on macOS: zoom by a fixed step of `1.2x` per "click" (each wheel notch ≈ one delta event). Trackpad delta events accumulate; clamp at every event.

---

## Task 1: MapGeometry pure-logic helpers

**Files:**
- Create: `FantasyTavernApp/Sources/Map/MapGeometry.swift`
- Create: `FantasyTavernApp/Tests/MapGeometryTests.swift`

- [ ] **Step 1: Failing tests**

  `FantasyTavernApp/Tests/MapGeometryTests.swift`:

  ```swift
  import XCTest
  @testable import FantasyTavernApp

  final class MapGeometryTests: XCTestCase {
      func test_clampScale_floor() {
          XCTAssertEqual(MapGeometry.clamp(scale: 0.1), 0.5, accuracy: 0.0001)
      }
      func test_clampScale_ceiling() {
          XCTAssertEqual(MapGeometry.clamp(scale: 20), 8.0, accuracy: 0.0001)
      }
      func test_clampScale_passthrough() {
          XCTAssertEqual(MapGeometry.clamp(scale: 2.0), 2.0, accuracy: 0.0001)
      }
      func test_clampNormalized_inRange() {
          XCTAssertEqual(MapGeometry.clampNormalized(-0.5), 0.0)
          XCTAssertEqual(MapGeometry.clampNormalized(1.4), 1.0)
          XCTAssertEqual(MapGeometry.clampNormalized(0.3), 0.3)
      }
      func test_scaleStep_zoomsIn_atDeltaUp() {
          XCTAssertEqual(MapGeometry.scaleStep(current: 1.0, deltaY: 1.0), 1.2, accuracy: 0.0001)
      }
      func test_scaleStep_zoomsOut_atDeltaDown() {
          XCTAssertEqual(MapGeometry.scaleStep(current: 1.0, deltaY: -1.0), 1.0 / 1.2, accuracy: 0.0001)
      }
      func test_scaleStep_clampsAtCeiling() {
          XCTAssertEqual(MapGeometry.scaleStep(current: 8.0, deltaY: 1.0), 8.0, accuracy: 0.0001)
      }
  }
  ```

- [ ] **Step 2: Run** — `xcodebuild ... test`, expect compile failure.

- [ ] **Step 3: Implement**

  `FantasyTavernApp/Sources/Map/MapGeometry.swift`:

  ```swift
  import Foundation

  enum MapGeometry {
      static let minScale: Double = 0.5
      static let maxScale: Double = 8.0
      static let zoomStep: Double = 1.2

      static func clamp(scale: Double) -> Double {
          min(maxScale, max(minScale, scale))
      }

      static func clampNormalized(_ v: Double) -> Double {
          min(1.0, max(0.0, v))
      }

      /// Multiplicative zoom step given a vertical scroll delta sign.
      /// deltaY > 0 → zoom in; deltaY < 0 → zoom out.
      static func scaleStep(current: Double, deltaY: Double) -> Double {
          guard deltaY != 0 else { return current }
          let next = deltaY > 0 ? current * zoomStep : current / zoomStep
          return clamp(scale: next)
      }
  }
  ```

- [ ] **Step 4: Run** — 7 new tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(map): MapGeometry helpers (clamp + scaleStep)"
  ```

---

## Task 2: MapView — zoom + pan + pin drag + delete

**Files:**
- Modify: `FantasyTavernApp/Sources/Map/MapView.swift`

- [ ] **Step 1: Overwrite**

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

      @State private var scale: Double = 1.0
      @State private var dragOffset: CGSize = .zero
      @State private var committedOffset: CGSize = .zero

      var body: some View {
          Group {
              if let doc, let image {
                  GeometryReader { geo in
                      let fit = aspectFit(imageSize: image.size, container: geo.size)
                      ZStack(alignment: .topLeading) {
                          imageLayer(doc: doc, image: image, fit: fit)
                      }
                      .frame(width: geo.size.width, height: geo.size.height)
                      .clipped()
                      .contentShape(Rectangle())
                      .gesture(panGesture(fit: fit))
                      .gesture(magnifyGesture())
                      .background(WheelZoomCatcher(scale: $scale))
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
          .toolbar {
              ToolbarItemGroup {
                  Button("Reset") { resetView() }
              }
          }
      }

      // MARK: - layers

      @ViewBuilder
      private func imageLayer(doc: MapDoc, image: NSImage, fit: FitRect) -> some View {
          let totalOffset = CGSize(width: committedOffset.width + dragOffset.width,
                                   height: committedOffset.height + dragOffset.height)
          ZStack(alignment: .topLeading) {
              Image(nsImage: image)
                  .resizable()
                  .scaledToFit()
                  .frame(width: fit.size.width, height: fit.size.height)
                  .offset(x: fit.origin.x, y: fit.origin.y)
                  .simultaneousGesture(SpatialTapGesture(coordinateSpace: .local).modifiers(.command).onEnded { event in
                      pendingPinNormalized = normalize(event.location, in: fit)
                  })
              ForEach(Array(doc.pins.enumerated()), id: \.offset) { idx, pin in
                  pinView(idx: idx, pin: pin, fit: fit)
              }
          }
          .scaleEffect(scale, anchor: .center)
          .offset(totalOffset)
          .animation(.snappy, value: scale)
      }

      private func pinView(idx: Int, pin: MapPin, fit: FitRect) -> some View {
          let px = fit.origin.x + CGFloat(pin.clampedX) * fit.size.width
          let py = fit.origin.y + CGFloat(pin.clampedY) * fit.size.height
          return Circle()
              .fill(Color.red)
              .frame(width: 12, height: 12)
              .overlay(Circle().stroke(Color.white, lineWidth: 1))
              .position(x: px, y: py)
              .help(pin.label ?? pin.locationId.rawValue)
              .onTapGesture { tabs.open(.entity(pin.locationId)) }
              .gesture(pinDragGesture(idx: idx, fit: fit))
              .contextMenu {
                  Button(role: .destructive) { deletePin(idx: idx) } label: { Text("Delete pin") }
              }
      }

      // MARK: - gestures

      private func panGesture(fit: FitRect) -> some Gesture {
          DragGesture(minimumDistance: 1)
              .onChanged { value in
                  dragOffset = value.translation
              }
              .onEnded { value in
                  committedOffset = CGSize(width: committedOffset.width + value.translation.width,
                                           height: committedOffset.height + value.translation.height)
                  dragOffset = .zero
              }
      }

      private func magnifyGesture() -> some Gesture {
          MagnifyGesture()
              .onChanged { value in
                  scale = MapGeometry.clamp(scale: value.magnification * scale)
              }
              .onEnded { _ in /* leave scale as-is */ }
      }

      private func pinDragGesture(idx: Int, fit: FitRect) -> some Gesture {
          DragGesture(minimumDistance: 2)
              .onChanged { value in
                  guard var d = doc, idx < d.pins.count else { return }
                  // Convert screen delta back to normalized space, ignoring scale (we keep pin pinned to image grid).
                  let dx = Double(value.translation.width) / fit.size.width / scale
                  let dy = Double(value.translation.height) / fit.size.height / scale
                  let originalX = d.pins[idx].x
                  let originalY = d.pins[idx].y
                  d.pins[idx].x = MapGeometry.clampNormalized(originalX + dx)
                  d.pins[idx].y = MapGeometry.clampNormalized(originalY + dy)
                  doc = d
                  // restore originals so next .onChanged is delta from start
                  // (DragGesture provides cumulative translation — keep applying to a snapshot stored elsewhere)
                  // The simpler fix below uses startLocation/translation directly via a captured baseline.
                  _ = (originalX, originalY)
              }
              .onEnded { _ in
                  if let d = doc, let store = session.store {
                      try? store.saveMap(d, name: name)
                  }
              }
      }

      // MARK: - helpers (load/add/delete)

      private func load() {
          guard let store = session.store else { loadError = "No world open"; return }
          do {
              let d = try store.loadMap(named: name)
              doc = d
              let imageURL = store.world.folder.appendingPathComponent("maps").appendingPathComponent(d.image)
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

      private func deletePin(idx: Int) {
          guard var d = doc, idx < d.pins.count, let store = session.store else { return }
          d.pins.remove(at: idx)
          try? store.saveMap(d, name: name)
          doc = d
      }

      private func resetView() {
          scale = 1.0
          committedOffset = .zero
          dragOffset = .zero
      }

      // MARK: - layout

      struct FitRect {
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
          return CGPoint(x: MapGeometry.clampNormalized(relX), y: MapGeometry.clampNormalized(relY))
      }
  }

  // MARK: - ⌘scroll wheel catcher

  private struct WheelZoomCatcher: NSViewRepresentable {
      @Binding var scale: Double

      func makeNSView(context: Context) -> NSView {
          let v = WheelView()
          v.onWheel = { event in
              guard event.modifierFlags.contains(.command) else { return false }
              let delta = event.scrollingDeltaY
              if abs(delta) < 0.01 { return false }
              scale = MapGeometry.scaleStep(current: scale, deltaY: Double(delta))
              return true
          }
          return v
      }
      func updateNSView(_ nsView: NSView, context: Context) {}
  }

  private final class WheelView: NSView {
      var onWheel: ((NSEvent) -> Bool)?
      override var acceptsFirstResponder: Bool { true }
      override func scrollWheel(with event: NSEvent) {
          if onWheel?(event) == true { return }
          super.scrollWheel(with: event)
      }
  }
  ```

  **Note on pin drag baseline math.** SwiftUI's `DragGesture.translation` is cumulative from the gesture's start. Applying `originalX + dx` in `onChanged` would compound — the version above is structurally close but will drift. Refactor with a per-gesture baseline:

  Replace the `pinDragGesture` body with this corrected version (use it instead of the one above):

  ```swift
      @State private var pinDragBaseline: [Int: CGPoint] = [:]

      private func pinDragGesture(idx: Int, fit: FitRect) -> some Gesture {
          DragGesture(minimumDistance: 2)
              .onChanged { value in
                  guard var d = doc, idx < d.pins.count else { return }
                  if pinDragBaseline[idx] == nil {
                      pinDragBaseline[idx] = CGPoint(x: d.pins[idx].x, y: d.pins[idx].y)
                  }
                  guard let base = pinDragBaseline[idx] else { return }
                  let dx = Double(value.translation.width) / fit.size.width / scale
                  let dy = Double(value.translation.height) / fit.size.height / scale
                  d.pins[idx].x = MapGeometry.clampNormalized(Double(base.x) + dx)
                  d.pins[idx].y = MapGeometry.clampNormalized(Double(base.y) + dy)
                  doc = d
              }
              .onEnded { _ in
                  pinDragBaseline[idx] = nil
                  if let d = doc, let store = session.store {
                      try? store.saveMap(d, name: name)
                  }
              }
      }
  ```

  Add `@State private var pinDragBaseline: [Int: CGPoint] = [:]` to the view's properties.

- [ ] **Step 2: Build + run**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -15
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, all tests pass.

- [ ] **Step 3: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(map): pinch + ⌘scroll zoom, pan, drag pins, delete via context menu"
  ```

---

## Task 3: TimelineGeometry — `fittedGranularity`

**Files:**
- Modify: `FantasyTavernApp/Sources/Timeline/TimelineGeometry.swift`
- Modify: `FantasyTavernApp/Tests/TimelineGeometryTests.swift`

- [ ] **Step 1: Failing tests**

  Append to `TimelineGeometryTests.swift`:

  ```swift
      func test_fittedGranularity_small_picksYear() {
          // 5-year span → year
          XCTAssertEqual(TimelineGeometry.fittedGranularity(forSpan: 5), .year)
      }
      func test_fittedGranularity_medium_picksDecade() {
          // 80-year span → decade
          XCTAssertEqual(TimelineGeometry.fittedGranularity(forSpan: 80), .decade)
      }
      func test_fittedGranularity_large_picksCentury() {
          XCTAssertEqual(TimelineGeometry.fittedGranularity(forSpan: 5000), .century)
      }
      func test_fittedGranularity_zero_defaultsToDecade() {
          XCTAssertEqual(TimelineGeometry.fittedGranularity(forSpan: 0), .decade)
      }
  ```

- [ ] **Step 2: Run** — expect compile failure.

- [ ] **Step 3: Implement**

  In `TimelineGeometry.swift`, append inside the enum:

  ```swift
      /// Pick the granularity whose tick step keeps a span readable
      /// (target ~10-30 visible ticks across the span).
      static func fittedGranularity(forSpan years: Int) -> TimelineGranularity {
          let span = max(0, years)
          if span <= 20 { return .year }
          if span <= 400 { return .decade }
          return .century
      }
  ```

  Note: `span == 0` falls into the `<= 20` branch → `.year`. The test expects `.decade` — adjust the test or the impl. The plan picks **impl**: change to:

  ```swift
      static func fittedGranularity(forSpan years: Int) -> TimelineGranularity {
          let span = max(0, years)
          if span == 0 { return .decade }
          if span <= 20 { return .year }
          if span <= 400 { return .decade }
          return .century
      }
  ```

- [ ] **Step 4: Run** — expect 4 new tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(timeline): TimelineGeometry.fittedGranularity helper"
  ```

---

## Task 4: TimelineWheelCatcher + TimelineView ⌘scroll + Fit button

**Files:**
- Create: `FantasyTavernApp/Sources/Timeline/TimelineWheelCatcher.swift`
- Modify: `FantasyTavernApp/Sources/Timeline/TimelineView.swift`

- [ ] **Step 1: WheelCatcher**

  `FantasyTavernApp/Sources/Timeline/TimelineWheelCatcher.swift`:

  ```swift
  import SwiftUI
  import AppKit

  /// Forwards ⌘scroll wheel events to a callback. Returns true if the event was consumed.
  struct TimelineWheelCatcher: NSViewRepresentable {
      let onCommandScroll: (CGFloat) -> Void

      func makeNSView(context: Context) -> NSView {
          let v = WheelView()
          v.onWheel = { event in
              guard event.modifierFlags.contains(.command) else { return false }
              onCommandScroll(event.scrollingDeltaY)
              return true
          }
          return v
      }
      func updateNSView(_ nsView: NSView, context: Context) {}

      private final class WheelView: NSView {
          var onWheel: ((NSEvent) -> Bool)?
          override var acceptsFirstResponder: Bool { true }
          override func scrollWheel(with event: NSEvent) {
              if onWheel?(event) == true { return }
              super.scrollWheel(with: event)
          }
      }
  }
  ```

- [ ] **Step 2: Wire into `TimelineView`**

  Read the existing `TimelineView.swift`. Insert two changes:

  1. Below `@State private var granularity:` line, add:

     ```swift
     @State private var wheelAccumulator: CGFloat = 0
     ```

  2. Inside the outermost `GeometryReader { geo in … }` body, attach a `.background(TimelineWheelCatcher { delta in handleWheel(delta) })` modifier to the ZStack containing era bands + axis + dots.

  3. Inside the `toolbar` `ToolbarItemGroup`, add (after the existing Picker):

     ```swift
     Button("Fit") { fitToEvents() }
     ```

  4. Add these methods inside `TimelineView`:

     ```swift
     private func handleWheel(_ delta: CGFloat) {
         wheelAccumulator += delta
         let threshold: CGFloat = 8 // small swipes shouldn't change zoom
         if wheelAccumulator > threshold {
             zoomIn(); wheelAccumulator = 0
         } else if wheelAccumulator < -threshold {
             zoomOut(); wheelAccumulator = 0
         }
     }

     private func zoomIn() {
         switch granularity {
         case .century: granularity = .decade
         case .decade:  granularity = .year
         case .year:    break
         }
     }

     private func zoomOut() {
         switch granularity {
         case .year:   granularity = .decade
         case .decade: granularity = .century
         case .century: break
         }
     }

     private func fitToEvents() {
         let years = events.map(\.year)
         let span = (years.max() ?? 0) - (years.min() ?? 0)
         granularity = TimelineGeometry.fittedGranularity(forSpan: span)
     }
     ```

- [ ] **Step 3: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, all tests pass.

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(timeline): ⌘scroll zoom + Fit-to-events toolbar button"
  ```

---

## Task 5: Manual acceptance

**Files:** none.

- [ ] **Step 1: Build + launch**

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -3
  pkill -f FantasyTavernApp 2>/dev/null || true
  sleep 1
  open ~/Library/Developer/Xcode/DerivedData/FantasyTavern-cjpexdvcsmhrwcafqhtvzpbgihqg/Build/Products/Debug/FantasyTavernApp.app
  ```

- [ ] **Step 2: Map**

  1. Open Aetheria → Maps → overworld.
  2. Pinch trackpad (or ⌘scroll up) → image zooms in. ⌘scroll down → out. Scale clamps below 0.5 and above 8.
  3. Drag empty area → image pans. Pin positions move with image.
  4. Click "Reset" in toolbar → zoom 1, pan 0.
  5. Drag an existing pin → it follows the cursor and saves on release. Inspect `maps/overworld.json` → x/y updated.
  6. Right-click a pin → "Delete pin" → pin vanishes; JSON updated.
  7. ⌘-click empty image → location picker still works.

- [ ] **Step 3: Timeline**

  1. Open Aetheria → Timeline.
  2. ⌘scroll up → granularity → year. ⌘scroll down → decade → century.
  3. Click "Fit" → picks granularity for the current event span.

- [ ] **Step 4: Tag**

  ```bash
  git tag plan-4-5-timeline-map-polish-complete
  ```

---

## Deferred from Plan 4.5 (call out at review)

- Pin labels visible by default (currently only on hover via `.help(...)`).
- Snap-to-grid pin placement.
- Multi-touch / pinch-zoom calibration on trackpads.
- Timeline horizontal pan via drag (ScrollView already covers it; native trackpad scroll works).
- Map fit-to-image keyboard shortcut.

## Self-Review notes

**Spec coverage:**
- Map zoom (pinch + ⌘scroll): Task 2. ✓
- Map pan: Task 2. ✓
- Pin drag: Task 2 (with corrected baseline math). ✓
- Pin delete: Task 2 (context menu). ✓
- Timeline ⌘scroll: Task 4. ✓
- Timeline Fit: Tasks 3 + 4. ✓

**Placeholder scan:** no TBDs; the only "interpretation" note is the pin-drag baseline correction at the bottom of Task 2 Step 1 — engineer must use the *corrected* version (the second snippet).

**Type consistency:**
- `MapGeometry.clamp(scale:)` / `clampNormalized(_:)` / `scaleStep(current:deltaY:)` consistent across Tasks 1 + 2.
- `TimelineGeometry.fittedGranularity(forSpan:)` Tasks 3 + 4.
- `TimelineGranularity` cases (year/decade/century) — unchanged from Plan 4.
- `MapPin.clampedX`/`clampedY` — pre-existing, unchanged.
