import Foundation

// BodyPose is the canonical model for a single detected body pose.
// It travels through the entire app — Vision layer creates it, Analysis layer reads it, UI layer displays it.
//
// Design rule: this file must stay framework-free (Foundation only).
// That keeps it unit-testable on any Mac without a simulator or device.
// The Vision conversion lives in BodyPose+Vision.swift.
//
// Coordinates: all joint positions are stored in raw Vision normalised space (0.0–1.0).
// Origin is bottom-left, Y increases upward.
// The Y-flip for SwiftUI rendering happens in CoordinateConverter, not here.

struct BodyPose {

    // A single detected keypoint on the body.
    // position  — normalised Vision coordinate (x: 0–1, y: 0–1, origin bottom-left)
    // confidence — Vision's certainty that this joint exists in frame (0.0–1.0)
    struct Joint {
        let position: CGPoint
        let confidence: Float

        // Used by the UI layer to decide whether to draw this joint.
        // 0.5 is the display threshold — below this the joint is too uncertain to show.
        var isReliable: Bool { confidence > 0.5 }
    }

    // All 16 tracked keypoints. Optional because any joint can be out of frame or below confidence.
    // nil means "not detected with sufficient confidence", not an error.
    var leftEye: Joint?
    var rightEye: Joint?
    var nose: Joint?
    var leftEar: Joint?
    var rightEar: Joint?
    var neck: Joint?
    var leftShoulder: Joint?
    var rightShoulder: Joint?
    var leftElbow: Joint?
    var rightElbow: Joint?
    var leftWrist: Joint?
    var rightWrist: Joint?
    var leftHip: Joint?
    var rightHip: Joint?
    var leftKnee: Joint?
    var rightKnee: Joint?
    var leftAnkle: Joint?
    var rightAnkle: Joint?

    // True only when the 4 core trunk joints are detected.
    // Both shoulders and both hips are the minimum geometry needed for posture analysis.
    // Extremities (wrists, ankles) regularly fall out of frame and are not required.
    var isValid: Bool {
        leftShoulder != nil && rightShoulder != nil &&
        leftHip != nil && rightHip != nil
    }

    // Convenience for initialising an empty pose (all joints nil, isValid == false).
    // Used as the default value in CameraManager before the first frame is processed.
    static var empty: BodyPose { BodyPose() }
}
