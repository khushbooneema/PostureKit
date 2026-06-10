import SwiftUI

// PostureWizardView is the root view of the photo-based assessment flow.
//
// It owns a single PhotoCaptureViewModel for the full lifetime of the wizard
// and swaps child views as the wizard phase changes:
//
//   CaptureStepView    ← phase: .capturing / .analyzing
//   PhotoConfirmView   ← phase: .confirming
//   PhotoAnalysisView  ← phase: .done
//
// Session lifecycle lives here (not in child views) so the AVCaptureSession
// keeps running across the capturing → confirming → capturing transitions.
// If it were owned by CaptureStepView, the session would restart on every retake.

struct PostureWizardView: View {

    @StateObject private var viewModel = PhotoCaptureViewModel()

    var body: some View {
        currentPhaseView
            .onAppear  { viewModel.captureManager.startSession() }
            .onDisappear { viewModel.captureManager.stopSession() }
            .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
    }

    // @ViewBuilder so we can use switch/if-let without returning AnyView.
    @ViewBuilder
    private var currentPhaseView: some View {
        switch viewModel.phase {

        case .capturing, .analyzing:
            CaptureStepView(viewModel: viewModel)

        case .confirming:
            if let image = viewModel.capturedImage {
                PhotoConfirmView(image: image, viewModel: viewModel)
            } else {
                // Transient — confirming always has an image; this branch shouldn't appear.
                CaptureStepView(viewModel: viewModel)
            }

        case .done:
            PhotoAnalysisView(viewModel: viewModel)
        }
    }
}
