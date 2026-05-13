import Foundation

public enum SnapshotServiceError: Error {
    case worldMissing(URL)
}

public struct SnapshotEntry: Equatable {
    public let url: URL
    public let date: Date
    public let size: Int64

    public init(url: URL, date: Date, size: Int64) {
        self.url = url
        self.date = date
        self.size = size
    }
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
        // Normalize via FileManager listing so the returned URL matches `list(in:)` output
        // (NSTemporaryDirectory paths involve /var → /private/var symlink resolution).
        if let match = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .first(where: { $0.lastPathComponent == name }) {
            return match
        }
        return archive
    }

    public static func list(in world: URL) -> [SnapshotEntry] {
        let dir = snapshotsDir(in: world)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]) else {
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
