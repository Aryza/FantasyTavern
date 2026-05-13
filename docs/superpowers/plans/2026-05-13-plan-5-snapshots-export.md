# FantasyTavern Plan 5 — Snapshots & Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add auto-snapshots (10-min interval, retention-policy pruned) with manual + restore UI, and a File → Export submenu that writes single entity, type folder, or whole world as markdown / zipped markdown.

**Architecture:**
- New SPM package `SnapshotService` (pure logic + small system-tool wrappers). Holds: `Zip` (shell out to `/usr/bin/zip` and `/usr/bin/unzip` via `Process`), `RetentionPolicy` (pure function over snapshot timestamps), and `SnapshotService` (orchestration).
- App-level `WorldSession` owns a `SnapshotScheduler` that fires every 10 minutes; only writes a snapshot if `isDirty` flipped since the last one. `save(_:)` sets `isDirty = true`.
- SwiftUI `SnapshotsView` sheet listing snapshots w/ Restore + Preview buttons. Restore archives current state first (`pre-restore-{ts}.zip`) then replaces world content.
- Export menu: File → Export → Markdown → Entity / Type / Whole world. Single entity = save `.md` to chosen path. Type or world = zip via `Zip.create(...)`.

**Tech Stack:** Same as prior plans — Swift 5.10+, macOS 14+, SwiftUI, system `/usr/bin/zip` + `/usr/bin/unzip` via `Process`, XCTest.

**Plan 5 success criteria:**
1. Editing an entity flips `WorldSession.isDirty`. After 10 min (or via `File → Snapshot Now`), a zip lands at `<world>/.fantasytavern/snapshots/<ISO>.zip` covering everything except `.fantasytavern/`.
2. `File → Show Snapshots…` opens a sheet listing all snapshots newest-first w/ timestamp + size.
3. Selecting a snapshot + Restore archives current state into `pre-restore-<ISO>.zip`, then unpacks the chosen snapshot back into the world folder. The FSEvents watcher reloads the in-memory world automatically.
4. Retention runs after every successful snapshot: keep all within 24h, hourly buckets for last 7d, daily for last 30d, drop older. Pruned files removed from disk.
5. `File → Export → Markdown → Current Entity…` writes the active entity's `.md` to a user-chosen file path.
6. `File → Export → Markdown → Type (current entity's type)…` writes a zip of that entity-type's folder to a user-chosen file path.
7. `File → Export → Markdown → Whole World…` writes a zip of the entire world (excluding `.fantasytavern/`) to a user-chosen file path.
8. All package tests stay green; new tests cover `Zip` round-trip, `RetentionPolicy` decisions, and `SnapshotService` snapshot/list/restore.

**Out of scope (later plans / future polish):**
- PDF export (deferred per Plan 1 spec).
- Conflict UI when restoring while a tab has unsaved edits — Plan 5 simply overwrites; the user is warned via a confirm dialog before restore.
- Per-entity export to non-markdown formats (HTML, etc.).
- Diff view between current state and a snapshot.

---

## File Structure

```
Packages/
  SnapshotService/                                # NEW pure-logic + thin shell-out package
    Package.swift
    Sources/SnapshotService/
      Zip.swift                                   # Process wrappers for /usr/bin/zip + unzip
      RetentionPolicy.swift                       # pure: [Date] -> (keep, prune)
      SnapshotService.swift                       # snapshot(world:), list(in:), restore(name:to:)
    Tests/SnapshotServiceTests/
      ZipTests.swift
      RetentionPolicyTests.swift
      SnapshotServiceTests.swift

FantasyTavernApp/Sources/
  Snapshots/
    SnapshotScheduler.swift                       # NEW: timer + dirty flag
    SnapshotsView.swift                           # NEW: sheet UI
  WorldSession.swift                              # MODIFY: own scheduler, isDirty, snapshotNow, restore
  Commands/AppCommands.swift                      # MODIFY: Snapshot Now / Show Snapshots / Export submenu
  Export/
    ExportService.swift                           # NEW: writeEntity(_:to:), zipFolder(_:to:)
FantasyTavernApp/Tests/
  SnapshotSchedulerTests.swift                    # NEW
  ExportServiceTests.swift                        # NEW
```

**Why this split:**
- `Zip` is the only file that shells out — keeps process I/O in one place.
- `RetentionPolicy` is pure; trivially testable.
- `SnapshotScheduler` is small and observable; the sheet view is passive.
- `ExportService` collects file-write helpers used by the menu so the menu stays declarative.

---

## Conventions (carry-over + additions)

