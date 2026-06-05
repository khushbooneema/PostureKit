import SwiftUI
import Combine

// FPSCounterView — debug overlay showing live frames per second.
// Visible only in DEBUG builds. Automatically hidden in Release (App Store) builds.
//
// Uses CADisplayLink which fires every screen refresh — the most accurate
// FPS measurement available on iOS, same source Instruments Core Animation uses.
//
// Remove from the view hierarchy before shipping Layer 5.

#if DEBUG

struct FPSCounterView: View {

    @StateObject private var counter = FPSCounter()

    var body: some View {
        Text("FPS: \(counter.fps)")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// Drives the FPS measurement using CADisplayLink.
// CADisplayLink fires once per display refresh — we count how many
// fires happen per second to get the true rendered frame rate.
private class FPSCounter: ObservableObject {

    @Published var fps: Int = 0

    private var displayLink: CADisplayLink?
    private var frameCount: Int = 0
    private var lastTimestamp: CFTimeInterval = 0

    init() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    deinit {
        displayLink?.invalidate()
    }

    @objc private func tick(link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }

        frameCount += 1
        let elapsed = link.timestamp - lastTimestamp

        // Update FPS reading once per second to keep the number readable.
        if elapsed >= 1.0 {
            fps = Int(round(Double(frameCount) / elapsed))
            frameCount = 0
            lastTimestamp = link.timestamp
        }
    }
}

#endif
