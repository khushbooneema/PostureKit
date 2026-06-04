import SwiftUI

// LiveAnalysisView is the root screen of the app.
// It composites three layers in a ZStack:
//   1. CameraPreviewView     — live camera feed (bottom)
//   2. SkeletonOverlayView   — skeleton drawn over the feed
//   3. Warning banner        — user guidance when detection quality is poor (top)
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
            // No .scaleEffect needed — mirror is handled in PoseDetector via .leftMirrored orientation.
            SkeletonOverlayView(pose: camera.currentPose)
                .ignoresSafeArea()

            // Layer 3: warning banner
            // Pinned to the top of the screen.
            // Only visible when detection quality is too poor for reliable posture analysis.
            VStack {
                if let message = warningMessage {
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .padding(.top, 16)
                }
                Spacer()
            }
        }
    }

    // MARK: - Warning Logic

    // Returns a user-facing message when conditions are too poor for accurate detection.
    // Priority: pose validity (person not in frame) > confidence (poor lighting).
    // Returns nil when everything is fine — no banner shown.
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
