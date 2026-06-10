import SwiftUI

// AnalysisPanel — the bottom card that combines the score ring (PostureScoreView)
// with the list of detected issues (IssueRowView).
//
// This is the only analysis UI that LiveAnalysisView places directly. It is a
// "dumb" view: it takes a score and a list of issues and renders them. It owns no
// state and does no analysis — that keeps it trivially previewable and testable.
//
// Layout (top to bottom):
//   [ score ring ]  [ "Posture Score" + one-line summary ]
//   ── issues ──
//   either a list of IssueRowViews, or a "good posture" confirmation row.

struct AnalysisPanel: View {

    let score: Int
    let issues: [PostureIssue]

    // One-line plain-English summary that matches the ring colour band.
    // Gives the number meaning — "82" alone doesn't tell a beginner if that's good.
    private var scoreSummary: String {
        switch score {
        case 75...100: return "Good posture"
        case 50..<75:  return "Needs attention"
        default:       return "Significant issues"
        }
    }

    var body: some View {
        VStack(spacing: 12) {

            // Header: ring on the left, label + summary on the right.
            HStack(spacing: 16) {
                PostureScoreView(score: score)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Posture Score")
                        .font(.headline)

                    Text(scoreSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Issue list — or a positive confirmation when there's nothing wrong.
            // Showing a green "all clear" row is important: an empty panel would
            // look broken / make the user wonder if detection is even working.
            if issues.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)

                    Text("Good posture detected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(8)
            } else {
                ForEach(issues) { issue in
                    IssueRowView(issue: issue)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(.horizontal)
    }
}
