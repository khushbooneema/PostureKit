import XCTest
@testable import PostureKit

// Tests for BodyPose and BodyPose.Joint.
// No device or simulator required — BodyPose is Foundation-only.

final class BodyPoseTests: XCTestCase {

    // MARK: - Helpers

    func makeJoint(x: CGFloat = 0.5, y: CGFloat = 0.5, confidence: Float = 0.9) -> BodyPose.Joint {
        BodyPose.Joint(position: CGPoint(x: x, y: y), confidence: confidence)
    }

    // Returns a BodyPose with all 4 core joints present and high confidence.
    func makeValidPose() -> BodyPose {
        var pose = BodyPose()
        pose.leftShoulder  = makeJoint(x: 0.3, y: 0.7)
        pose.rightShoulder = makeJoint(x: 0.7, y: 0.7)
        pose.leftHip       = makeJoint(x: 0.3, y: 0.4)
        pose.rightHip      = makeJoint(x: 0.7, y: 0.4)
        return pose
    }

    // MARK: - BodyPose.empty

    func testEmptyPoseHasAllNilJoints() {
        let pose = BodyPose.empty
        XCTAssertNil(pose.leftShoulder)
        XCTAssertNil(pose.rightShoulder)
        XCTAssertNil(pose.leftHip)
        XCTAssertNil(pose.rightHip)
        XCTAssertNil(pose.nose)
    }

    func testEmptyPoseIsNotValid() {
        XCTAssertFalse(BodyPose.empty.isValid)
    }

    func testDefaultInitIsNotValid() {
        XCTAssertFalse(BodyPose().isValid)
    }

    // MARK: - isValid

    func testPoseWithAllFourCoreJointsIsValid() {
        XCTAssertTrue(makeValidPose().isValid)
    }

    func testPoseWithMissingLeftShoulderIsNotValid() {
        var pose = makeValidPose()
        pose.leftShoulder = nil
        XCTAssertFalse(pose.isValid)
    }

    func testPoseWithMissingRightShoulderIsNotValid() {
        var pose = makeValidPose()
        pose.rightShoulder = nil
        XCTAssertFalse(pose.isValid)
    }

    func testPoseWithMissingLeftHipIsNotValid() {
        var pose = makeValidPose()
        pose.leftHip = nil
        XCTAssertFalse(pose.isValid)
    }

    func testPoseWithMissingRightHipIsNotValid() {
        var pose = makeValidPose()
        pose.rightHip = nil
        XCTAssertFalse(pose.isValid)
    }

    // Extremities (nose, wrists, ankles) are not required for isValid.
    func testPoseWithOnlyCoreJointsIsValidWithoutExtremities() {
        var pose = makeValidPose()
        pose.nose      = nil
        pose.leftWrist = nil
        pose.leftAnkle = nil
        XCTAssertTrue(pose.isValid)
    }

    // MARK: - Joint.isReliable

    func testJointAboveThresholdIsReliable() {
        let joint = makeJoint(confidence: 0.6)
        XCTAssertTrue(joint.isReliable)
    }

    func testJointBelowThresholdIsNotReliable() {
        let joint = makeJoint(confidence: 0.4)
        XCTAssertFalse(joint.isReliable)
    }

    // Threshold is > 0.5, not >= 0.5 — exactly 0.5 should NOT be reliable.
    func testJointAtExactThresholdIsNotReliable() {
        let joint = makeJoint(confidence: 0.5)
        XCTAssertFalse(joint.isReliable)
    }

    func testJointJustAboveThresholdIsReliable() {
        let joint = makeJoint(confidence: 0.51)
        XCTAssertTrue(joint.isReliable)
    }

    func testJointAtMaxConfidenceIsReliable() {
        let joint = makeJoint(confidence: 1.0)
        XCTAssertTrue(joint.isReliable)
    }

    func testJointAtZeroConfidenceIsNotReliable() {
        let joint = makeJoint(confidence: 0.0)
        XCTAssertFalse(joint.isReliable)
    }

    // MARK: - Joint position

    func testJointStoresPositionCorrectly() {
        let joint = makeJoint(x: 0.25, y: 0.75)
        XCTAssertEqual(joint.position.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(joint.position.y, 0.75, accuracy: 0.001)
    }

    func testJointStoresConfidenceCorrectly() {
        let joint = makeJoint(confidence: 0.87)
        XCTAssertEqual(joint.confidence, 0.87, accuracy: 0.001)
    }
}
