import Foundation
import Combine

// PostureAnalyzer — rules engine that evaluates a BodyPose and produces
// a posture score (0–100) and a list of active PostureIssues.
//
// Architecture role:
// - Sits between the Vision layer (BodyPose in) and the UI layer (score + issues out)
// - Analysis layer is UIKit/SwiftUI-free — pure Swift, fully unit testable
// - Each check is a private function returning PostureIssue? (nil = no problem detected)
//
// Threading:
// analyze() is called from LiveViewModel's Combine sink, which receives
// camera.$currentPose published on the main thread. So all @Published
// updates here happen on the main thread naturally — no extra dispatch needed.
//
// Score smoothing:
// Raw scores are averaged over a rolling window to prevent frame-to-frame
// flickering caused by minor keypoint jitter.

class PostureAnalyzer: ObservableObject {

    @Published var currentIssues: [PostureIssue] = []
    @Published var postureScore: Int = 100

    // Rolling window for score smoothing — averages over the last N frames.
    // At 30fps, window=10 = 333ms of smoothing lag.
    // Reduce to 6 if response feels sluggish; increase to 15 if still flickering.
    private var scoreHistory: [Int] = []
    private let scoreWindow = 10

    // MARK: - FHP thresholds
    // Named constants so threshold tuning (L2-018) has one place to change.
    // Values are normalised (0–1): 0.08 = ear ~8% of frame width forward of shoulder.
    // These are starting points — calibrate on a real device in L2-018.
    private let fhpMildThreshold     = 0.04  // barely noticeable forward lean
    private let fhpModerateThreshold = 0.08  // clearly visible, adds neck strain
    private let fhpSevereThreshold   = 0.14  // significant forward head position

    // MARK: - Main analysis entry point

    // Evaluate all active checks against the current pose and update published properties.
    // Called every camera frame (~30fps).
    func analyze(_ pose: BodyPose) {
        // CRITICAL: clear at the START of every call.
        // If you clear at the end, a crash mid-analysis leaves stale issues on screen.
        // If you forget to clear entirely, issues accumulate indefinitely every frame.
        var issues: [PostureIssue] = []

        // Only run checks when we have a valid full-body pose.
        // isValid requires both shoulders and both hips — minimum geometry for analysis.
        guard pose.isValid else {
            publishResults(issues: [], score: calculateScore(from: []))
            return
        }

        // Run active checks — append result if an issue was detected.
        // Other checks (shoulder, spinal, hip) added here in L2-010/011/012.
        if let issue = checkForwardHead(pose) { issues.append(issue) }

        publishResults(issues: issues, score: calculateScore(from: issues))
    }

    // MARK: - Score calculation

    // Calculates a smoothed posture score from the current issue list.
    // Raw score = 100 minus each issue's severityScore, clamped to 0.
    // Smoothed score = rolling average over scoreWindow frames.
    private func calculateScore(from issues: [PostureIssue]) -> Int {
        let rawScore = max(0, 100 - issues.reduce(0) { $0 + $1.severityScore })

        scoreHistory.append(rawScore)
        if scoreHistory.count > scoreWindow {
            scoreHistory.removeFirst()
        }

        return scoreHistory.reduce(0, +) / scoreHistory.count
    }

    // Publishes results — single place to update both @Published properties together.
    // Keeping them in sync prevents a frame where issues updated but score hasn't yet.
    private func publishResults(issues: [PostureIssue], score: Int) {
        currentIssues = issues
        postureScore = score
    }
}

// MARK: - Forward Head Posture check

extension PostureAnalyzer {

    // Detects forward head posture by measuring the horizontal distance between
    // the ear and the shoulder on the same side.
    //
    // Clinical basis:
    // A neutral spine has the ear directly above the shoulder in the coronal plane.
    // When the head protrudes forward, the ear moves away from the shoulder horizontally.
    // From a front-facing camera, this shows as an increased X-axis offset.
    //
    // Limitation: this camera angle captures the 2D projection of a 3D movement.
    // True forward head posture is best measured from the side — but the horizontal
    // offset from a front camera is a reliable proxy and good enough for V1.
    private func checkForwardHead(_ pose: BodyPose) -> PostureIssue? {

        // Prefer the left ear — fall back to right if left isn't detected.
        // Using one ear is intentional: FHP is a bilateral issue, either ear
        // relative to its same-side shoulder gives a valid measurement.
        guard let ear = pose.leftEar ?? pose.rightEar else { return nil }

        // Use the shoulder on the same side as the ear we selected.
        // Comparing left ear to right shoulder would measure neck tilt, not FHP.
        let shoulder: BodyPose.Joint?
        if pose.leftEar != nil {
            shoulder = pose.leftShoulder
        } else {
            shoulder = pose.rightShoulder
        }
        guard let shoulder else { return nil }

        let offset = AngleCalculator.horizontalOffset(ear.position, shoulder.position)

        // Apply severity thresholds.
        // These starting values are calibrated for a person 6–8 feet from the camera.
        // Real-device tuning happens in L2-018 using the debug overlay.
        if offset > fhpSevereThreshold {
            return PostureIssue(type: .forwardHead, severity: .severe)
        } else if offset > fhpModerateThreshold {
            return PostureIssue(type: .forwardHead, severity: .moderate)
        } else if offset > fhpMildThreshold {
            return PostureIssue(type: .forwardHead, severity: .mild)
        }

        return nil
    }
}
