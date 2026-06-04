import AVFoundation
import Combine

// CameraManager owns the entire AVCaptureSession lifecycle.
// It is the entry point of the data pipeline:
// AVCaptureSession → PoseDetector → PoseSmoother → @Published currentPose → SwiftUI
//
// Threading model:
// - setupSession() and startSession() are called from init (main thread)
// - captureOutput runs on processingQueue (background serial queue)
// - All @Published properties are updated on the main thread via DispatchQueue.main.async

class CameraManager: NSObject, ObservableObject {

    public let captureSession = AVCaptureSession()

    // Published so SwiftUI views automatically re-render when a new pose arrives.
    // Initialised to .empty so views have a valid (non-optional) pose before the first frame.
    @Published var currentPose: BodyPose = .empty

    // Average confidence across all detected joints in the current pose.
    // Used by the UI to show a low-light warning when Vision is struggling.
    // 0.0 = no joints detected, 1.0 = all joints detected at maximum confidence.
    @Published var averageConfidence: Float = 0

    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "pose.processing", qos: .userInitiated)

    // PoseDetector is owned here because CameraManager feeds it frames.
    // It lives for the duration of the session — not recreated per frame.
    private let poseDetector = PoseDetector()

    // PoseSmoother maintains the rolling window across frames.
    // Owned here alongside poseDetector — both are part of the same pipeline stage.
    private let smoother = PoseSmoother()

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Front camera not available")
            return
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            print("Could not create camera input")
            return
        }

        guard captureSession.canAddInput(input) else {
            print("Cannot add camera input to session")
            return
        }

        captureSession.addInput(input)
        print("Camera input added")

        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)

        guard captureSession.canAddOutput(videoOutput) else {
            print("Cannot add video output to session")
            return
        }

        captureSession.addOutput(videoOutput)
        startSession()
    }

    public func startSession() {
        Task.detached { [weak self] in
            await self?.captureSession.startRunning()
        }
    }

    public func stopSession() {
        captureSession.stopRunning()
    }

    // Calculates the mean confidence of all non-nil joints in a pose.
    // Returns 0 if no joints are detected.
    private func calculateAverageConfidence(for pose: BodyPose) -> Float {
        let allJoints: [BodyPose.Joint?] = [
            pose.leftEye, pose.rightEye,
            pose.nose, pose.leftEar, pose.rightEar, pose.neck,
            pose.leftShoulder, pose.rightShoulder,
            pose.leftElbow, pose.rightElbow,
            pose.leftWrist, pose.rightWrist,
            pose.leftHip, pose.rightHip,
            pose.leftKnee, pose.rightKnee,
            pose.leftAnkle, pose.rightAnkle
        ]
        let confidences = allJoints.compactMap { $0?.confidence }
        guard !confidences.isEmpty else { return 0 }
        return confidences.reduce(0, +) / Float(confidences.count)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    // Called by AVFoundation on processingQueue for every incoming camera frame.
    // This is where the Vision pipeline begins.
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        if let pose = poseDetector.detect(in: sampleBuffer) {
            let smoothed = smoother.smooth(pose)
            let confidence = calculateAverageConfidence(for: smoothed)

            // Both published properties updated in a single main-thread dispatch
            // so SwiftUI always sees them in sync — no frame where pose is updated
            // but confidence hasn't caught up yet.
            DispatchQueue.main.async { [weak self] in
                self?.currentPose = smoothed
                self?.averageConfidence = confidence
            }
        } else {
            smoother.reset()
            DispatchQueue.main.async { [weak self] in
                self?.currentPose = .empty
                self?.averageConfidence = 0
            }
        }
    }
}
