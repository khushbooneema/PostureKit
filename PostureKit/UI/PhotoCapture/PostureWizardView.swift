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
//
// Data-collection sheet:
//   A 2-second long press on the step indicator in CaptureStepView sets
//   showDataCollection = true. This view stops the wizard session so the
//   collection view can start its own session on the same camera.
//   On dismiss, the wizard session restarts via the sheet's onDismiss callback.

struct PostureWizardView: View {

    @StateObject private var viewModel = PhotoCaptureViewModel()
    @State private var showDataCollection = false

    var body: some View {
        currentPhaseView
            .onAppear  { viewModel.captureManager.startSession() }
            .onDisappear { viewModel.captureManager.stopSession() }
            .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
            // Stop wizard session before the collection sheet starts its own.
            // Restart it once the sheet is fully dismissed and its session is stopped.
            .sheet(isPresented: $showDataCollection, onDismiss: {
                viewModel.captureManager.startSession()
            }) {
                DataCollectionView()
            }
            .onChange(of: showDataCollection) { _, isShowing in
                if isShowing { viewModel.captureManager.stopSession() }
            }
    }

    // @ViewBuilder so we can use switch/if-let without returning AnyView.
    @ViewBuilder
    private var currentPhaseView: some View {
        switch viewModel.phase {

        case .capturing, .analyzing:
            CaptureStepView(viewModel: viewModel, showDataCollection: $showDataCollection)

        case .confirming:
            if let image = viewModel.capturedImage {
                PhotoConfirmView(image: image, viewModel: viewModel)
            } else {
                // Transient — confirming always has an image; this branch shouldn't appear.
                CaptureStepView(viewModel: viewModel, showDataCollection: $showDataCollection)
            }

        case .done:
            PhotoAnalysisView(viewModel: viewModel)
        }
    }
}
