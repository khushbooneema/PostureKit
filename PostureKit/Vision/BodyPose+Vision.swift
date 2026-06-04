import Vision

// This extension is the single conversion boundary between Apple's Vision framework
// and PostureKit's internal BodyPose model.
//
// Rule: VNHumanBodyPoseObservation must never appear outside this file.
// All downstream code (Analysis, UI, Storage) works with BodyPose only.
// This means swapping Vision for a custom CoreML model in Layer 4 touches this file only.

extension BodyPose {

    // Converts a raw Vision observation into a clean BodyPose.
    // Any joint below 0.3 confidence is treated as not detected (returns nil).
    // 0.3 is the creation gate — below this Vision has very low confidence the joint exists at all.
    // The display gate (isReliable) is higher at 0.5, set on Joint itself.
    init(from observation: VNHumanBodyPoseObservation) {

        // recognizedPoints(.all) returns a dictionary of all detected joints for this frame.
        // try? means a failure (e.g. no person in frame) produces nil, which the helper handles gracefully.
        let points = try? observation.recognizedPoints(.all)

        // Local helper — looks up a joint by name, applies the confidence gate, returns nil if below threshold.
        // Coordinates are stored raw (Vision normalised space). Y-flip happens in CoordinateConverter.
        func joint(_ name: VNHumanBodyPoseObservation.JointName) -> Joint? {
            guard let point = points?[name], point.confidence > 0.3 else { return nil }
            return Joint(
                position: CGPoint(x: point.location.x, y: point.location.y),
                confidence: point.confidence
            )
        }

        leftEye       = joint(.leftEye)
        rightEye      = joint(.rightEye)
        nose          = joint(.nose)
        leftEar       = joint(.leftEar)
        rightEar      = joint(.rightEar)
        neck          = joint(.neck)
        leftShoulder  = joint(.leftShoulder)
        rightShoulder = joint(.rightShoulder)
        leftElbow     = joint(.leftElbow)
        rightElbow    = joint(.rightElbow)
        leftWrist     = joint(.leftWrist)
        rightWrist    = joint(.rightWrist)
        leftHip       = joint(.leftHip)
        rightHip      = joint(.rightHip)
        leftKnee      = joint(.leftKnee)
        rightKnee     = joint(.rightKnee)
        leftAnkle     = joint(.leftAnkle)
        rightAnkle    = joint(.rightAnkle)
    }
}