- **Snapshot filename:** ISO 8601 UTC, colons replaced w/ dashes (filesystem-safe): `2026-05-13T15-04-22Z.zip`.
- **Snapshot folder:** `<world>/.fantasytavern/snapshots/`. `.fantasytavern/` already gitignored in default user worlds; the snapshot routine excludes it from the zip.
- **Pre-restore archive:** `<world>/.fantasytavern/snapshots/pre-restore-<ISO>.zip` — also indexed in retention.
- **Zip command:** `cd <world>; /usr/bin/zip -r -q <archive> . -x ".fantasytavern/*"`. Quiet, recursive. Exit code 0 = success. Other codes throw.
- **Unzip command:** `/usr/bin/unzip -q -o <archive> -d <dest>`. `-o` overwrites without prompt.
- **Scheduler interval:** 10 minutes (`600` s). On `WorldSession.save(_:)`, set `isDirty = true`. On successful snapshot, set `isDirty = false`.
- **Manual snapshot:** File menu → "Snapshot Now". Always writes, regardless of dirty.

---

## Task 1: SnapshotService package scaffold + Zip

**Files:**
- Create: `Packages/SnapshotService/Package.swift`
- Create: `Packages/SnapshotService/Sources/SnapshotService/Zip.swift`
- Create: `Packages/SnapshotService/Tests/SnapshotServiceTests/ZipTests.swift`

- [ ] **Step 1: Scaffold dirs + Package.swift**

  ```bash
  mkdir -p Packages/SnapshotService/Sources/SnapshotService
  mkdir -p Packages/SnapshotService/Tests/SnapshotServiceTests
  ```

  `Packages/SnapshotService/Package.swift`:

  ```swift
  // swift-tools-version: 5.10
  import PackageDescription

  let package = Package(
      name: "SnapshotService",
      platforms: [.macOS(.v14)],
      products: [
          .library(name: "SnapshotService", targets: ["SnapshotService"]),
      ],
      dependencies: [],
      targets: [
          .target(name: "SnapshotService"),
          .testTarget(name: "SnapshotServiceTests", dependencies: ["SnapshotService"]),
      ]
  )
  ```

- [ ] **Step 2: Failing tests**

  `Packages/SnapshotService/Tests/SnapshotServiceTests/ZipTests.swift`:

  ```swift
  import XCTest
  @testable import SnapshotService

  final class ZipTests: XCTestCase {
      var tmp: URL!

      override func setUpWithError() throws {
          tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
      }
      override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

      func test_createAndExtract_roundTrip() throws {
          let src = tmp.appendingPathComponent("src")
          try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
          try "hello".write(to: src.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
          try "world".write(to: src.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

          let archive = tmp.appendingPathComponent("out.zip")
          try Zip.create(folder: src, to: archive, exclude: [])
          XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))

          let dest = tmp.appendingPathComponent("dest")
          try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
          try Zip.extract(archive: archive, to: dest)
          let aText = try String(contentsOf: dest.appendingPathComponent("a.txt"), encoding: .utf8)
          XCTAssertEqual(aText, "hello")
      }

      func test_create_excludesGlob() throws {
          let src = tmp.appendingPathComponent("src")
          try FileManager.default.createDirectory(at: src.appendingPathComponent("keep"), withIntermediateDirectories: true)
          try FileManager.default.createDirectory(at: src.appendingPathComponent(".fantasytavern/snapshots"), withIntermediateDirectories: true)
          try "x".write(to: src.appendingPathComponent("keep/y.txt"), atomically: true, encoding: .utf8)
          try "secret".write(to: src.appendingPathComponent(".fantasytavern/snapshots/old.zip"), atomically: true, encoding: .utf8)

          let archive = tmp.appendingPathComponent("out.zip")
          try Zip.create(folder: src, to: archive, exclude: [".fantasytavern/*"])

          let dest = tmp.appendingPathComponent("dest")
          try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
          try Zip.extract(archive: archive, to: dest)
          XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("keep/y.txt").path))
          XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent(".fantasytavern/snapshots/old.zip").path))
      }

      func test_extract_missingArchive_throws() {
          let missing = tmp.appendingPathComponent("nope.zip")
          let dest = tmp.appendingPathComponent("dest")
          try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
          XCTAssertThrowsError(try Zip.extract(archive: missing, to: dest))
      }
  }
  ```

- [ ] **Step 3: Run to verify failure**

  ```bash
  swift test --package-path Packages/SnapshotService 2>&1 | tail -15
  ```

  Expected: compile failure (`Zip` unknown).

