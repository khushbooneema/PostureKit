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
    @Published var postureScore: Int?

    // Rolling window for score smoothing — averages over the last N frames.
    // At 30fps, window=10 = 333ms of smoothing lag.
    // Reduce to 6 if response feels sluggish; increase to 15 if still flickering.
    private var scoreHistory: [Int] = []
    private let scoreWindow = 10

    // MARK: - Single-shot analysis (photo capture flow)

    // Runs angle-appropriate checks against a single pose and returns the results directly.
    // Used by PhotoCaptureViewModel — no rolling window, no @Published side effects.
    //
    // Why angle-aware:
    // CVA (craniovertebral angle) is a sagittal-plane measurement — it only works when
    // the camera sees the person from the side. From a front-facing camera the ear sits
    // directly above the shoulder in X regardless of FHP, so CVA always reads ~90° and
    // gives a false "no issue" result. Running the wrong check on the wrong angle produces
    // misleading scores, so each angle gets its own check list.
    //
    // Why no pose.isValid guard here:
    // isValid requires ALL of leftShoulder + rightShoulder + leftHip + rightHip.
    // In a side or back photo, one hip is often occluded and Vision drops it — isValid
    // returns false and the entire analysis is skipped, giving a spurious 100 score.
    // Each individual check already guards on the specific keypoints it needs, so letting
    // them self-guard is both correct and more robust to partial occlusion.
    // Returns issues, score, and the raw CVA angle (side view only — nil for front/back).
    // The CVA angle is surfaced so the UI can show the user exactly where they land
    // on the clinical threshold scale, even when posture is good (no issue produced).
    func analyzeOnce(_ pose: BodyPose, for angle: CaptureAngle) -> (issues: [PostureIssue], score: Int, cvaAngle: Double?) {
        var issues: [PostureIssue] = []
        var cvaAngle: Double? = nil

        switch angle {
        case .side:
            // CVA requires a side profile — the ear's forward displacement is visible
            // as horizontal separation from the shoulder only in the sagittal plane.
            let (issue, cva) = checkForwardHead(pose)
            if let issue { issues.append(issue) }
            cvaAngle = cva  // return even when posture is good, so UI can show "52° — Normal"

        case .front:
            // FHP via CVA does not apply here — forward displacement appears as depth
            // (into/out of the camera), not horizontal offset, so CVA stays ~90°.
            // Shoulder symmetry and hip symmetry checks will go here (future layers).
            break

        case .back:
            // Spinal alignment and posterior shoulder symmetry checks go here (future layers).
            break
        }

        let score = max(0, 100 - issues.reduce(0) { $0 + $1.severityScore })
        return (issues, score, cvaAngle)
    }

    // MARK: - CVA thresholds (degrees)
    // Craniovertebral Angle thresholds from clinical literature.
    // A higher CVA is better — 90° means the ear is directly above the shoulder.
    // Values below each threshold trigger the corresponding severity.
    private let cvaNormalThreshold   = 50.0  // ≥ 50° = neutral, no issue
    private let cvaMildThreshold     = 45.0  // 45–49° = mild FHP
    private let cvaModerateThreshold = 35.0  // 35–44° = moderate FHP
                                             // < 35°  = severe FHP

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
            return
        }

        // Run active checks — append result if an issue was detected.
        // Other checks (shoulder, spinal, hip) added here in L2-010/011/012.
        let (issue, _) = checkForwardHead(pose)
        if let issue { issues.append(issue) }

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

    // Detects forward head posture using the Craniovertebral Angle (CVA).
    //
    // Clinical basis:
    // CVA = the angle between a horizontal line through C7 (approximated by the
    // shoulder keypoint) and the line from C7 up to the tragus of the ear.
    // A neutral spine has the ear directly above the shoulder, giving CVA ≈ 90°.
    // As the head protrudes forward, the ear shifts in front of the shoulder and
    // the CVA decreases toward horizontal (0°).
    //
    // Why CVA over horizontal offset:
    // Horizontal offset is a raw pixel distance — it grows when the subject stands
    // closer to the camera even with perfect posture. CVA is a geometric angle
    // (rise/run ratio), so it remains consistent regardless of distance or height.
    //
    // Best measured from a side-view photo (sagittal plane) where forward
    // displacement is visible as horizontal separation in the image.
    // Returns both the PostureIssue (nil if posture is good) and the raw CVA angle.
    // The angle is always returned when keypoints are found — even for good posture —
    // so the UI can display "52.3° — Normal" and show the user where they land on the scale.
    private func checkForwardHead(_ pose: BodyPose) -> (issue: PostureIssue?, cvaAngle: Double?) {

        // Prefer the ear/shoulder pair that Vision detected with higher confidence.
        // Using one side is intentional: FHP is a bilateral pattern, either side
        // relative to its same-side shoulder gives a valid CVA measurement.
        let (ear, shoulder): (BodyPose.Joint, BodyPose.Joint)
        if let leftEar = pose.leftEar, let leftShoulder = pose.leftShoulder {
            (ear, shoulder) = (leftEar, leftShoulder)
        } else if let rightEar = pose.rightEar, let rightShoulder = pose.rightShoulder {
            (ear, shoulder) = (rightEar, rightShoulder)
        } else {
            return (nil, nil)
        }

        let cva = AngleCalculator.craniovertebralAngle(ear: ear.position, shoulder: shoulder.position)

        // Lower CVA = worse posture. Thresholds from clinical literature.
        if cva < cvaModerateThreshold {
            return (PostureIssue(type: .forwardHead, severity: .severe), cva)
        } else if cva < cvaMildThreshold {
            return (PostureIssue(type: .forwardHead, severity: .moderate), cva)
        } else if cva < cvaNormalThreshold {
            return (PostureIssue(type: .forwardHead, severity: .mild), cva)
        }

        return (nil, cva)
    }
}
