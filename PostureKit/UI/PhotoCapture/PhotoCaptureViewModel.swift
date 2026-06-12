import Foundation
import SwiftUI
import Combine

// MARK: - Supporting types

// The three angles the user photographs. rawValue matches the step index (0, 1, 2)
// so we can do CaptureAngle(rawValue: currentAngle.rawValue + 1) to advance.
enum CaptureAngle: Int, CaseIterable {
    case front, side, back

    var title: String {
        switch self {
        case .front: return "Front View"
        case .side:  return "Side View"
        case .back:  return "Back View"
        }
    }

    // Shown in the capture card below the camera preview.
    var instruction: String {
        switch self {
        case .front: return "Face the camera with feet shoulder-width apart, arms relaxed at your sides."
        case .side:  return "Turn so your left side faces the camera. Stand naturally — don't pose."
        case .back:  return "Turn so your back faces the camera. Feet shoulder-width apart, arms relaxed."
        }
    }

    var icon: String {
        switch self {
        case .front: return "person.fill"
        case .side:  return "person.crop.rectangle"
        case .back:  return "figure.stand"
        }
    }

    // Convenience — nil signals "no next step" (back was the last).
    var next: CaptureAngle? { CaptureAngle(rawValue: rawValue + 1) }
}

// Analysis result for a single angle.
// Identifiable so ForEach can use it directly in results view.
struct AngleResult: Identifiable {
    let id = UUID()
    let angle: CaptureAngle
    let image: UIImage
    let pose: BodyPose          // stored so the analysis screen can draw the skeleton
    let issues: [PostureIssue]
    let score: Int
    let cvaAngle: Double?       // nil for front/back — CVA is only measured from side view
    let mlPrediction: MLPrediction?  // classifier opinion — nil if the model failed to load (FR-21)
}

// The four states the wizard moves through.
// Equatable so SwiftUI animations can diff between them.
enum WizardPhase: Equatable {
    case capturing    // camera preview + capture button shown
    case confirming   // captured photo shown — user can confirm or retake
    case analyzing    // Vision is running on the confirmed photo
    case done         // all 3 angles complete — show results
}

// MARK: - ViewModel

// PhotoCaptureViewModel is the single source of truth for the guided photo capture flow.
//
// Wizard state machine:
//   capturing → [tap capture] → confirming → [tap confirm] → analyzing → capturing (next angle)
//                                          → [tap retake]  → capturing (same angle)
//   After back angle confirms → done
//
// Why @MainActor:
// All @Published mutations must happen on the main thread or SwiftUI drops the update.
// Marking the whole class @MainActor is simpler and safer than sprinkling
// DispatchQueue.main.async throughout — Swift enforces it at compile time.
@MainActor
class PhotoCaptureViewModel: ObservableObject {

    // MARK: - State

    @Published var phase: WizardPhase = .capturing
    @Published var currentAngle: CaptureAngle = .front
    @Published var capturedImage: UIImage?
    @Published var results: [AngleResult] = []
    // Counts down from 5 to 1 before firing the shutter. 0 = not active.
    @Published var countdown: Int = 0

    // MARK: - Dependencies

    // Owned here so the preview layer (CameraPreviewView) has a stable session reference
    // for the full lifetime of the wizard.
    let captureManager = PhotoCaptureManager()

    // PoseDetector is reused across all three captures — it caches internal Vision state
    // that makes subsequent calls faster. Do not create a new one per capture.
    private let poseDetector = PoseDetector()
    private let analyzer = PostureAnalyzer()
    // ML classifier runs alongside the rule-based analyzer (FR-21).
    // Reused so the compiled model is only loaded once.
    private let mlBridge = PostureMLBridge()

    // MARK: - Computed results

    // Average score across all completed angles.
    var overallScore: Int {
        guard !results.isEmpty else { return 0 }
        return results.map(\.score).reduce(0, +) / results.count
    }

    // Deduplicated issue list across all angles.
    // When the same issue appears in multiple angles (e.g. FHP in both front and side),
    // we keep only the worst severity — showing duplicates would confuse the user.
    var allIssues: [PostureIssue] {
        var best: [PostureIssue] = []
        for issue in results.flatMap(\.issues) {
            if let idx = best.firstIndex(where: { $0.type == issue.type }) {
                if issue.severityScore > best[idx].severityScore {
                    best[idx] = issue
                }
            } else {
                best.append(issue)
            }
        }
        return best
    }

    // MARK: - Actions

    // User taps the shutter button.
    // Counts down 5→1, then fires AVCapturePhotoOutput.
    // The countdown gives the user time to step back and get into position
    // without needing a second person to tap the button for them.
    func capture() {
        guard phase == .capturing, countdown == 0 else { return }
        Task {
            for i in stride(from: 5, through: 1, by: -1) {
                countdown = i
                try? await Task.sleep(for: .seconds(1))
            }
            countdown = 0
            phase = .analyzing
            guard let image = await captureManager.capturePhoto() else {
                phase = .capturing
                return
            }
            capturedImage = image
            phase = .confirming
        }
    }

    // User taps "Looks good" on the confirmation screen.
    // Runs Vision pose detection on the confirmed photo, stores the result,
    // then advances to the next angle (or done if back was last).
    func confirmPhoto() {
        guard let image = capturedImage, phase == .confirming else { return }
        phase = .analyzing

        Task {
            // Vision inference on a still image runs synchronously (~100–300ms).
            // We push it to a high-priority background task so the main thread
            // (and therefore the UI) stays responsive during analysis.
            let pose = await Task.detached(priority: .userInitiated) { [weak self] in
                await self?.poseDetector.detect(in: image) ?? .empty
            }.value

            // analyzeOnce is single-shot (no rolling-window smoothing).
            // Smoothing is only meaningful for continuous video — one frame would just
            // return the raw score with no history to average, which is what we want here.
            let (issues, score, cvaAngle) = analyzer.analyzeOnce(pose, for: currentAngle)

            // ML classifier opinion (FR-21). Runs in parallel with the rule-based
            // checks above — neither affects the other. A tabular classifier
            // prediction is sub-millisecond, so no need to push it off-main.
            // nil = model unavailable; the UI just omits the ML row.
            let mlPrediction = mlBridge.predict(pose: pose, angle: currentAngle)

            results.append(AngleResult(
                angle: currentAngle,
                image: image,
                pose: pose,
                issues: issues,
                score: score,
                cvaAngle: cvaAngle,
                mlPrediction: mlPrediction
            ))

            capturedImage = nil

            if let next = currentAngle.next {
                currentAngle = next
                phase = .capturing
            } else {
                phase = .done
            }
        }
    }

    // User taps "Retake" — discard the preview photo and try again.
    func retake() {
        capturedImage = nil
        phase = .capturing
    }

    // Start a brand new assessment from the beginning.
    func restart() {
        results = []
        currentAngle = .front
        capturedImage = nil
        phase = .capturing
    }
}
