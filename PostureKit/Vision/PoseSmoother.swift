import Foundation

// PoseSmoother reduces the frame-to-frame jitter in raw Vision keypoints.
// It maintains a rolling window of recent poses and returns the per-joint average.
//
// Why smoothing is needed:
// Vision detects joints independently each frame. Even when you're standing still,
// keypoint positions shift by small amounts due to compression artifacts, lighting
// variation, and model uncertainty. Without smoothing this appears as visible tremor
// in the skeleton overlay.
//
// Trade-off:
// A larger window = smoother skeleton but more lag behind real movement.
// A smaller window = more responsive but jitterier.
// windowSize 5 at 30fps = ~167ms of smoothing. Tune if needed.
//
// Threading: smooth() is called on processingQueue. history is only ever
// accessed from that queue — no concurrent access, no lock needed.

class PoseSmoother {

    private var history: [BodyPose] = []
    private let windowSize = 5

    // Adds pose to the rolling window and returns the averaged result.
    // Automatically trims the window to windowSize.
    func smooth(_ pose: BodyPose) -> BodyPose {
        history.append(pose)
        if history.count > windowSize {
            history.removeFirst()
        }
        return averaged(history)
    }

    // Clears history. Called when no person is in frame so stale poses
    // don't contaminate the average when a person re-enters the frame.
    func reset() {
        history.removeAll()
    }

    // Averages each joint across all frames in the history window.
    // Uses compactMap to collect only non-nil joints — a joint absent
    // in some frames simply contributes fewer samples to the average.
    // If a joint has no samples at all, it stays nil in the result.
    private func averaged(_ poses: [BodyPose]) -> BodyPose {
        var result = BodyPose()

        result.leftEye       = averageJoint(poses.compactMap { $0.leftEye })
        result.rightEye      = averageJoint(poses.compactMap { $0.rightEye })
        result.nose          = averageJoint(poses.compactMap { $0.nose })
        result.nose          = averageJoint(poses.compactMap { $0.nose })
        result.leftEar       = averageJoint(poses.compactMap { $0.leftEar })
        result.rightEar      = averageJoint(poses.compactMap { $0.rightEar })
        result.neck          = averageJoint(poses.compactMap { $0.neck })
        result.leftShoulder  = averageJoint(poses.compactMap { $0.leftShoulder })
        result.rightShoulder = averageJoint(poses.compactMap { $0.rightShoulder })
        result.leftElbow     = averageJoint(poses.compactMap { $0.leftElbow })
        result.rightElbow    = averageJoint(poses.compactMap { $0.rightElbow })
        result.leftWrist     = averageJoint(poses.compactMap { $0.leftWrist })
        result.rightWrist    = averageJoint(poses.compactMap { $0.rightWrist })
        result.leftHip       = averageJoint(poses.compactMap { $0.leftHip })
        result.rightHip      = averageJoint(poses.compactMap { $0.rightHip })
        result.leftKnee      = averageJoint(poses.compactMap { $0.leftKnee })
        result.rightKnee     = averageJoint(poses.compactMap { $0.rightKnee })
        result.leftAnkle     = averageJoint(poses.compactMap { $0.leftAnkle })
        result.rightAnkle    = averageJoint(poses.compactMap { $0.rightAnkle })

        return result
    }

    // Averages position and confidence across a set of joints.
    // Returns nil if the input is empty (joint was absent in all history frames).
    private func averageJoint(_ joints: [BodyPose.Joint]) -> BodyPose.Joint? {
        guard !joints.isEmpty else { return nil }

        let count = CGFloat(joints.count)
        let avgX          = joints.reduce(0) { $0 + $1.position.x } / count
        let avgY          = joints.reduce(0) { $0 + $1.position.y } / count
        let avgConfidence = joints.reduce(0) { $0 + $1.confidence } / Float(joints.count)

        return BodyPose.Joint(
            position: CGPoint(x: avgX, y: avgY),
            confidence: avgConfidence
        )
    }
}
