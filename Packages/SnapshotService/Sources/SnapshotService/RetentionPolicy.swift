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
