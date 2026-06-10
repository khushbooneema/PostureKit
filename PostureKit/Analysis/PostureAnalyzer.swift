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
            // From a front-facing camera, CVA reads ~90° regardless of FHP (the head
            // protrudes in depth, not X). Instead we check:
            //   • Shoulder height symmetry  — one shoulder raised
            //   • Hip height symmetry       — lateral pelvic tilt / weight shift
            //   • Trunk lateral tilt        — shoulder-to-hip axis angle from vertical
            //   • Head tilt                 — ear height asymmetry (head rotated sideways)
            if let issue = checkShoulderSymmetry(pose)   { issues.append(issue) }
            if let issue = checkHipSymmetry(pose)        { issues.append(issue) }
            if let issue = checkTrunkLateralTilt(pose)   { issues.append(issue) }
            if let issue = checkHeadTilt(pose)           { issues.append(issue) }

        case .back:
            // Same structural checks as front — ears unreliable from behind, so skip head tilt.
            if let issue = checkShoulderSymmetry(pose)   { issues.append(issue) }
            if let issue = checkHipSymmetry(pose)        { issues.append(issue) }
            if let issue = checkTrunkLateralTilt(pose)   { issues.append(issue) }
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

    // MARK: - Shoulder symmetry

    // Detects one shoulder raised higher than the other.
    // Ratio = vertical height difference / horizontal shoulder width.
    // Normalising by shoulder width keeps the result consistent across camera distances.
    //
    // Thresholds (empirical — may need calibration per camera setup):
    //   mild     > 0.08  (~1 cm raise visible at arm's length)
    //   moderate > 0.15  (clearly visible shoulder hike)
    //   severe   > 0.25  (obvious postural asymmetry)
    private func checkShoulderSymmetry(_ pose: BodyPose) -> PostureIssue? {
        guard let ls = pose.leftShoulder, let rs = pose.rightShoulder,
              ls.isReliable, rs.isReliable else { return nil }

        let ratio = AngleCalculator.symmetryRatio(a: ls.position, b: rs.position)

        if ratio > 0.25 {
            return PostureIssue(type: .shoulderImbalance, severity: .severe)
        } else if ratio > 0.15 {
            return PostureIssue(type: .shoulderImbalance, severity: .moderate)
        } else if ratio > 0.08 {
            return PostureIssue(type: .shoulderImbalance, severity: .mild)
        }
        return nil
    }

    // MARK: - Hip symmetry

    // Detects one hip higher than the other (lateral pelvic tilt / weight shift).
    // Uses the same normalised-ratio approach as shoulder symmetry.
    private func checkHipSymmetry(_ pose: BodyPose) -> PostureIssue? {
        guard let lh = pose.leftHip, let rh = pose.rightHip,
              lh.isReliable, rh.isReliable else { return nil }

        let ratio = AngleCalculator.symmetryRatio(a: lh.position, b: rh.position)

        if ratio > 0.25 {
            return PostureIssue(type: .hipImbalance, severity: .severe)
        } else if ratio > 0.15 {
            return PostureIssue(type: .hipImbalance, severity: .moderate)
        } else if ratio > 0.08 {
            return PostureIssue(type: .hipImbalance, severity: .mild)
        }
        return nil
    }

    // MARK: - Trunk lateral tilt (front + back views)

    // Measures the angle of the trunk from vertical using the shoulder midpoint and hip midpoint.
    // This is the clinically correct way to detect lateral trunk lean — it uses 4 joints
    // instead of the nose proxy, and is robust to the person facing slightly off-axis.
    //
    // Requires both shoulders AND both hips to be reliably detected. In a pure side photo
    // one hip is occluded and this check will silently return nil — that is intentional,
    // since trunk tilt is not meaningful from a side angle anyway.
    //
    // Thresholds (degrees from vertical):
    //   < 3°   — normal variation, no issue
    //   3–6°   — mild lean
    //   6–10°  — moderate lean
    //   > 10°  — severe lean
    private func checkTrunkLateralTilt(_ pose: BodyPose) -> PostureIssue? {
        guard let ls = pose.leftShoulder,  ls.isReliable,
              let rs = pose.rightShoulder, rs.isReliable,
              let lh = pose.leftHip,       lh.isReliable,
              let rh = pose.rightHip,      rh.isReliable else { return nil }

        let shoulderMid = CGPoint(
            x: (ls.position.x + rs.position.x) / 2,
            y: (ls.position.y + rs.position.y) / 2
        )
        let hipMid = CGPoint(
            x: (lh.position.x + rh.position.x) / 2,
            y: (lh.position.y + rh.position.y) / 2
        )

        let tiltDegrees = AngleCalculator.trunkTiltAngle(shoulderMid: shoulderMid, hipMid: hipMid)

        if tiltDegrees > 10 {
            return PostureIssue(type: .spinalTilt, severity: .severe)
        } else if tiltDegrees > 6 {
            return PostureIssue(type: .spinalTilt, severity: .moderate)
        } else if tiltDegrees > 3 {
            return PostureIssue(type: .spinalTilt, severity: .mild)
        }
        return nil
    }

    // MARK: - Head tilt (front view only)

    // Detects lateral head rotation — one ear is higher than the other.
    // This is distinct from trunk tilt: the torso can be straight while the head
    // is tilted sideways (cranial lateral flexion), and vice versa.
    //
    // Normalised by shoulder width so the result is consistent across camera distances.
    // Only meaningful from the front — ears are not reliably detected from the back.
    //
    // Thresholds (ear height difference / shoulder width):
    //   > 0.06 — mild tilt   (~half a head width deviation for an average person)
    //   > 0.12 — moderate
    //   > 0.20 — severe
    private func checkHeadTilt(_ pose: BodyPose) -> PostureIssue? {
        guard let le = pose.leftEar,       le.isReliable,
              let re = pose.rightEar,      re.isReliable,
              let ls = pose.leftShoulder,  ls.isReliable,
              let rs = pose.rightShoulder, rs.isReliable else { return nil }

        let shoulderWidth = abs(Double(ls.position.x) - Double(rs.position.x))
        guard shoulderWidth > 0 else { return nil }

        let earHeightDiff = abs(Double(le.position.y) - Double(re.position.y))
        let ratio = earHeightDiff / shoulderWidth

        if ratio > 0.20 {
            return PostureIssue(type: .headTilt, severity: .severe)
        } else if ratio > 0.12 {
            return PostureIssue(type: .headTilt, severity: .moderate)
        } else if ratio > 0.06 {
            return PostureIssue(type: .headTilt, severity: .mild)
        }
        return nil
    }

    // MARK: - Forward Head Posture check

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
