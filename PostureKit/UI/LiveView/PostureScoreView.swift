import SwiftUI

// PostureScoreView — animated ring showing the posture score 0–100.
//
// Why a ring instead of just a number:
// The ring gives instant colour-coded feedback without the user needing
// to read and interpret a number. Green ring = good, red ring = bad — readable
// at a glance while focused on standing correctly in front of the camera.
//
// The trim animation (.easeInOut 0.3s) makes the ring feel alive —
// it responds smoothly to posture changes rather than jumping.

struct PostureScoreView: View {

    let score: Int

    // Colour bands match physiotherapist convention:
    // green = good, orange = needs attention, red = significant issues.
    var scoreColor: Color {
        switch score {
        case 75...100: return .green
        case 50..<75:  return .orange
        default:       return .red
        }
    }

    var body: some View {
        ZStack {
            // Background ring — always full circle, low opacity grey track.
            Circle()
                .stroke(Color.gray.opacity(0.25), lineWidth: 10)

            // Foreground ring — fills from 0 to score/100 clockwise from 12 o'clock.
            // .trim(from:to:) takes 0–1, so divide score by 100.
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(
                    scoreColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                // Without rotation, trim starts at 3 o'clock (default CGPath origin).
                // -90° rotates the start point to 12 o'clock — standard progress ring behaviour.
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: score)

            // Score label centred in the ring.
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: score)

                Text("/ 100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 120, height: 120)
    }
}
