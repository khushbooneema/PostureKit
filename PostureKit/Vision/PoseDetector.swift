import Vision
import AVFoundation
import UIKit

// PoseDetector is the only type in the app that runs Vision inference.
// It takes either a live camera frame (CMSampleBuffer) or a still photo (UIImage)
// and returns a clean BodyPose.
//
// Threading: both detect(in:) overloads block the calling thread for ~10–300ms.
// The CMSampleBuffer path is called from CameraManager's background processingQueue.
// The UIImage path is called from a detached Task in PhotoCaptureViewModel.
// Neither path may be called on the main thread.

class PoseDetector {

    // The request is created once and reused across every call.
    // VNDetectHumanBodyPoseRequest caches internal state that makes subsequent
    // calls faster. Do not recreate it per frame or per photo.
    private let request = VNDetectHumanBodyPoseRequest()

    // MARK: - Live video path (CameraManager)

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

    // MARK: - Still photo path (PhotoCaptureManager)

    // Takes a UIImage captured by AVCapturePhotoOutput and returns a BodyPose.
    // UIImage carries an imageOrientation property that describes the transform needed
    // to display it upright. cgImage holds the raw pixel data without that transform applied,
    // so we must translate the UIImage orientation into a CGImagePropertyOrientation and
    // pass it to Vision — otherwise keypoint coordinates are rotated/mirrored incorrectly.
    func detect(in image: UIImage) -> BodyPose? {
        guard let cgImage = image.cgImage else { return nil }

        let orientation = cgImageOrientation(from: image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        try? handler.perform([request])

        guard let observation = request.results?.first else { return nil }
        return BodyPose(from: observation)
    }

    // Translates UIImage.Orientation into the equivalent CGImagePropertyOrientation.
    // These two enums cover the same 8 orientations but use different raw value schemes
    // — there is no built-in conversion, so we map them explicitly.
    private func cgImageOrientation(from uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}
