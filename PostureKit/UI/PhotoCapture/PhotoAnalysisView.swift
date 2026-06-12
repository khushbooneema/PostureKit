import SwiftUI

// PhotoAnalysisView — the results screen shown after all three photos are captured.
//
// Layout (top to bottom):
//   Overall score header  (average across all three angles)
//   Segmented angle picker  ← tappable shortcut
//   Swipeable photo carousel with skeleton overlay (highlights affected joints/bones)
//   Per-angle detail panel (scrollable):
//     • Side view  → CVAScaleView (CVA angle + colour-coded threshold bar) + FHP issue row
//     • Front/back → score summary + full checklist of every check performed (pass or fail)

struct PhotoAnalysisView: View {

    @ObservedObject var viewModel: PhotoCaptureViewModel

    // Drives both the segment picker and the TabView — changing either updates the other.
    @State private var selectedIndex: Int = 0

    private var currentResult: AngleResult? {
        viewModel.results.indices.contains(selectedIndex) ? viewModel.results[selectedIndex] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            overallHeader

            anglePicker
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            photoCarousel

            issueScrollView
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Subviews

    // Compact header: title on the left, overall score chip on the right.
    // Caption clarifies the score is FHP-based so the user knows what's measured.
    private var overallHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Assessment Results")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("Tap an angle or swipe the photo to compare")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            overallScoreChip
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // Coloured pill showing the overall average score.
    private var overallScoreChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(scoreColor(viewModel.overallScore))
                .frame(width: 8, height: 8)
            Text("\(viewModel.overallScore)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(viewModel.overallScore))
            Text("/ 100")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }

    // Segmented picker — tapping jumps directly to that angle's photo.
    // Stays in sync with swiping via the shared selectedIndex binding.
    private var anglePicker: some View {
        Picker("Angle", selection: $selectedIndex) {
            ForEach(viewModel.results.indices, id: \.self) { idx in
                Text(viewModel.results[idx].angle.title).tag(idx)
            }
        }
        .pickerStyle(.segmented)
    }

    // TabView paged carousel — each page is the photo with skeleton drawn on top.
    // .page indexDisplayMode .always shows the standard iOS page dots.
    // Binding to selectedIndex keeps it in sync with the segment picker above.
    private var photoCarousel: some View {
        TabView(selection: $selectedIndex) {
            ForEach(viewModel.results.indices, id: \.self) { idx in
                SkeletonOnPhotoView(result: viewModel.results[idx])
                    .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 420)
        .background(Color.black)
    }

    // Per-angle detail panel — content differs by angle.
    // Side view: CVAScaleView is the primary metric (it IS the check we run).
    // Front/back: generic score row + a note that checks for that angle come later.
    private var issueScrollView: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let result = currentResult {
                    if result.angle == .side, let cva = result.cvaAngle {
                        // Side view — CVA is the full story.
                        CVAScaleView(angle: cva)
                            .transition(.opacity)

                        // Show issue row only when FHP is detected (mild/moderate/severe).
                        // CVAScaleView already describes the condition; the row adds the
                        // specific corrective guidance from PostureIssue.description.
                        if !result.issues.isEmpty {
                            ForEach(result.issues) { issue in
                                IssueRowView(issue: issue)
                            }
                            .transition(.opacity)
                        }

                    } else {
                        // Front / back — score summary + full checklist so the user sees
                        // every check that was run, not just the ones that failed.
                        angleScoreRow(result)
                            .transition(.opacity)

                        ForEach(performedChecks(for: result), id: \.name) { check in
                            checkRow(check)
                                .transition(.opacity)
                        }
                    }

                    // ML classifier opinion (FR-21) — shown for every angle when the
                    // model produced a prediction. Runs independently of the rule-based
                    // checks above, so agreement between the two is a good sign and
                    // disagreement is worth a second look (debug view, FR-22).
                    if let prediction = result.mlPrediction {
                        mlPredictionRow(prediction)
                            .transition(.opacity)
                    }
                }

                Divider().padding(.top, 4)

                Button("New Assessment") {
                    viewModel.restart()
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .animation(.easeInOut(duration: 0.2), value: selectedIndex)
        }
    }

    // Angle name + issue count on the left, large score number on the right.
    private func angleScoreRow(_ result: AngleResult) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: result.angle.icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.angle.title)
                        .font(.headline)
                    Text(result.issues.isEmpty
                         ? "No issues detected"
                         : "\(result.issues.count) issue\(result.issues.count == 1 ? "" : "s") found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 0) {
                Text("\(result.score)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(result.score))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.25), value: result.score)
                Text("/ 100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
    }

    // MARK: - ML prediction row (FR-21)

    // Compact card showing the classifier's top label and its confidence.
    // Styled differently from the rule-based check rows (brain icon, purple tint)
    // so the user understands this is a model opinion, not a measured angle.
    private func mlPredictionRow(_ prediction: MLPrediction) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Classifier")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(prediction.label.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Confidence as a percentage chip
            Text("\(Int(prediction.confidence * 100))%")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(8)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
    }

    // MARK: - Check list (front / back)

    // Maps each angle to the checks PostureAnalyzer.analyzeOnce actually ran,
    // so the user sees every check — not just the ones that produced an issue.
    private struct PerformedCheck {
        let name: String
        let passedNote: String      // short positive message when issue == nil
        let issue: PostureIssue?    // nil = passed
        var passed: Bool { issue == nil }
    }

    private func performedChecks(for result: AngleResult) -> [PerformedCheck] {
        func find(_ type: PostureIssue.IssueType) -> PostureIssue? {
            result.issues.first { $0.type == type }
        }
        switch result.angle {
        case .front:
            return [
                PerformedCheck(name: "Shoulder Symmetry",
                               passedNote: "Both shoulders appear level",
                               issue: find(.shoulderImbalance)),
                PerformedCheck(name: "Hip Symmetry",
                               passedNote: "Hips appear level",
                               issue: find(.hipImbalance)),
                PerformedCheck(name: "Trunk Lateral Tilt",
                               passedNote: "Torso is upright",
                               issue: find(.spinalTilt)),
                PerformedCheck(name: "Head Tilt",
                               passedNote: "Head is centred and level",
                               issue: find(.headTilt)),
            ]
        case .back:
            return [
                PerformedCheck(name: "Shoulder Symmetry",
                               passedNote: "Both shoulders appear level",
                               issue: find(.shoulderImbalance)),
                PerformedCheck(name: "Hip Symmetry",
                               passedNote: "Hips appear level",
                               issue: find(.hipImbalance)),
                PerformedCheck(name: "Trunk Lateral Tilt",
                               passedNote: "Torso is upright",
                               issue: find(.spinalTilt)),
            ]
        case .side:
            return []   // CVAScaleView handles side view — no list needed
        }
    }

    @ViewBuilder
    private func checkRow(_ check: PerformedCheck) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Left icon: green fill for pass, issue emoji for fail
            Group {
                if check.passed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(check.issue!.emoji)
                }
            }
            .font(.title3)
            .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(check.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    // Status badge
                    if let issue = check.issue {
                        statusBadge(issue.severity.rawValue.uppercased(),
                                    color: severityColor(issue.severity))
                    } else {
                        statusBadge("PASS", color: .green)
                    }
                }

                Text(check.issue?.description ?? check.passedNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func statusBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color, lineWidth: 1)
            )
    }

    // MARK: - Helpers

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 75...100: return .green
        case 50..<75:  return .orange
        default:       return .red
        }
    }

    private func severityColor(_ severity: PostureIssue.Severity) -> Color {
        switch severity {
        case .mild:     return .yellow
        case .moderate: return .orange
        case .severe:   return .red
        }
    }
}
