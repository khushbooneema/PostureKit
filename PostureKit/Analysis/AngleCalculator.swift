import Foundation

// AngleCalculator — pure math utility for posture geometry.
//
// Design rules:
// - All inputs are CGPoint in Vision normalised space (0–1). All outputs are Double in degrees.
// - No state, no side effects, no framework imports beyond Foundation.
// - Every function is static — call as AngleCalculator.angle(...), never instantiate.
//
// Why enum with no cases:
// Prevents AngleCalculator() from being written anywhere. Swift idiom for a
// stateless namespace — the same pattern as Swift's standard library Math utilities.

enum AngleCalculator {

    // MARK: - angle(a:b:c:)

    // Calculates the angle in degrees at joint B, formed by segments A→B and B→C.
    //
    // How it works — dot product formula:
    //   cos(θ) = (BA · BC) / (|BA| × |BC|)
    //   θ = acos(cos(θ)) × (180 / π)
    //
    // Where:
    //   BA = vector from B to A
    //   BC = vector from B to C
    //   · = dot product
    //   |v| = magnitude (length) of vector v
    //
    // Example: elbow angle — pass shoulder(a), elbow(b), wrist(c)
    // Returns 0.0 if either vector has zero length (identical points) — no crash.
    static func angle(a: CGPoint, b: CGPoint, c: CGPoint) -> Double {
        // Vectors from the vertex joint (B) to each neighbouring joint
        let ba = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let bc = CGVector(dx: c.x - b.x, dy: c.y - b.y)

        // Dot product: measures how much the two vectors point in the same direction
        let dot = ba.dx * bc.dx + ba.dy * bc.dy

        // Magnitudes (lengths) of each vector
        let magBA = sqrt(ba.dx * ba.dx + ba.dy * ba.dy)
        let magBC = sqrt(bc.dx * bc.dx + bc.dy * bc.dy)

        // Guard: if either point is identical to B, the vector has zero length —
        // the angle is undefined. Return 0 rather than crash or NaN.
        guard magBA > 0, magBC > 0 else { return 0 }

        // Clamp to [-1, 1] before acos — REQUIRED, not optional.
        // Floating-point arithmetic can produce values like 1.0000000002 due to
        // rounding errors. acos() is only defined on [-1, 1] — outside that range
        // it returns NaN, which silently corrupts every downstream calculation.
        let cosAngle = (dot / (magBA * magBC)).clamped(to: -1.0...1.0)

        return acos(cosAngle) * (180.0 / .pi)
    }

    // MARK: - craniovertebralAngle

    // Returns the Craniovertebral Angle (CVA) in degrees.
    //
    // Clinical definition:
    //   The angle formed between a horizontal line through C7 (approximated by the
    //   shoulder keypoint) and the line from C7 up to the tragus of the ear.
    //   A neutral spine has the ear directly above the shoulder — CVA ≈ 90°.
    //   As the head protrudes forward, the ear shifts in front of the shoulder,
    //   rotating the shoulder→ear vector toward horizontal and reducing the CVA.
    //
    // Why this is better than horizontal offset:
    //   Horizontal offset is a raw pixel distance that changes with how far the
    //   subject stands from the camera. CVA is a ratio (rise/run = angle), so it
    //   stays consistent regardless of camera distance or subject height.
    //
    // Input coordinate space — Vision normalised (0–1), origin bottom-left, Y up:
    //   ear.y > shoulder.y in all normal postures (ear is higher on the body).
    //   We take abs(dx) so the formula works for both left- and right-facing profiles.
    //
    // Reference thresholds (clinical literature):
    //   ≥ 50°  → normal
    //   45–49° → mild FHP
    //   35–44° → moderate FHP
    //   < 35°  → severe FHP
    static func craniovertebralAngle(ear: CGPoint, shoulder: CGPoint) -> Double {
        let dx = abs(Double(ear.x - shoulder.x))   // horizontal separation
        let dy = Double(ear.y - shoulder.y)         // vertical separation (positive = ear above shoulder)

        // If the two points are coincident Vision detected a degenerate pose — return neutral.
        guard dx > 0 || dy > 0 else { return 90 }

        return atan2(dy, dx) * (180.0 / .pi)
    }
}

// MARK: - Double clamping helper

// Used by angle(a:b:c:) to keep the cosine in acos()'s valid domain.
// Defined as an extension rather than a local function so it can be used
// by any future AngleCalculator function that needs range clamping.
extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
