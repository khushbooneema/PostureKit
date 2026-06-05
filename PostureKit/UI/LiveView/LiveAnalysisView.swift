import SwiftUI

// LiveAnalysisView is the root screen of the app.
// It composites three layers in a ZStack:
//   1. CameraPreviewView     — live camera feed (bottom)
//   2. SkeletonOverlayView   — skeleton drawn over the feed
//   3. Warning banner + FPS counter — user guidance and debug info
//
// CameraManager is the single source of truth — it owns the session,
// publishes currentPose and averageConfidence. All layers read from the same instance.

struct LiveAnalysisView: View {

    @StateObject private var camera = CameraManager()

    var body: some View {
        ZStack {
            // Layer 1: live camera feed
            CameraPreviewView(session: camera.captureSession)
                .ignoresSafeArea()

            // Layer 2: skeleton overlay
            SkeletonOverlayView(pose: camera.currentPose)
                .ignoresSafeArea()

            // Layer 3: warnings + debug FPS counter
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

    // MARK: - Warning Logic

    private var warningMessage: String? {
        guard camera.currentPose.isValid else {
            return "Step back so your full body is visible"
        }
        if camera.averageConfidence < 0.4 {
            return "Move to better lighting"
        }
        return nil
    }
}
