import Foundation
import CoreML

// PostureMLBridge runs the CreateML tabular classifier on a detected BodyPose (FR-21).
//
// The model (PostureClassifier.mlmodel) was trained on flat rows of
// 18 joints × (x, y, confidence) + capture_angle, with -1.0 as the
// "joint not detected" sentinel. This bridge reproduces that exact row
// format at inference time — any mismatch between training columns and
// prediction features silently degrades accuracy, so the keypoint order
// and sentinel convention here MUST stay in sync with:
//   - DataCollectionViewModel.makeKeypointDict  (real captures)
//   - scripts/generate_training_data.py         (synthetic data)
//
// Note: Xcode compiles the .mlmodel at build time and generates the
// PostureClassifier class into DerivedData — it never appears in the
// project navigator. We use the generated class only to locate/load the
// compiled model; prediction goes through MLDictionaryFeatureProvider
// so we don't need the 55-parameter generated input type.

// MARK: - Prediction result

// One classifier prediction for a single pose.
// Carried inside AngleResult so the analysis screen can show the
// ML opinion alongside the rule-based checks.
struct MLPrediction {
    let label: PostureLabel        // the winning class
    let confidence: Double         // probability of the winning class (0–1)
    let probabilities: [PostureLabel: Double]  // full distribution, for the debug view (FR-22)

    var displayText: String {
        "\(label.displayName) (\(Int(confidence * 100))%)"
    }
}

// MARK: - Bridge

final class PostureMLBridge {

    // Loaded once on first predict() call. Tabular classifier models are small
    // (~1 MB) so the load is fast, but there's no reason to pay it before the
    // first prediction is actually needed.
    private lazy var model: MLModel? = {
        try? PostureClassifier(configuration: MLModelConfiguration()).model
    }()

    // Runs the classifier. Returns nil when the model failed to load or the
    // prediction errored — callers treat nil as "no ML opinion available"
    // and fall back to rule-based results only.
    func predict(pose: BodyPose, angle: CaptureAngle) -> MLPrediction? {
        guard let model else { return nil }

        let features = makeFeatureDict(pose: pose, angle: angle)
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: features),
              let output = try? model.prediction(from: provider),
              let rawLabel = output.featureValue(for: "label")?.stringValue,
              let label = PostureLabel(rawValue: rawLabel)
        else { return nil }

        // labelProbability is [String: Double] keyed by class name.
        var probabilities: [PostureLabel: Double] = [:]
        if let probDict = output.featureValue(for: "labelProbability")?.dictionaryValue {
            for (key, value) in probDict {
                if let l = PostureLabel(rawValue: key as? String ?? "") {
                    probabilities[l] = value.doubleValue
                }
            }
        }

        return MLPrediction(
            label: label,
            confidence: probabilities[label] ?? 0,
            probabilities: probabilities
        )
    }

    // MARK: - Feature row construction

    // Builds the 55-feature dictionary matching the training columns.
    // Missing joints → (-1, -1, 0) — same sentinel the model was trained on.
    private func makeFeatureDict(pose: BodyPose, angle: CaptureAngle) -> [String: Any] {
        let angleString: String
        switch angle {
        case .front: angleString = "front"
        case .side:  angleString = "side"
        case .back:  angleString = "back"
        }

        var features: [String: Any] = ["capture_angle": angleString]

        let joints: [(String, BodyPose.Joint?)] = [
            ("nose",          pose.nose),
            ("neck",          pose.neck),
            ("leftEye",       pose.leftEye),
            ("rightEye",      pose.rightEye),
            ("leftEar",       pose.leftEar),
            ("rightEar",      pose.rightEar),
            ("leftShoulder",  pose.leftShoulder),
            ("rightShoulder", pose.rightShoulder),
            ("leftElbow",     pose.leftElbow),
            ("rightElbow",    pose.rightElbow),
            ("leftWrist",     pose.leftWrist),
            ("rightWrist",    pose.rightWrist),
            ("leftHip",       pose.leftHip),
            ("rightHip",      pose.rightHip),
            ("leftKnee",      pose.leftKnee),
            ("rightKnee",     pose.rightKnee),
            ("leftAnkle",     pose.leftAnkle),
            ("rightAnkle",    pose.rightAnkle),
        ]

        for (name, joint) in joints {
            if let joint {
                features["\(name)_x"]          = Double(joint.position.x)
                features["\(name)_y"]          = Double(joint.position.y)
                features["\(name)_confidence"] = Double(joint.confidence)
            } else {
                features["\(name)_x"]          = -1.0
                features["\(name)_y"]          = -1.0
                features["\(name)_confidence"] = 0.0
            }
        }

        return features
    }
}
