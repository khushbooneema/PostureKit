import Foundation

// PostureLabel — the classification labels used when recording training samples.
//
// rawValue is the string written into the JSON export and becomes the CreateML
// target column. Keep the taxonomy coarse for v1 (one label per condition, no
// severity). Once you have 200+ samples per condition you can relabel and retrain
// with severity splits (e.g. "forward_head_mild", "forward_head_severe").
enum PostureLabel: String, CaseIterable, Hashable {
    case normal             = "normal"
    case forwardHead        = "forward_head"
    case shoulderAsymmetry  = "shoulder_asymmetry"
    case hipAsymmetry       = "hip_asymmetry"
    case trunkTilt          = "trunk_tilt"
    case headTilt           = "head_tilt"

    var displayName: String {
        switch self {
        case .normal:            return "Normal"
        case .forwardHead:       return "Forward Head"
        case .shoulderAsymmetry: return "Shoulder Asymmetry"
        case .hipAsymmetry:      return "Hip Asymmetry"
        case .trunkTilt:         return "Trunk Tilt"
        case .headTilt:          return "Head Tilt"
        }
    }
}

// PoseSample — one labelled training example.
//
// Stores the full 18-joint body pose as a flat keypoint dictionary so it can
// be trivially serialised to the row format CreateML expects.
//
// Foundation-only: no UIKit, no Vision, no SwiftUI. The conversion from
// BodyPose to this struct happens in DataCollectionViewModel (which imports those
// frameworks) so this model stays testable on any platform.
struct PoseSample: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let label: String          // PostureLabel.rawValue
    let captureAngle: String   // "front" | "side" | "back"
    let keypoints: [String: KeypointData]

    // A single Vision joint in normalised image space (origin bottom-left, 0–1).
    //
    // Sentinel convention: x = -1, y = -1 means the joint was not detected.
    // We use -1 rather than 0 because 0 is a valid coordinate (left/bottom edge
    // of the frame). The model sees -1 as a distinct "missing" signal.
    struct KeypointData: Codable {
        let x: Float
        let y: Float
        let confidence: Float

        static let missing = KeypointData(x: -1.0, y: -1.0, confidence: 0.0)
    }
}
