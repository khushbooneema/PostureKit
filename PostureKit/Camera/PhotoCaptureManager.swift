import AVFoundation
import Combine
import UIKit

// PhotoCaptureManager owns an AVCaptureSession configured for still photos.
//
// Unlike CameraManager (which runs Vision on every video frame for live analysis),
// this class only captures a single high-res photo when the user taps the button.
// Vision runs once on that photo, not continuously — so no PoseDetector or smoother here.
//
// AVCapturePhotoOutput vs AVCaptureVideoDataOutput:
// VideoDataOutput gives us a stream of CMSampleBuffers (video frames) — used in CameraManager.
// PhotoOutput gives us a single full-resolution JPEG when capturePhoto() is called — used here.
// We can't use both outputs at maximum quality simultaneously, but photo preset handles this.
//
// Threading:
// capturePhoto() is async — the caller awaits a UIImage result.
// AVCapturePhotoCaptureDelegate callback fires on an internal AVFoundation thread.
// We bridge that callback to Swift async/await using CheckedContinuation.

class PhotoCaptureManager: NSObject, ObservableObject {

    // Exposed so CameraPreviewView (a UIViewRepresentable) can attach its preview layer.
    let captureSession = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()

    // Holds the continuation between capturePhoto() and the delegate callback.
    // There can only be one in-flight photo capture at a time.
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    override init() {
        super.init()
        setupSession()
    }

    // MARK: - Session lifecycle

    private func setupSession() {
        // .photo preset gives the highest resolution the device supports.
        // It optimises the pipeline for still capture rather than low-latency video.
        captureSession.sessionPreset = .photo

        // Use the front camera — the user sees their mirror image in the preview,
        // which makes it easier to position themselves without a second person.
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else { return }

        captureSession.addInput(input)

        guard captureSession.canAddOutput(photoOutput) else { return }
        captureSession.addOutput(photoOutput)
    }

    func startSession() {
        // startRunning() blocks until the session is ready — must run off the main thread.
        // Task.detached ensures this never runs on the main actor even if the caller is @MainActor.
        Task.detached { [weak self] in
            await self?.captureSession.startRunning()
        }
    }

    func stopSession() {
        captureSession.stopRunning()
    }

    // MARK: - Photo capture

    // Captures a single photo and returns it as a UIImage.
    // Returns nil if the session isn't running or AVFoundation returns an error.
    //
    // CheckedContinuation bridges the callback-based AVFoundation delegate pattern
    // to async/await. The continuation is stored as an instance var because the
    // delegate callback fires later on a different thread.
    func capturePhoto() async -> UIImage? {
        return await withCheckedContinuation { continuation in
            photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension PhotoCaptureManager: AVCapturePhotoCaptureDelegate {

    // Called by AVFoundation when the photo has finished processing.
    // Fires on an internal AVFoundation background thread — the continuation
    // re-delivers the result to whatever context awaited capturePhoto().
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {

        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else {
            photoContinuation?.resume(returning: nil)
            photoContinuation = nil
            return
        }

        photoContinuation?.resume(returning: image)
        photoContinuation = nil
    }
}
