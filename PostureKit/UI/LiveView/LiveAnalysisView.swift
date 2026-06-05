import SwiftUI

// LiveAnalysisView is the root screen of the app.
// It reads exclusively from LiveViewModel — unaware that CameraManager
// and PostureAnalyzer exist as separate objects underneath.
//
// ZStack layers (bottom to top):
//   1. CameraPreviewView   — live camera feed
//   2. SkeletonOverlayView — skeleton drawn over the feed
//   3. Warning banner + FPS counter — user guidance and debug info

struct LiveAnalysisView: View {

    @StateObject private var viewModel = LiveViewModel()

    var body: some View {
        ZStack {
            // Layer 1: live camera feed
            CameraPreviewView(session: viewModel.captureSession)
                .ignoresSafeArea()

            // Layer 2: skeleton overlay
            SkeletonOverlayView(pose: viewModel.currentPose)
                .ignoresSafeArea()

            // Layer 3: warnings + debug counter
            VStack {
                HStack(alignment: .top) {
                    if let message = warningMessage {
                        Text(message)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                    }
                    Spacer()
                    #if DEBUG
                    FPSCounterView()
                    #endif
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                Spacer()
            }
        }
    }

    // MARK: - Warning logic

    private var warningMessage: String? {
        guard viewModel.currentPose.isValid else {
            return "Step back so your full body is visible"
        }
        if viewModel.averageConfidence < 0.4 {
            return "Move to better lighting"
        }
        return nil
    }
}