- [ ] **Step 4: Implement**

  `Packages/SnapshotService/Sources/SnapshotService/Zip.swift`:

  ```swift
  import Foundation

  public enum ZipError: Error {
      case zipFailed(Int32, String)
      case unzipFailed(Int32, String)
      case archiveMissing(URL)
  }

  public enum Zip {
      public static func create(folder: URL, to archive: URL, exclude: [String] = []) throws {
          let proc = Process()
          proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
          var args = ["-r", "-q", archive.path, "."]
          for pattern in exclude {
              args.append(contentsOf: ["-x", pattern])
          }
          proc.arguments = args
          proc.currentDirectoryURL = folder
          let pipe = Pipe()
          proc.standardError = pipe
          proc.standardOutput = Pipe()
          try proc.run()
          proc.waitUntilExit()
          if proc.terminationStatus != 0 {
              let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
              let msg = String(data: data ?? Data(), encoding: .utf8) ?? ""
              throw ZipError.zipFailed(proc.terminationStatus, msg)
          }
      }

      public static func extract(archive: URL, to destination: URL) throws {
          guard FileManager.default.fileExists(atPath: archive.path) else {
              throw ZipError.archiveMissing(archive)
          }
          let proc = Process()
          proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
          proc.arguments = ["-q", "-o", archive.path, "-d", destination.path]
          let pipe = Pipe()
          proc.standardError = pipe
          proc.standardOutput = Pipe()
          try proc.run()
          proc.waitUntilExit()
          if proc.terminationStatus != 0 {
              let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
              let msg = String(data: data ?? Data(), encoding: .utf8) ?? ""
              throw ZipError.unzipFailed(proc.terminationStatus, msg)
          }
      }
  }
  ```

  Note: `Pipe.fileHandleForReading.readToEnd()` returns `Data?` — the cast above with `(try? …) ?? Data()` already collapses optionality. The second optional unwrap (`data ?? Data()`) is redundant; Swift will warn — fix at write-time by dropping the extra `?? Data()`. Final form:

  ```swift
          if proc.terminationStatus != 0 {
              let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
              let msg = String(data: data, encoding: .utf8) ?? ""
              throw ZipError.zipFailed(proc.terminationStatus, msg)
          }
  ```

  Apply this pattern to both functions.

- [ ] **Step 5: Run tests** — `swift test --package-path Packages/SnapshotService`. Expected: 3 tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add Packages/SnapshotService
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(SnapshotService): Zip wrapper (system zip/unzip)"
  ```

---

## Task 2: RetentionPolicy

**Files:**
- Create: `Packages/SnapshotService/Sources/SnapshotService/RetentionPolicy.swift`
- Create: `Packages/SnapshotService/Tests/SnapshotServiceTests/RetentionPolicyTests.swift`

- [ ] **Step 1: Failing tests**

  `Packages/SnapshotService/Tests/SnapshotServiceTests/RetentionPolicyTests.swift`:

  ```swift
  import XCTest
  @testable import SnapshotService

  final class RetentionPolicyTests: XCTestCase {
      private func d(hoursAgo: Double, from now: Date) -> Date {
          now.addingTimeInterval(-hoursAgo * 3600)
      }

      func test_keepEverythingWithin24h() {
          let now = Date(timeIntervalSince1970: 1_700_000_000)
          let stamps = [d(hoursAgo: 0.1, from: now),
                        d(hoursAgo: 5,   from: now),
                        d(hoursAgo: 23,  from: now)]
          let decision = RetentionPolicy.decide(stamps: stamps, now: now)
          XCTAssertEqual(Set(decision.keep), Set(stamps))
          XCTAssertTrue(decision.prune.isEmpty)
      }

      func test_hourlyBucketing_betweenDay1And7() {
          let now = Date(timeIntervalSince1970: 1_700_000_000)
          // Two stamps in the same hour, ~30h ago → keep newest, prune older
          let newer = d(hoursAgo: 30, from: now)
          let older = newer.addingTimeInterval(-10) // same hour bucket
          let decision = RetentionPolicy.decide(stamps: [newer, older], now: now)
          XCTAssertEqual(decision.keep, [newer])
          XCTAssertEqual(decision.prune, [older])
      }

      func test_dailyBucketing_betweenDay7And30() {
          let now = Date(timeIntervalSince1970: 1_700_000_000)
          // Two stamps on the same day ~10 days ago → keep newer, prune older
          let newer = d(hoursAgo: 24*10 + 1, from: now)
          let older = newer.addingTimeInterval(-3600)
          let decision = RetentionPolicy.decide(stamps: [newer, older], now: now)
          XCTAssertEqual(decision.keep, [newer])
          XCTAssertEqual(decision.prune, [older])
      }

      func test_droppedAfter30Days() {
          let now = Date(timeIntervalSince1970: 1_700_000_000)
          let ancient = d(hoursAgo: 24*40, from: now)
          let decision = RetentionPolicy.decide(stamps: [ancient], now: now)
          XCTAssertTrue(decision.keep.isEmpty)
          XCTAssertEqual(decision.prune, [ancient])
      }
  }
  ```

- [ ] **Step 2: Run** — expect compile failure.

- [ ] **Step 3: Implement**

  `Packages/SnapshotService/Sources/SnapshotService/RetentionPolicy.swift`:

  ```swift
  import Foundation

  public enum RetentionPolicy {
      public struct Decision: Equatable {
          public let keep: [Date]
          public let prune: [Date]
      }

      public static func decide(stamps input: [Date], now: Date) -> Decision {
          var keep: [Date] = []
          var prune: [Date] = []
          let sorted = input.sorted(by: >) // newest first
          var seenHourBuckets: Set<Int> = []
          var seenDayBuckets: Set<Int> = []

          for s in sorted {
              let age = now.timeIntervalSince(s)
              if age < 0 { keep.append(s); continue } // future-dated: keep
              let hours = age / 3600
              if hours <= 24 {
                  keep.append(s)
              } else if hours <= 24 * 7 {
                  let bucket = Int(s.timeIntervalSince1970 / 3600)
                  if seenHourBuckets.insert(bucket).inserted { keep.append(s) }
                  else { prune.append(s) }
              } else if hours <= 24 * 30 {
                  let bucket = Int(s.timeIntervalSince1970 / 86400)
                  if seenDayBuckets.insert(bucket).inserted { keep.append(s) }
                  else { prune.append(s) }
              } else {
                  prune.append(s)
              }
          }
          return Decision(keep: keep, prune: prune)
      }
  }
  ```

- [ ] **Step 4: Run** — expect 4 new tests pass; package total = 7.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/SnapshotService
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(SnapshotService): RetentionPolicy (24h/7d/30d buckets)"
  ```

