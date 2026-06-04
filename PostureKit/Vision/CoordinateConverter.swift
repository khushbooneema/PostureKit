import Foundation

// CoordinateConverter translates Vision normalised coordinates into SwiftUI Canvas points.
//
// Why this exists as a dedicated type:
// Vision, SwiftUI Canvas, and AVFoundation all use different coordinate origins
// and Y-axis directions. Centralising the conversion in one place means:
// - The formula is written and tested once
// - Every call site is a single function call — no inline arithmetic scattered across the UI layer
// - If the formula ever needs to change (e.g. landscape rotation), there is one place to fix it
//
// Coordinate space reference:
//   Vision normalised:  origin bottom-left, Y increases upward,  range 0.0–1.0
//   SwiftUI Canvas:     origin top-left,    Y increases downward, range 0–viewSize
//
// Conversion formula:
//   canvasX = vision.x × canvasWidth
//   canvasY = (1 − vision.y) × canvasHeight   ← the Y-flip
//
// Why an enum with no cases:
// We want a namespace for static functions with no ability to create an instance.
// A caseless enum enforces that — you cannot write CoordinateConverter() by mistake.

enum CoordinateConverter {

    // Converts a raw Vision normalised point to a SwiftUI Canvas point.
    static func visionToCanvas(_ point: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: point.x * canvasSize.width,
            y: (1 - point.y) * canvasSize.height   // flip Y axis
        )
    }

    // Convenience overload for a Joint.
    // Returns nil if the joint is nil or below the reliability threshold (confidence < 0.5).
    // This is the version the skeleton drawing code calls — unreliable joints are skipped entirely.
    static func visionToCanvas(_ joint: BodyPose.Joint?, canvasSize: CGSize) -> CGPoint? {
        guard let joint, joint.isReliable else { return nil }
        return visionToCanvas(joint.position, canvasSize: canvasSize)
    }
}
