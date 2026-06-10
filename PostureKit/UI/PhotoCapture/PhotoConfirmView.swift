import SwiftUI

// PhotoConfirmView shows the just-captured photo full-screen so the user
// can judge whether their full body is visible before analysis runs.
//
// Why this step exists:
// Vision needs to see both shoulders and both hips to produce a valid pose.
// If the user is too close or at a bad angle, detection will fail silently
// (isValid = false → score 100 with no issues). Showing the photo first
// lets them catch that before committing.
//
// Two outcomes:
//   "Looks good" → confirmPhoto() → Vision runs → advance to next angle
//   "Retake"     → retake()       → back to CaptureStepView for same angle

struct PhotoConfirmView: View {

    let image: UIImage
    @ObservedObject var viewModel: PhotoCaptureViewModel

    var body: some View {
        ZStack(alignment: .bottom) {

            // Full-screen photo preview.
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            // Subtle gradient so the bottom card text is readable over any background.
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.5)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Confirm / retake card
            VStack(spacing: 16) {
                Text(viewModel.currentAngle.title)
                    .font(.headline)

                Text("Is your full body visible from head to feet?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 14) {
                    Button("Retake") {
                        viewModel.retake()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("Looks good") {
                        viewModel.confirmPhoto()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding(.horizontal, 20)
            .padding(.bottom, 44)
        }
        // Analyzing overlay — replaces the confirm card while Vision runs.
        .overlay {
            if viewModel.phase == .analyzing {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.4)
                            .tint(.white)
                        Text("Analysing posture…")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}