---

## Task 3: SnapshotService API

**Files:**
- Create: `Packages/SnapshotService/Sources/SnapshotService/SnapshotService.swift`
- Create: `Packages/SnapshotService/Tests/SnapshotServiceTests/SnapshotServiceTests.swift`

- [ ] **Step 1: Failing tests**

  `Packages/SnapshotService/Tests/SnapshotServiceTests/SnapshotServiceTests.swift`:

  ```swift
  import XCTest
  @testable import SnapshotService

  final class SnapshotServiceTests: XCTestCase {
      var tmp: URL!

      override func setUpWithError() throws {
          tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
      }
      override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

      private func makeWorld() throws -> URL {
          let w = tmp.appendingPathComponent("world")
          try FileManager.default.createDirectory(at: w.appendingPathComponent("characters"), withIntermediateDirectories: true)
          try "hello".write(to: w.appendingPathComponent("characters/lyra.md"), atomically: true, encoding: .utf8)
          return w
      }

      func test_snapshot_writesArchive_andListed() throws {
          let world = try makeWorld()
          let date = Date(timeIntervalSince1970: 1_700_000_000)
          let url = try SnapshotService.snapshot(world: world, now: date)
          XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
          let listed = SnapshotService.list(in: world)
          XCTAssertEqual(listed.map(\.url), [url])
      }

      func test_snapshot_excludesDotFantasytavern() throws {
          let world = try makeWorld()
          let dotDir = world.appendingPathComponent(".fantasytavern/snapshots")
          try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
          try "old".write(to: dotDir.appendingPathComponent("old.zip"), atomically: true, encoding: .utf8)

          let url = try SnapshotService.snapshot(world: world)
          let dest = tmp.appendingPathComponent("extract")
          try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
          try Zip.extract(archive: url, to: dest)
          XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent(".fantasytavern/snapshots/old.zip").path))
          XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("characters/lyra.md").path))
      }

      func test_restore_archivesCurrentAndReplaces() throws {
          let world = try makeWorld()
          let snap = try SnapshotService.snapshot(world: world)
          // Modify world after snapshot
          try "changed".write(to: world.appendingPathComponent("characters/lyra.md"), atomically: true, encoding: .utf8)
          try SnapshotService.restore(snapshot: snap, world: world)
          let after = try String(contentsOf: world.appendingPathComponent("characters/lyra.md"), encoding: .utf8)
          XCTAssertEqual(after, "hello")
          let listed = SnapshotService.list(in: world)
          XCTAssertTrue(listed.contains { $0.url.lastPathComponent.hasPrefix("pre-restore-") })
      }

      func test_prune_removesAccordingToPolicy() throws {
          let world = try makeWorld()
          let dir = world.appendingPathComponent(".fantasytavern/snapshots")
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          // Plant fake-old file
          let oldURL = dir.appendingPathComponent("2020-01-01T00-00-00Z.zip")
          try Data().write(to: oldURL)
          try SnapshotService.prune(world: world, now: Date())
          XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
      }
  }
  ```

- [ ] **Step 2: Run** — expect compile failure.

