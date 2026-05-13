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
