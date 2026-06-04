import Vision
import AVFoundation

// PoseDetector is the only type in the app that runs Vision inference.
// It takes a raw camera frame (CMSampleBuffer) and returns a clean BodyPose.
//
// Threading: detect(in:) is called from CameraManager's processingQueue (background thread).
// It must never be called on the main thread — Vision inference blocks for ~10–30ms per frame.

class PoseDetector {

    // The request is created once and reused across every frame.
    // VNDetectHumanBodyPoseRequest is designed for reuse — it caches internal state
    // that makes subsequent calls faster. Do not recreate it per frame.
    private let request = VNDetectHumanBodyPoseRequest()

    // Takes a single camera frame and returns a BodyPose if a person is detected.
    // Returns nil if no person is in frame, if the pixel buffer is unavailable,
    // or if Vision fails — all treated as "no pose this frame", not errors.
    func detect(in sampleBuffer: CMSampleBuffer) -> BodyPose? {

        // CMSampleBuffer wraps the raw frame. CVPixelBuffer is the actual image data Vision needs.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        // VNImageRequestHandler is tied to a single image — create it fresh every frame.
        // Reusing it across frames would analyse the wrong image.
        //
        // Orientation .leftMirrored — not .up:
        // The front camera buffer in portrait mode is a landscape image rotated 90° CCW.
        // .leftMirrored tells Vision to rotate 90° CW AND mirror horizontally,
        // which matches how the front camera preview is displayed (selfie/mirror view).
        // Using .up causes the X and Y axes to be swapped — moving UP appears as moving RIGHT.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)

        // perform() is synchronous — it blocks until inference is complete.
        // try? means any Vision error (unsupported hardware, bad input) returns nil gracefully.
        try? handler.perform([request])

        // results holds all detected people. We take the first (highest confidence) only.
        // Multi-person support is explicitly out of scope for V1.
        guard let observation = request.results?.first else { return nil }

        return BodyPose(from: observation)
    }
}