- [ ] **Step 3: Implement**

  `Packages/SnapshotService/Sources/SnapshotService/SnapshotService.swift`:

  ```swift
  import Foundation

  public enum SnapshotServiceError: Error {
      case worldMissing(URL)
  }

  public struct SnapshotEntry: Equatable {
      public let url: URL
      public let date: Date
      public let size: Int64
  }

  public enum SnapshotService {
      private static let isoFormatter: ISO8601DateFormatter = {
          let f = ISO8601DateFormatter()
          f.formatOptions = [.withInternetDateTime]
          return f
      }()

      private static let filenameDateFormatter: DateFormatter = {
          let f = DateFormatter()
          f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
          f.timeZone = TimeZone(identifier: "UTC")
          f.locale = Locale(identifier: "en_US_POSIX")
          return f
      }()

      public static func snapshotsDir(in world: URL) -> URL {
          world.appendingPathComponent(".fantasytavern/snapshots")
      }

      @discardableResult
      public static func snapshot(world: URL, now: Date = Date(), prefix: String = "") throws -> URL {
          guard FileManager.default.fileExists(atPath: world.path) else {
              throw SnapshotServiceError.worldMissing(world)
          }
          let dir = snapshotsDir(in: world)
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          let name = "\(prefix)\(filenameDateFormatter.string(from: now)).zip"
          let archive = dir.appendingPathComponent(name)
          try Zip.create(folder: world, to: archive, exclude: [".fantasytavern/*"])
          return archive
      }

      public static func list(in world: URL) -> [SnapshotEntry] {
          let dir = snapshotsDir(in: world)
          guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
              return []
          }
          let entries: [SnapshotEntry] = files.compactMap { url in
              guard url.pathExtension.lowercased() == "zip" else { return nil }
              let stem = url.deletingPathExtension().lastPathComponent
              let candidates = [stem, stem.replacingOccurrences(of: "pre-restore-", with: "")]
              let date = candidates.compactMap { filenameDateFormatter.date(from: $0) }.first
                  ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                  ?? .distantPast
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
              return SnapshotEntry(url: url, date: date, size: size)
          }
          return entries.sorted { $0.date > $1.date }
      }

      public static func restore(snapshot: URL, world: URL) throws {
          // Archive current state first
          _ = try Self.snapshot(world: world, now: Date(), prefix: "pre-restore-")
          // Wipe non-hidden contents (leave .fantasytavern alone — contains snapshots dir)
          let fm = FileManager.default
          let entries = try fm.contentsOfDirectory(atPath: world.path)
          for entry in entries where entry != ".fantasytavern" {
              try? fm.removeItem(at: world.appendingPathComponent(entry))
          }
          // Extract the chosen snapshot into the world folder
          try Zip.extract(archive: snapshot, to: world)
      }

      public static func prune(world: URL, now: Date = Date()) throws {
          let entries = list(in: world)
          let decision = RetentionPolicy.decide(stamps: entries.map(\.date), now: now)
          let pruneSet = Set(decision.prune)
          for entry in entries where pruneSet.contains(entry.date) {
              try? FileManager.default.removeItem(at: entry.url)
          }
      }
  }
  ```

- [ ] **Step 4: Run** — expect 4 new tests pass; package total = 11.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/SnapshotService
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(SnapshotService): snapshot/list/restore/prune"
  ```

---

## Task 4: project.yml — link SnapshotService into app

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Edit**

  Under `packages:` append:
  ```yaml
    SnapshotService:
      path: Packages/SnapshotService
  ```

  Under `targets.FantasyTavernApp.dependencies:` append:
  ```yaml
        - package: SnapshotService
  ```

- [ ] **Step 2: Regenerate + build**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -5
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, 59 tests still pass.

- [ ] **Step 3: Commit**

  ```bash
  git add project.yml
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "chore(project): link SnapshotService into app target"
  ```

---

## Task 5: SnapshotScheduler + WorldSession integration

**Files:**
- Create: `FantasyTavernApp/Sources/Snapshots/SnapshotScheduler.swift`
- Modify: `FantasyTavernApp/Sources/WorldSession.swift`
- Create: `FantasyTavernApp/Tests/SnapshotSchedulerTests.swift`

- [ ] **Step 1: Failing tests**

  `FantasyTavernApp/Tests/SnapshotSchedulerTests.swift`:

  ```swift
  import XCTest
  @testable import FantasyTavernApp

  final class SnapshotSchedulerTests: XCTestCase {
      func test_fire_callsSnapshotOnlyIfDirty() {
          var calls = 0
          let scheduler = SnapshotScheduler(interval: 60) { calls += 1 }
          scheduler.markDirty()
          scheduler.fireForTesting()
          XCTAssertEqual(calls, 1)
          scheduler.fireForTesting()
          XCTAssertEqual(calls, 1, "Second fire without new dirty mark should not snapshot")
          scheduler.markDirty()
          scheduler.fireForTesting()
          XCTAssertEqual(calls, 2)
      }

      func test_isDirty_clearedAfterFire() {
          var calls = 0
          let scheduler = SnapshotScheduler(interval: 60) { calls += 1 }
          scheduler.markDirty()
          XCTAssertTrue(scheduler.isDirty)
          scheduler.fireForTesting()
          XCTAssertFalse(scheduler.isDirty)
      }
  }
  ```

- [ ] **Step 2: Run** — expect compile failure.

- [ ] **Step 3: Implement**

  `FantasyTavernApp/Sources/Snapshots/SnapshotScheduler.swift`:

  ```swift
  import Foundation
  import Observation

  @Observable
  final class SnapshotScheduler {
      private(set) var isDirty: Bool = false
      private let interval: TimeInterval
      private let perform: () -> Void
      private var timer: Timer?

      init(interval: TimeInterval = 600, perform: @escaping () -> Void) {
          self.interval = interval
          self.perform = perform
      }

      func start() {
          stop()
          timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
              self?.fireIfDirty()
          }
      }

      func stop() {
          timer?.invalidate()
          timer = nil
      }

      func markDirty() {
          isDirty = true
      }

      func fireForTesting() {
          fireIfDirty()
      }

      private func fireIfDirty() {
          guard isDirty else { return }
          perform()
          isDirty = false
      }

      deinit { stop() }
  }
  ```

- [ ] **Step 4: Update `WorldSession`**

  Add `import SnapshotService` at top. Add property + wiring:

  ```swift
      private var scheduler: SnapshotScheduler?

      // … inside openWorld, after rebuildSearch + startWatching:
          scheduler?.stop()
          let s = SnapshotScheduler { [weak self] in
              guard let self, let folder = self.store?.world.folder else { return }
              _ = try? SnapshotService.snapshot(world: folder)
              try? SnapshotService.prune(world: folder)
          }
          s.start()
          scheduler = s

      // … inside save(_:), after rebuildLinks + searchIndex.upsert:
          scheduler?.markDirty()

      // … add public methods:
      public func snapshotNow() {
          guard let folder = store?.world.folder else { return }
          _ = try? SnapshotService.snapshot(world: folder)
          try? SnapshotService.prune(world: folder)
          scheduler?.markDirty() // future runs still trigger if user edits again
      }

      public func listSnapshots() -> [SnapshotEntry] {
          guard let folder = store?.world.folder else { return [] }
          return SnapshotService.list(in: folder)
      }

      public func restore(snapshot: URL) throws {
          guard let folder = store?.world.folder else { throw SessionError.noWorldOpen }
          try SnapshotService.restore(snapshot: snapshot, world: folder)
          // FSEvents watcher will reload entities.
      }
  ```

  Read the existing `WorldSession.swift` and apply these inserts surgically. Don't rewrite the file from scratch — preserve all prior properties (`store`, `backlinkIndex`, `searchIndex`, `watcher`) and methods (`createEntity`, `createCharacter`, `backlinks`, `fields`, `search`, helpers).

- [ ] **Step 5: Run** — `xcodegen generate && xcodebuild test`. Expect 61 tests pass (59 + 2 new).

- [ ] **Step 6: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(app): SnapshotScheduler + WorldSession snapshot/restore APIs"
  ```

