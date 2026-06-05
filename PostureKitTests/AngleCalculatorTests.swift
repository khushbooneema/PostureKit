import XCTest
@testable import PostureKit

// Tests for AngleCalculator — angle(a:b:c:) and horizontalOffset.
//
// All floating-point assertions use accuracy: 0.001.
// Never use exact equality for angle calculations — floating-point
// arithmetic rarely produces exact values like 90.0000000000.
//
// All points are in Vision normalised space (0–1).
// No device or simulator required — AngleCalculator is Foundation-only.

final class AngleCalculatorTests: XCTestCase {

    // MARK: - angle(a:b:c:)

    // L-shaped geometry: A directly above B, C directly to the right of B.
    // The two segments are perpendicular — angle at B must be 90°.
    func testRightAngle() {
        let result = AngleCalculator.angle(
            a: CGPoint(x: 0, y: 1),   // above B
            b: CGPoint(x: 0, y: 0),   // vertex
            c: CGPoint(x: 1, y: 0)    // right of B
        )
        XCTAssertEqual(result, 90.0, accuracy: 0.001)
    }

    // Three points in the same direction (A→B→C all along the Y axis going up).
    // Vectors BA and BC point the same way — angle between them is 0°.
    func testSameDirectionReturnsZero() {
        let result = AngleCalculator.angle(
            a: CGPoint(x: 0, y: 1),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 0, y: 2)
        )
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
    }

    // Three collinear points going in opposite directions (A above B, C below B).
    // Vectors BA and BC point in exactly opposite directions — angle is 180°.
    func testStraightLineReturns180() {
        let result = AngleCalculator.angle(
            a: CGPoint(x: 0, y: 1),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 0, y: -1)
        )
        XCTAssertEqual(result, 180.0, accuracy: 0.001)
    }

    // 45° angle: BA points along positive X, BC points at 45° (equal X and Y components).
    // cos(45°) = 1/√2, which is what the dot product formula produces here.
    func test45DegreeAngle() {
        let result = AngleCalculator.angle(
            a: CGPoint(x: 1, y: 0),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 1, y: 1)
        )
        XCTAssertEqual(result, 45.0, accuracy: 0.001)
    }

    // 135° obtuse angle.
    // BA points right (+X), BC points upper-left (−X, +Y equal magnitudes).
    func test135DegreeAngle() {
        let result = AngleCalculator.angle(
            a: CGPoint(x: 1, y: 0),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: -1, y: 1)
        )
        XCTAssertEqual(result, 135.0, accuracy: 0.001)
    }

    // Edge case: A and B are the same point — vector BA has zero length.
    // Guard should catch this and return 0.0 instead of crashing or returning NaN.
    func testIdenticalAandBReturnsZeroNoCrash() {
        let result = AngleCalculator.angle(
            a: CGPoint(x: 0.5, y: 0.5),  // same as B
            b: CGPoint(x: 0.5, y: 0.5),
            c: CGPoint(x: 0.8, y: 0.8)
        )
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
        XCTAssertFalse(result.isNaN)
    }

    // Edge case: B and C are the same point — vector BC has zero length.
    func testIdenticalBandCReturnsZeroNoCrash() {
        let result = AngleCalculator.angle(
            a: CGPoint(x: 0.2, y: 0.2),
            b: CGPoint(x: 0.5, y: 0.5),
            c: CGPoint(x: 0.5, y: 0.5)   // same as B
        )
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
        XCTAssertFalse(result.isNaN)
    }

    // All three points identical — both vectors are zero length.
    // Should return 0.0 without crash or NaN.
    func testAllIdenticalPointsReturnsZero() {
        let result = AngleCalculator.angle(
            a: CGPoint(x: 0.5, y: 0.5),
            b: CGPoint(x: 0.5, y: 0.5),
            c: CGPoint(x: 0.5, y: 0.5)
        )
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
        XCTAssertFalse(result.isNaN)
    }

    // The clamp guards against floating-point values just outside [-1, 1].
    // This test uses a known near-parallel configuration that can produce
    // cosine values like 1.0000000001 without the clamp.
    // Result must be a number (not NaN) and near 0°.
    func testClampPreventNaN() {
        let result = AngleCalculator.angle(
            a: CGPoint(x: 0.0, y: 1.0),
            b: CGPoint(x: 0.0, y: 0.0),
            c: CGPoint(x: 0.0001, y: 1.0)   // nearly parallel — stress-tests the clamp
        )
        XCTAssertFalse(result.isNaN, "angle() must never return NaN — clamp is required")
    }

    // Result is always in degrees, never radians.
    // A right angle in radians would be ~1.5708 — verifying we get 90.0 confirms degrees.
    func testResultIsInDegrees() {
        let result = AngleCalculator.angle(
            a: CGPoint(x: 0, y: 1),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 1, y: 0)
        )
        XCTAssertGreaterThan(result, 2.0, "Result looks like radians, not degrees")
        XCTAssertEqual(result, 90.0, accuracy: 0.001)
    }

    // MARK: - horizontalOffset

    // Ticket acceptance criteria: (0.2, 0) and (0.5, 0) must return 0.3.
    func testHorizontalOffsetBasic() {
        let result = AngleCalculator.horizontalOffset(
            CGPoint(x: 0.2, y: 0),
            CGPoint(x: 0.5, y: 0)
        )
        XCTAssertEqual(result, 0.3, accuracy: 0.001)
    }

    // Order of arguments should not affect the result — abs() ensures symmetry.
    func testHorizontalOffsetIsSymmetric() {
        let forward = AngleCalculator.horizontalOffset(
            CGPoint(x: 0.5, y: 0),
            CGPoint(x: 0.2, y: 0)
        )
        let reverse = AngleCalculator.horizontalOffset(
            CGPoint(x: 0.2, y: 0),
            CGPoint(x: 0.5, y: 0)
        )
        XCTAssertEqual(forward, reverse, accuracy: 0.001)
    }

    // Y coordinate must not affect horizontal offset — only X matters.
    func testHorizontalOffsetIgnoresY() {
        let sameY = AngleCalculator.horizontalOffset(
            CGPoint(x: 0.2, y: 0.0),
            CGPoint(x: 0.5, y: 0.0)
        )
        let differentY = AngleCalculator.horizontalOffset(
            CGPoint(x: 0.2, y: 0.9),
            CGPoint(x: 0.5, y: 0.1)
        )
        XCTAssertEqual(sameY, differentY, accuracy: 0.001)
    }

    // Same X coordinate — perfectly aligned horizontally — must return 0.
    func testHorizontalOffsetZeroWhenAligned() {
        let result = AngleCalculator.horizontalOffset(
            CGPoint(x: 0.4, y: 0.1),
            CGPoint(x: 0.4, y: 0.9)
        )
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
    }

    // Result is always non-negative — abs() guarantees this.
    func testHorizontalOffsetAlwaysNonNegative() {
        let result = AngleCalculator.horizontalOffset(
            CGPoint(x: 0.8, y: 0.5),
            CGPoint(x: 0.2, y: 0.5)
        )
        XCTAssertGreaterThanOrEqual(result, 0.0)
    }

    // Maximum possible offset in normalised space is 1.0 (opposite edges of frame).
    func testHorizontalOffsetMaximum() {
        let result = AngleCalculator.horizontalOffset(
            CGPoint(x: 0.0, y: 0.5),
            CGPoint(x: 1.0, y: 0.5)
        )
        XCTAssertEqual(result, 1.0, accuracy: 0.001)
    }

    // MARK: - Double.clamped

    func testClampedKeepsValueInRange() {
        XCTAssertEqual((1.5).clamped(to: -1.0...1.0), 1.0, accuracy: 0.001)
        XCTAssertEqual((-1.5).clamped(to: -1.0...1.0), -1.0, accuracy: 0.001)
        XCTAssertEqual((0.5).clamped(to: -1.0...1.0), 0.5, accuracy: 0.001)
    }

    func testClampedAtBoundaryStaysAtBoundary() {
        XCTAssertEqual((1.0).clamped(to: -1.0...1.0), 1.0, accuracy: 0.001)
        XCTAssertEqual((-1.0).clamped(to: -1.0...1.0), -1.0, accuracy: 0.001)
    }
}
