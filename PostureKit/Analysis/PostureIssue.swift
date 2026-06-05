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

        // Shoulder Imbalance — placeholder until L2-010
        case (.shoulderImbalance, .mild):
            return "Shoulders are slightly uneven. Check if you are tensing one side."
        case (.shoulderImbalance, .moderate), (.shoulderImbalance, .severe):
            return "One shoulder is raised. Try consciously relaxing both shoulders down."

        // Spinal Tilt — placeholder until L2-011
        case (.spinalTilt, .mild), (.spinalTilt, .moderate):
            return "Your torso is leaning to one side. Try shifting your weight to centre."
        case (.spinalTilt, .severe):
            return "Significant torso lean detected. Try standing with feet hip-width apart."

        // Hip Imbalance — placeholder until L2-012
        case (.hipImbalance, _):
            return "Hips are uneven. Try distributing your weight equally on both feet."
        }
    }
}