---

## Task 6: SnapshotsView sheet

**Files:**
- Create: `FantasyTavernApp/Sources/Snapshots/SnapshotsView.swift`

- [ ] **Step 1: Implement**

  ```swift
  import SwiftUI
  import SnapshotService

  struct SnapshotsView: View {
      @Environment(WorldSession.self) private var session
      @Environment(\.dismiss) private var dismiss

      @State private var entries: [SnapshotEntry] = []
      @State private var selected: URL?
      @State private var confirmRestore: SnapshotEntry?

      var body: some View {
          VStack(alignment: .leading, spacing: 12) {
              Text("Snapshots").font(.headline)
              List(entries, id: \.url, selection: $selected) { entry in
                  HStack {
                      VStack(alignment: .leading) {
                          Text(entry.url.lastPathComponent)
                          Text(entry.date.formatted(date: .abbreviated, time: .standard))
                              .font(.caption).foregroundStyle(.secondary)
                      }
                      Spacer()
                      Text(byteString(entry.size)).font(.caption).foregroundStyle(.secondary)
                  }
                  .tag(entry.url)
              }
              .frame(minHeight: 240)

              HStack {
                  Button("Snapshot Now") {
                      session.snapshotNow()
                      reload()
                  }
                  Spacer()
                  Button("Restore Selected") {
                      if let url = selected, let entry = entries.first(where: { $0.url == url }) {
                          confirmRestore = entry
                      }
                  }
                  .disabled(selected == nil)
                  Button("Close") { dismiss() }
                      .keyboardShortcut(.cancelAction)
              }
          }
          .padding(16)
          .frame(width: 520, height: 360)
          .onAppear { reload() }
          .alert("Restore this snapshot?",
                 isPresented: Binding(get: { confirmRestore != nil },
                                       set: { if !$0 { confirmRestore = nil } })) {
              Button("Restore", role: .destructive) {
                  if let entry = confirmRestore {
                      try? session.restore(snapshot: entry.url)
                      reload()
                  }
                  confirmRestore = nil
              }
              Button("Cancel", role: .cancel) { confirmRestore = nil }
          } message: {
              Text("Current state will be archived first as a pre-restore snapshot.")
          }
      }

      private func reload() {
          entries = session.listSnapshots()
      }

      private func byteString(_ size: Int64) -> String {
          ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
      }
  }
  ```

- [ ] **Step 2: Build** — `xcodegen generate && xcodebuild build`. Expected: succeeds.

