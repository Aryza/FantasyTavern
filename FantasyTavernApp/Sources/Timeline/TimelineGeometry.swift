import Foundation

enum TimelineGranularity { case year, decade, century }

enum TimelineGeometry {
    static func year(fromDateString raw: String) -> Int? {
        var digits = ""
        var sawSign = false
        var inRun = false
        for ch in raw {
            if ch == "-" && !inRun && digits.isEmpty {
                digits.append(ch); sawSign = true
            } else if ch.isNumber {
                digits.append(ch); inRun = true
            } else if inRun {
                break
            }
        }
        guard !digits.isEmpty, digits != "-" else { return nil }
        _ = sawSign
        return Int(digits)
    }

    static func tickStep(_ g: TimelineGranularity) -> Int {
        switch g { case .year: return 1; case .decade: return 10; case .century: return 100 }
    }

    static func x(forYear year: Int, range: ClosedRange<Int>, width: Double) -> Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        let frac = Double(year - range.lowerBound) / span
        return frac * width
    }

    static func year(atX x: Double, range: ClosedRange<Int>, width: Double) -> Int {
        guard width > 0 else { return range.lowerBound }
        let frac = max(0, min(1, x / width))
        let span = Double(range.upperBound - range.lowerBound)
        return range.lowerBound + Int((frac * span).rounded())
    }

    /// Pick the granularity whose tick step keeps a span readable
    /// (target ~10-30 visible ticks across the span).
    static func fittedGranularity(forSpan years: Int) -> TimelineGranularity {
        let span = max(0, years)
        if span == 0 { return .decade }
        if span <= 20 { return .year }
        if span <= 400 { return .decade }
        return .century
    }
}
