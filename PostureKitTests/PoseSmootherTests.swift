import XCTest
@testable import PostureKit

// Tests for PoseSmoother.
// Validates averaging behaviour, window size, and graceful handling of missing joints.
// No device or simulator required — PoseSmoother is Foundation-only.

final class PoseSmootherTests: XCTestCase {

    var smoother: PoseSmoother!

    override func setUp() {
        super.setUp()
        smoother = PoseSmoother()
    }

    override func tearDown() {
        smoother = nil
        super.tearDown()
    }

    // MARK: - Helpers

    func makeJoint(x: CGFloat, y: CGFloat, confidence: Float = 0.9) -> BodyPose.Joint {
        BodyPose.Joint(position: CGPoint(x: x, y: y), confidence: confidence)
    }

    // Builds a pose with a single joint set — useful for targeted averaging tests.
    func makePose(noseX: CGFloat, noseY: CGFloat, confidence: Float = 0.9) -> BodyPose {
        var pose = BodyPose()
        pose.nose = makeJoint(x: noseX, y: noseY, confidence: confidence)
        return pose
    }

    func makeFullPose(value: CGFloat) -> BodyPose {
        var pose = BodyPose()
        let joint = makeJoint(x: value, y: value)
        pose.nose          = joint
        pose.leftShoulder  = joint
        pose.rightShoulder = joint
        pose.leftHip       = joint
        pose.rightHip      = joint
        return pose
    }

    // MARK: - Single frame

    func testSinglePoseReturnedAsIs() {
        let pose = makePose(noseX: 0.3, noseY: 0.7)
        let result = smoother.smooth(pose)

        XCTAssertEqual(result.nose?.position.x ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(result.nose?.position.y ?? 0, 0.7, accuracy: 0.001)
    }

    func testSinglePoseWithNilJointRemainsNil() {
        let pose = makePose(noseX: 0.5, noseY: 0.5)
        // leftShoulder not set in this pose
        let result = smoother.smooth(pose)
        XCTAssertNil(result.leftShoulder)
    }

    // MARK: - Averaging

    func testTwoPosesAreAveraged() {
        _ = smoother.smooth(makePose(noseX: 0.2, noseY: 0.2))
        let result = smoother.smooth(makePose(noseX: 0.4, noseY: 0.6))

        XCTAssertEqual(result.nose?.position.x ?? 0, 0.3, accuracy: 0.001) // (0.2 + 0.4) / 2
        XCTAssertEqual(result.nose?.position.y ?? 0, 0.4, accuracy: 0.001) // (0.2 + 0.6) / 2
    }

    func testConfidenceIsAlsoAveraged() {
        _ = smoother.smooth(makePose(noseX: 0.5, noseY: 0.5, confidence: 0.6))
        let result = smoother.smooth(makePose(noseX: 0.5, noseY: 0.5, confidence: 0.8))

        XCTAssertEqual(result.nose?.confidence ?? 0, 0.7, accuracy: 0.001) // (0.6 + 0.8) / 2
    }

    func testThreePosesAveragedCorrectly() {
        _ = smoother.smooth(makePose(noseX: 0.0, noseY: 0.0))
        _ = smoother.smooth(makePose(noseX: 0.3, noseY: 0.3))
        let result = smoother.smooth(makePose(noseX: 0.6, noseY: 0.6))

        XCTAssertEqual(result.nose?.position.x ?? 0, 0.3, accuracy: 0.001) // (0 + 0.3 + 0.6) / 3
        XCTAssertEqual(result.nose?.position.y ?? 0, 0.3, accuracy: 0.001)
    }

    // MARK: - Window size (5 frames)

    // After 5 frames, the oldest should be dropped.
    // 6 poses with x: 0.0, 0.1, 0.2, 0.3, 0.4, 0.5
    // After adding the 6th, window = [0.1, 0.2, 0.3, 0.4, 0.5] → average = 0.3
    func testWindowDropsOldestFrameAfterFive() {
        for i in 0..<5 {
            _ = smoother.smooth(makePose(noseX: CGFloat(i) * 0.1, noseY: 0))
        }
        let result = smoother.smooth(makePose(noseX: 0.5, noseY: 0))

        // Window is [0.1, 0.2, 0.3, 0.4, 0.5] — 0.0 was dropped
        let expected: CGFloat = (0.1 + 0.2 + 0.3 + 0.4 + 0.5) / 5
        XCTAssertEqual(result.nose?.position.x ?? 0, expected, accuracy: 0.001)
    }

    // MARK: - Missing joints across frames

    // Joint present in only some frames should be averaged over those frames only.
    func testJointPresentInSomeFramesIsAveraged() {
        var poseWithJoint = BodyPose()
        poseWithJoint.leftShoulder = makeJoint(x: 0.4, y: 0.4)

        var poseWithoutJoint = BodyPose()
        // leftShoulder is nil in this pose

        _ = smoother.smooth(poseWithJoint)
        let result = smoother.smooth(poseWithoutJoint)

        // Only 1 sample available — should return that sample's position
        XCTAssertNotNil(result.leftShoulder)
        XCTAssertEqual(result.leftShoulder?.position.x ?? 0, 0.4, accuracy: 0.001)
    }

    // Joint absent in ALL frames should remain nil.
    func testJointAbsentInAllFramesRemainsNil() {
        _ = smoother.smooth(makePose(noseX: 0.5, noseY: 0.5)) // no leftShoulder
        _ = smoother.smooth(makePose(noseX: 0.5, noseY: 0.5)) // no leftShoulder
        let result = smoother.smooth(makePose(noseX: 0.5, noseY: 0.5))

        XCTAssertNil(result.leftShoulder)
    }

    // MARK: - Reset

    func testResetClearsHistory() {
        // Feed in 3 frames with nose at x=0.1
        for _ in 0..<3 {
            _ = smoother.smooth(makePose(noseX: 0.1, noseY: 0.1))
        }

        smoother.reset()

        // After reset, a single new frame at x=0.9 should return exactly 0.9
        // (no averaging with the cleared history)
        let result = smoother.smooth(makePose(noseX: 0.9, noseY: 0.9))
        XCTAssertEqual(result.nose?.position.x ?? 0, 0.9, accuracy: 0.001)
    }

    func testResetAllowsFreshAverageToBegin() {
        _ = smoother.smooth(makePose(noseX: 0.1, noseY: 0.1))
        _ = smoother.smooth(makePose(noseX: 0.1, noseY: 0.1))

        smoother.reset()

        _ = smoother.smooth(makePose(noseX: 0.8, noseY: 0.8))
        let result = smoother.smooth(makePose(noseX: 1.0, noseY: 1.0))

        // Only 2 frames since reset: (0.8 + 1.0) / 2 = 0.9
        XCTAssertEqual(result.nose?.position.x ?? 0, 0.9, accuracy: 0.001)
    }

    // MARK: - Empty pose

    func testEmptyPoseThroughSmootherRemainsEmpty() {
        let result = smoother.smooth(BodyPose.empty)
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.nose)
        XCTAssertNil(result.leftShoulder)
    }
}