- [ ] **Step 3: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(app): SnapshotsView sheet (list + restore)"
  ```

---

## Task 7: ExportService + tests

**Files:**
- Create: `FantasyTavernApp/Sources/Export/ExportService.swift`
- Create: `FantasyTavernApp/Tests/ExportServiceTests.swift`

- [ ] **Step 1: Failing tests**

  ```swift
  import XCTest
  import EntityModel
  import WorldStore
  @testable import FantasyTavernApp

  final class ExportServiceTests: XCTestCase {
      var tmp: URL!

      override func setUpWithError() throws {
          tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
      }
      override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

      func test_writeEntityMarkdown() throws {
          let entity = Entity(id: EntityID("lyra"), type: .character, name: "Lyra", body: "Hello")
          let target = tmp.appendingPathComponent("lyra.md")
          try ExportService.writeEntity(entity, to: target)
          let text = try String(contentsOf: target, encoding: .utf8)
          XCTAssertTrue(text.contains("name: Lyra"))
          XCTAssertTrue(text.contains("Hello"))
      }

      func test_zipFolder_roundTrip() throws {
          let src = tmp.appendingPathComponent("characters")
          try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
          try "x".write(to: src.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
          let zip = tmp.appendingPathComponent("characters.zip")
          try ExportService.zipFolder(src, to: zip, exclude: [])
          XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
      }
  }
  ```

- [ ] **Step 2: Implement**

  `FantasyTavernApp/Sources/Export/ExportService.swift`:

  ```swift
  import Foundation
  import EntityModel
  import WorldStore
  import SnapshotService

  enum ExportService {
      static func writeEntity(_ entity: Entity, to target: URL) throws {
          let serialized = try FrontMatter.serialize(entity)
          try serialized.data(using: .utf8)!.write(to: target, options: .atomic)
      }

      static func zipFolder(_ folder: URL, to target: URL, exclude: [String] = []) throws {
          try Zip.create(folder: folder, to: target, exclude: exclude)
      }
  }
  ```

- [ ] **Step 3: Run** — expect 2 new tests pass. App total: 63.

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(app): ExportService for entity + folder zip"
  ```

---

## Task 8: AppCommands — Snapshot Now / Show Snapshots / Export submenu

**Files:**
- Modify: `FantasyTavernApp/Sources/Commands/AppCommands.swift`
- Modify: `FantasyTavernApp/Sources/FantasyTavernAppApp.swift` (sheet plumbing for SnapshotsView)

- [ ] **Step 1: AppCommands**

  Read existing `AppCommands.swift` (linter-modified per session). Add:
  - `@State private var showSnapshots = false` is **not** valid in `Commands` — instead expose `var onShowSnapshots: () -> Void` via the parent scene OR use an `@AppStorage`/binding pattern. Easier: route through a published flag on a shared `PaletteController`-style object, or via an environment object created in `FantasyTavernAppApp`.

  Simpler path used here: add a small `@Observable SnapshotsPresenter` in `FantasyTavernAppApp` and pass into both `AppCommands` and `ContentView`. The presenter holds `isShowing: Bool`. Menu sets it true; ContentView mounts the sheet bound to it.

  Create `FantasyTavernApp/Sources/Snapshots/SnapshotsPresenter.swift`:

  ```swift
  import Foundation
  import Observation

  @Observable
  final class SnapshotsPresenter {
      var isShowing: Bool = false
  }
  ```

  Modify `AppCommands.swift`:

  ```swift
  import SwiftUI
  import AppKit
  import EntityModel
  import UniformTypeIdentifiers

  struct AppCommands: Commands {
      @Binding var session: WorldSession
      @Binding var tabs: TabsModel
      @Bindable var recents = RecentWorlds.shared
      @Bindable var presenter: SnapshotsPresenter

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
              Divider()
              Button("Snapshot Now") { session.snapshotNow() }
                  .disabled(session.store == nil)
              Button("Show Snapshots…") { presenter.isShowing = true }
                  .keyboardShortcut("s", modifiers: [.command, .shift])
                  .disabled(session.store == nil)
              Divider()
              Menu("Export") {
                  Button("Current Entity…") { exportCurrentEntity() }
                      .disabled(currentEntity() == nil)
                  Button("Current Entity Type Folder…") { exportCurrentType() }
                      .disabled(currentEntity() == nil)
                  Button("Whole World…") { exportWholeWorld() }
                      .disabled(session.store == nil)
              }
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
              tabs.open(.entity(entity.id))
          }
      }

      // MARK: - export

      private func currentEntity() -> Entity? {
          guard case .entity(let id) = tabs.selected else { return nil }
          return session.store?.entities.first(where: { $0.id == id })
      }

      private func exportCurrentEntity() {
          guard let e = currentEntity() else { return }
          let panel = NSSavePanel()
          panel.allowedContentTypes = [.text]
          panel.nameFieldStringValue = "\(e.id.rawValue).md"
          guard panel.runModal() == .OK, let url = panel.url else { return }
          try? ExportService.writeEntity(e, to: url)
      }

      private func exportCurrentType() {
          guard let e = currentEntity(), let folder = session.store?.world.folder else { return }
          let panel = NSSavePanel()
          panel.allowedContentTypes = [.zip]
          panel.nameFieldStringValue = "\(e.type.folderName).zip"
          guard panel.runModal() == .OK, let url = panel.url else { return }
          let src = folder.appendingPathComponent(e.type.folderName)
          try? ExportService.zipFolder(src, to: url)
      }

      private func exportWholeWorld() {
          guard let folder = session.store?.world.folder else { return }
          let panel = NSSavePanel()
          panel.allowedContentTypes = [.zip]
          panel.nameFieldStringValue = "\(folder.lastPathComponent).zip"
          guard panel.runModal() == .OK, let url = panel.url else { return }
          try? ExportService.zipFolder(folder, to: url, exclude: [".fantasytavern/*"])
      }
  }
  ```

- [ ] **Step 2: FantasyTavernAppApp.swift — inject SnapshotsPresenter + sheet**

  ```swift
  import SwiftUI

  @main
  struct FantasyTavernAppApp: App {
      @State private var session = WorldSession()
      @State private var tabs = TabsModel()
      @State private var palette: PaletteController
      @State private var snapshots = SnapshotsPresenter()

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
                  .environment(snapshots)
                  .sheet(isPresented: Binding(
                      get: { snapshots.isShowing },
                      set: { snapshots.isShowing = $0 }
                  )) {
                      SnapshotsView()
                          .environment(session)
                  }
          }
          .commands {
              AppCommands(session: $session, tabs: $tabs, presenter: snapshots)
              CommandGroup(after: .toolbar) {
                  Button("Show Command Palette") { palette.show() }
                      .keyboardShortcut("k", modifiers: [.command])
              }
          }
      }
  }
  ```

- [ ] **Step 3: Build + test**

  ```bash
  xcodegen generate
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -10
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' test 2>&1 | tail -5
  ```

  Expected: build succeeds, 63 tests pass.

- [ ] **Step 4: Commit**

  ```bash
  git add FantasyTavernApp
  git -c user.email=aryb@gmx.de -c user.name=ary commit -m "feat(app): menu wires Snapshot Now/Show Snapshots/Export"
  ```

---

## Task 9: Manual acceptance

**Files:** none.

- [ ] **Step 1: Build + launch**

  ```bash
  xcodebuild -project FantasyTavern.xcodeproj -scheme FantasyTavernApp -destination 'platform=macOS' build 2>&1 | tail -3
  pkill -f FantasyTavernApp 2>/dev/null || true
  sleep 1
  open ~/Library/Developer/Xcode/DerivedData/FantasyTavern-cjpexdvcsmhrwcafqhtvzpbgihqg/Build/Products/Debug/FantasyTavernApp.app
  ```

- [ ] **Step 2: Snapshots**

  1. Open Aetheria. Edit Lyra — wait for save.
  2. File → Snapshot Now. Check `~/Documents/FantasyTavern/Aetheria/.fantasytavern/snapshots/` — a `*.zip` appears.
  3. File → Show Snapshots… → sheet lists it.
  4. Edit Lyra again (different text), wait save. File → Snapshot Now → second snapshot in sheet.
  5. Click oldest snapshot → Restore → confirm. Lyra body reverts. The `pre-restore-*.zip` appears in the list.

- [ ] **Step 3: Export**

  1. With Lyra open: File → Export → Current Entity… → save to Desktop. Confirm `.md` opens in any editor.
  2. File → Export → Current Entity Type Folder… → confirm `.zip`. Unzip — contains all character .md files.
  3. File → Export → Whole World… → confirm zip. Unzip — full world tree minus `.fantasytavern/`.

- [ ] **Step 4: Tag**

  ```bash
  git tag plan-5-snapshots-export-complete
  ```

---

## Deferred from Plan 5 (call out at review)

- **Snapshot preview mode** — currently restore is the only verb. A read-only preview window over a snapshot's contents is a follow-up.
- **Conflict UI on restore w/ unsaved edits.** Plan 5 confirms via alert but otherwise overwrites the open tab's draft once FSEvents fires.
- **PDF export** — spec deferred to v2.
- **HTML static site export.**
- **Cloud-backup integration** for snapshots.

## Self-Review notes

**Spec coverage:**
- Auto-snapshot every 10 min if dirty (Task 5). ✓
- Retention 24h/7d/30d (Task 2). ✓
- Restore w/ pre-restore archive (Task 3). ✓
- Restore UI (Task 6). ✓
- Snapshot Now manual menu (Task 8). ✓
- Markdown export single/type/world (Tasks 7 + 8). ✓
- PDF export — deferred per spec.

**Placeholder scan:** no TBDs; one inline note in Task 1 Step 4 about a redundant `?? Data()` — already shows the fixed form.

**Type consistency:**
- `Zip.create(folder:to:exclude:)` and `Zip.extract(archive:to:)` consistent across Tasks 1, 3, 7.
- `SnapshotService.snapshot(world:now:prefix:)` / `list(in:)` / `restore(snapshot:world:)` / `prune(world:now:)` consistent across Tasks 3, 5.
- `SnapshotEntry { url, date, size }` defined in Task 3, used in Tasks 5, 6.
- `SnapshotScheduler.markDirty()` / `start()` / `stop()` / `fireForTesting()` consistent Tasks 5.
- `WorldSession.snapshotNow()` / `listSnapshots()` / `restore(snapshot:)` defined Task 5, used Tasks 6 + 8.
- `ExportService.writeEntity(_:to:)` / `zipFolder(_:to:exclude:)` consistent Tasks 7 + 8.
- `SnapshotsPresenter.isShowing` consistent across new files in Tasks 8.
