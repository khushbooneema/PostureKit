import SwiftUI

// CaptureStepView shows the live camera preview with a capture button.
// Shown for all three angles — CaptureAngle in the viewModel drives the
// instruction text and step indicator.
//
// Layout (bottom to top):
//   Full-screen camera preview
//   Step progress dots (top centre)
//   Capture card (bottom): angle icon + title + instruction + shutter button

struct CaptureStepView: View {

    @ObservedObject var viewModel: PhotoCaptureViewModel

    var body: some View {
        ZStack {
            // Full-screen camera preview.
            // Reuses CameraPreviewView from the live analysis feature —
            // it takes any AVCaptureSession, so it works here too.
            CameraPreviewView(session: viewModel.captureManager.captureSession)
                .ignoresSafeArea()

            VStack {
                stepIndicator
                    .padding(.top, 60)

                Spacer()

                captureCard
            }
        }
        // Countdown overlay — large number shown while the timer runs down.
        .overlay {
            if viewModel.countdown > 0 {
                countdownOverlay
            }
        }
        // Spinner overlay — shown while AVFoundation is processing the photo
        // (the .analyzing phase that immediately follows the countdown finishing).
        .overlay {
            if viewModel.phase == .analyzing {
                processingOverlay
            }
        }
    }

    // MARK: - Subviews

    // Three dots — filled/checkmarked for completed steps, white for current, faded for upcoming.
    private var stepIndicator: some View {
        HStack(spacing: 10) {
            ForEach(CaptureAngle.allCases, id: \.rawValue) { angle in
                let isCurrent  = angle == viewModel.currentAngle
                let isComplete = angle.rawValue < viewModel.currentAngle.rawValue

                ZStack {
                    Circle()
                        .fill(isComplete ? Color.green : (isCurrent ? Color.white : Color.white.opacity(0.3)))
                        .frame(width: 12, height: 12)

                    // Show a tick inside completed dots so it's clear they're done,
                    // not just highlighted.
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }

    // Bottom card with step info and the shutter button.
    private var captureCard: some View {
        VStack(spacing: 16) {

            // Angle label
            HStack(spacing: 8) {
                Image(systemName: viewModel.currentAngle.icon)
                    .font(.title3)
                Text(viewModel.currentAngle.title)
                    .font(.headline)
            }
            .foregroundStyle(.primary)

            // Plain-English instruction for how to position.
            Text(viewModel.currentAngle.instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Shutter button — classic iOS camera style: outer ring + filled circle.
            // Disabled while analyzing to prevent double-firing.
            Button {
                viewModel.capture()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 3)
                        .frame(width: 84, height: 84)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                }
            }
            .disabled(viewModel.phase == .analyzing || viewModel.countdown > 0)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .padding(.horizontal, 20)
        .padding(.bottom, 44)
    }

    // Large countdown number centred over the camera feed.
    // The number animates in/out each second so it feels responsive.
    private var countdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            Text("\(viewModel.countdown)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 10)
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeInOut(duration: 0.4), value: viewModel.countdown)
        }
    }

    // Full-screen dimmed overlay with a spinner while the photo is being captured.
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)
                Text("Capturing…")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
        }
    }
}
