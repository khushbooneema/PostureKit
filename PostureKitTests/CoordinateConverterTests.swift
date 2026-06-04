import XCTest
@testable import PostureKit

// Tests for CoordinateConverter.
// Validates the Vision-to-Canvas coordinate transform, especially the Y-flip.
// No device or simulator required — CoordinateConverter is Foundation-only.

final class CoordinateConverterTests: XCTestCase {

    // MARK: - Helpers

    let canvas400x800 = CGSize(width: 400, height: 800)
    let canvas1000x1000 = CGSize(width: 1000, height: 1000)

    func makeReliableJoint(x: CGFloat, y: CGFloat) -> BodyPose.Joint {
        BodyPose.Joint(position: CGPoint(x: x, y: y), confidence: 0.9)
    }

    func makeUnreliableJoint(x: CGFloat, y: CGFloat) -> BodyPose.Joint {
        BodyPose.Joint(position: CGPoint(x: x, y: y), confidence: 0.3)
    }

    // MARK: - Point conversion

    // The canonical acceptance-criteria test from the ticket.
    func testCentrePointConvertsCorrectly() {
        let result = CoordinateConverter.visionToCanvas(
            CGPoint(x: 0.5, y: 0.5),
            canvasSize: canvas400x800
        )
        XCTAssertEqual(result.x, 200, accuracy: 0.001)
        XCTAssertEqual(result.y, 400, accuracy: 0.001)
    }

    // Vision (0,0) is bottom-left → Canvas bottom-left = (0, height).
    func testVisionOriginMapsToCanvasBottomLeft() {
        let result = CoordinateConverter.visionToCanvas(
            CGPoint(x: 0, y: 0),
            canvasSize: canvas400x800
        )
        XCTAssertEqual(result.x, 0,   accuracy: 0.001)
        XCTAssertEqual(result.y, 800, accuracy: 0.001)
    }

    // Vision (1,1) is top-right → Canvas top-right = (width, 0).
    func testVisionTopRightMapsToCanvasTopRight() {
        let result = CoordinateConverter.visionToCanvas(
            CGPoint(x: 1, y: 1),
            canvasSize: canvas400x800
        )
        XCTAssertEqual(result.x, 400, accuracy: 0.001)
        XCTAssertEqual(result.y, 0,   accuracy: 0.001)
    }

    // Vision (0,1) is top-left → Canvas top-left = (0, 0).
    func testVisionTopLeftMapsToCanvasTopLeft() {
        let result = CoordinateConverter.visionToCanvas(
            CGPoint(x: 0, y: 1),
            canvasSize: canvas400x800
        )
        XCTAssertEqual(result.x, 0, accuracy: 0.001)
        XCTAssertEqual(result.y, 0, accuracy: 0.001)
    }

    // Explicitly validates the Y-flip — the most critical part of the formula.
    func testYAxisIsFlipped() {
        let highVisionY  = CoordinateConverter.visionToCanvas(CGPoint(x: 0.5, y: 0.9), canvasSize: canvas1000x1000)
        let lowVisionY   = CoordinateConverter.visionToCanvas(CGPoint(x: 0.5, y: 0.1), canvasSize: canvas1000x1000)

        // Vision y=0.9 (near top of body) → Canvas y should be small (near top of screen).
        XCTAssertLessThan(highVisionY.y, lowVisionY.y)
    }

    func testXAxisIsNotFlipped() {
        let leftPoint  = CoordinateConverter.visionToCanvas(CGPoint(x: 0.1, y: 0.5), canvasSize: canvas1000x1000)
        let rightPoint = CoordinateConverter.visionToCanvas(CGPoint(x: 0.9, y: 0.5), canvasSize: canvas1000x1000)

        // Vision x increases left-to-right, same as Canvas.
        XCTAssertLessThan(leftPoint.x, rightPoint.x)
    }

    func testScalesWithCanvasSize() {
        let small = CoordinateConverter.visionToCanvas(CGPoint(x: 0.5, y: 0.5), canvasSize: CGSize(width: 100, height: 200))
        let large = CoordinateConverter.visionToCanvas(CGPoint(x: 0.5, y: 0.5), canvasSize: CGSize(width: 1000, height: 2000))

        XCTAssertEqual(small.x, 50,   accuracy: 0.001)
        XCTAssertEqual(large.x, 500,  accuracy: 0.001)
        XCTAssertEqual(small.y, 100,  accuracy: 0.001)
        XCTAssertEqual(large.y, 1000, accuracy: 0.001)
    }

    // MARK: - Joint overload — nil handling

    func testNilJointReturnsNil() {
        let result = CoordinateConverter.visionToCanvas(nil, canvasSize: canvas400x800)
        XCTAssertNil(result)
    }

    func testUnreliableJointReturnsNil() {
        let joint = makeUnreliableJoint(x: 0.5, y: 0.5)
        let result = CoordinateConverter.visionToCanvas(joint, canvasSize: canvas400x800)
        XCTAssertNil(result)
    }

    // Confidence exactly at threshold (0.5) is not reliable — should return nil.
    func testJointAtExactThresholdReturnsNil() {
        let joint = BodyPose.Joint(position: CGPoint(x: 0.5, y: 0.5), confidence: 0.5)
        let result = CoordinateConverter.visionToCanvas(joint, canvasSize: canvas400x800)
        XCTAssertNil(result)
    }

    func testReliableJointReturnsConvertedPoint() {
        let joint = makeReliableJoint(x: 0.5, y: 0.5)
        let result = CoordinateConverter.visionToCanvas(joint, canvasSize: canvas400x800)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.x, 200, accuracy: 0.001)
        XCTAssertEqual(result!.y, 400, accuracy: 0.001)
    }

    func testReliableJointAppliesYFlip() {
        // Vision y=0.0 (bottom of vision space) → Canvas y=height (bottom of canvas).
        let joint = makeReliableJoint(x: 0.0, y: 0.0)
        let result = CoordinateConverter.visionToCanvas(joint, canvasSize: canvas400x800)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.y, 800, accuracy: 0.001)
    }
}
