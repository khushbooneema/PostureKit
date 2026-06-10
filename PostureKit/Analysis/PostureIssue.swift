import Foundation

// PostureIssue — a single detected posture problem.
//
// Value type (struct) so it can be passed freely between Analysis, UI,
// and Storage layers without reference counting or threading concerns.
//
// Identifiable: lets SwiftUI ForEach track rows without needing an explicit id parameter.
//
// IssueType uses String rawValue so it can be stored directly in SwiftData
// (Layer 3) as a plain string — no conversion code needed.

struct PostureIssue: Identifiable {

    // MARK: - Nested types

    enum IssueType: String, CaseIterable {
        case forwardHead        = "forwardHead"
        case shoulderImbalance  = "shoulderImbalance"
        case spinalTilt         = "spinalTilt"
        case hipImbalance       = "hipImbalance"
        case headTilt           = "headTilt"

        var displayName: String {
            switch self {
            case .forwardHead:       return "Forward Head Posture"
            case .shoulderImbalance: return "Shoulder Symmetry"
            case .spinalTilt:        return "Trunk Lateral Tilt"
            case .hipImbalance:      return "Hip Symmetry"
            case .headTilt:          return "Head Tilt"
            }
        }
    }

    enum Severity: String {
        case mild     = "mild"
        case moderate = "moderate"
        case severe   = "severe"
    }

    // MARK: - Properties

    let id = UUID()
    let type: IssueType
    let severity: Severity
    let description: String

    // Points deducted from the 100-point posture score.
    // Severity bands are intentionally non-linear — severe is not just 2× moderate.
    // A severe issue (35pts) causes a clearly bad score even without other issues.
    var severityScore: Int {
        switch severity {
        case .mild:     return 10
        case .moderate: return 20
        case .severe:   return 35
        }
    }

    // Visual indicator per issue type — used in IssueRowView.
    var emoji: String {
        switch type {
        case .forwardHead:       return "🔺"
        case .shoulderImbalance: return "↕️"
        case .spinalTilt:        return "↔️"
        case .hipImbalance:      return "🦴"
        case .headTilt:          return "↗️"
        }
    }

    // MARK: - Init

    // Description is auto-set from the type + severity combination.
    // Callers never pass a description string — it is always derived.
    // This prevents mismatches between issue type and display text.
    init(type: IssueType, severity: Severity) {
        self.type = type
        self.severity = severity
        self.description = PostureIssue.description(for: type, severity: severity)
    }

    // MARK: - Display descriptions

    // Plain-English guidance shown to the user.
    //
    // Writing rules (from the Layer 2 doc):
    // - Write like talking to a friend, not a medical report
    // - Every message tells the user what to DO, not just what is wrong
    // - No words: danger, injury, damage, pain — they increase anxiety without usefulness
    // - FHP descriptions are fully written (Layer 2 focus)
    // - Other checks have placeholder text — to be completed when those checks are added
    static func description(for type: IssueType, severity: Severity) -> String {
        switch (type, severity) {

        // Forward Head Posture — fully implemented in Layer 2
        case (.forwardHead, .mild):
            return "Head is slightly forward. Try bringing your ears back over your shoulders."
        case (.forwardHead, .moderate):
            return "Head is noticeably forward. This adds strain to your neck muscles."
        case (.forwardHead, .severe):
            return "Head is significantly forward. Consider a short break and neck stretch."

        // Shoulder Imbalance — one shoulder higher than the other
        case (.shoulderImbalance, .mild):
            return "Shoulders are slightly uneven. Check if you are tensing one side."
        case (.shoulderImbalance, .moderate):
            return "One shoulder is noticeably raised. Consciously roll both shoulders back and down."
        case (.shoulderImbalance, .severe):
            return "One shoulder is significantly higher. Try a shoulder roll and let both sides drop equally."

        // Spinal Tilt — lateral lean of the whole trunk (shoulder-to-hip axis)
        case (.spinalTilt, .mild):
            return "Slight lateral lean detected. Try distributing weight evenly across both feet."
        case (.spinalTilt, .moderate):
            return "Torso is leaning to one side. Stand with feet hip-width apart and let your arms hang evenly."
        case (.spinalTilt, .severe):
            return "Significant lateral lean. Try standing against a wall to feel what a neutral, centred spine feels like."

        // Hip Imbalance — one hip higher than the other (lateral pelvic tilt / weight shift)
        case (.hipImbalance, .mild):
            return "Hips are slightly uneven. Try distributing your weight equally on both feet."
        case (.hipImbalance, .moderate):
            return "One hip is raised — often a sign of weight shifting to one leg. Try standing evenly."
        case (.hipImbalance, .severe):
            return "Hips are significantly uneven. Try planting both feet flat and consciously levelling your pelvis."

        // Head Tilt — head rotated so one ear is higher than the other
        case (.headTilt, .mild):
            return "Head is slightly tilted to one side. Gently lengthen the back of your neck and level your ears."
        case (.headTilt, .moderate):
            return "Noticeable head tilt. Imagine a thread pulling the crown of your head straight up to re-centre."
        case (.headTilt, .severe):
            return "Head is significantly tilted. Focus on bringing your ears parallel to the ground before you stand."
        }
    }
}
