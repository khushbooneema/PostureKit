import Foundation
import Combine
import AVFoundation

// LiveViewModel — connects CameraManager and PostureAnalyzer to the UI.
//
// MVVM role:
//   Model:     CameraManager (camera data) + PostureAnalyzer (analysis results)
//   ViewModel: LiveViewModel (this file — owns both, exposes what the view needs)
//   View:      LiveAnalysisView (reads from this ViewModel only)
//
// Why LiveViewModel owns both CameraManager and PostureAnalyzer:
// The view should have one single object to talk to — not two separate managers
// with separate lifecycles. LiveViewModel owns both and is responsible for
// connecting them. The view is completely unaware that two separate objects exist.
//
// Combine pipeline:
// camera.$currentPose → analyze() → analyzer.@Published → objectWillChange → SwiftUI re-render
//
// Threading:
// camera.$currentPose publishes on main thread (CameraManager dispatches to main).
// The sink fires on main — analyzer.analyze() runs on main.
// All @Published updates stay on main throughout.

class LiveViewModel: ObservableObject {

    // MARK: - Owned objects

    private let camera   = CameraManager()
    private let analyzer = PostureAnalyzer()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // Forward child objectWillChange notifications to trigger SwiftUI re-renders.
        //
        // Why this is needed:
        // LiveAnalysisView observes LiveViewModel via @StateObject. SwiftUI re-renders
        // when LiveViewModel fires objectWillChange. But changes happen inside camera
        // and analyzer — child objects whose changes don't automatically propagate up.
        // Subscribing to their objectWillChange and re-sending it on LiveViewModel
        // closes the loop: child change → parent notifies → SwiftUI re-renders.
        camera.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        analyzer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Connect camera frames to the analyzer.
        // Every new pose published by CameraManager is fed into PostureAnalyzer.
        // [weak self] prevents a retain cycle: LiveViewModel → camera → sink → LiveViewModel.
        camera.$currentPose
            .sink { [weak self] pose in
                self?.analyzer.analyze(pose)
            }
            .store(in: &cancellables)
    }

    // MARK: - Camera passthrough

    // The view reads these to display the camera feed and skeleton overlay.
    var captureSession: AVCaptureSession { camera.captureSession }
    var currentPose: BodyPose            { camera.currentPose }
    var averageConfidence: Float         { camera.averageConfidence }

    // MARK: - Analyzer passthrough

    // The view reads these to display the score ring and issue list.
    var score: Int                  { analyzer.postureScore }
    var issues: [PostureIssue]      { analyzer.currentIssues }
}
