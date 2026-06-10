import SwiftUI

// IssueRowView — one row in the analysis panel describing a single detected issue.
//
// Layout (left to right):
//   [emoji]  [issue title + guidance]  [Spacer]  [severity badge]
//
// Why a dedicated row view:
// Keeping the row in its own file means the panel (AnalysisPanel) just does a
// ForEach over issues — it never worries about how a single issue looks. If we
// later want to add a tap action, animation, or icon per row, it changes here only.

struct IssueRowView: View {

    let issue: PostureIssue

    // Badge colour mirrors the score ring convention so the whole UI speaks
    // the same colour language: mild = yellow, moderate = orange, severe = red.
    var severityColor: Color {
        switch issue.severity {
        case .mild:     return .yellow
        case .moderate: return .orange
        case .severe:   return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            // Quick visual identifier for the issue type.
            Text(issue.emoji)
                .font(.title2)

            // Title + plain-English guidance.
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.bold)

                Text(issue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true) // allow multi-line wrap
            }

            Spacer()

            // Severity badge — short, uppercased, colour-outlined pill.
            Text(issue.severity.rawValue.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(severityColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(severityColor, lineWidth: 1)
                )
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }
}
