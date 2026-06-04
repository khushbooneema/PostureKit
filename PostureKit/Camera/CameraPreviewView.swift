import AVFoundation
import SwiftUI

// CameraPreviewView bridges AVCaptureVideoPreviewLayer into SwiftUI.
//
// Why UIViewRepresentable: AVCaptureVideoPreviewLayer is a CALayer, not a UIView or SwiftUI View.
// It must be wrapped in a UIView to participate in the SwiftUI view hierarchy.
//
// Why a custom UIView subclass (PreviewLayerView):
// updateUIView() fires when SwiftUI state changes, not on layout events.
// On first render, uiView.bounds is still CGRect.zero when updateUIView runs,
// so setting the frame there produces a black screen.
// Overriding layoutSubviews() in the UIView subclass fires on every layout pass —
// initial render, rotation, split-screen resize — and always has the correct bounds.

struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        view.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {
        // Frame is kept in sync by PreviewLayerView.layoutSubviews().
        // Nothing to do here — layout changes are handled at the UIKit level.
    }
}

// UIView subclass that owns the preview layer and keeps its frame correct.
// layoutSubviews() is the reliable hook for frame updates — it fires on
// initial layout, rotation, and any bounds change.
class PreviewLayerView: UIView {

    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
