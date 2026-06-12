import Foundation
import SwiftUI
import Combine

// DataCollectionViewModel orchestrates the hidden data-collection flow (FR-19).
//
// Recording lifecycle (one tap of the Record button):
//   1. Fire AVCapturePhotoOutput via captureManager — gets a UIImage
//   2. Run Vision pose detection on the still (same PoseDetector used by the wizard)
//   3. Convert BodyPose → flat keypoint dict (all 18 joints, missing = -1.0 sentinel)
//   4. Append to PoseSampleStore with the chosen label + angle
//
// Session ownership:
//   The VM owns its own PhotoCaptureManager so the session lifecycle is fully
//   contained here. PostureWizardView stops the wizard session before presenting
//   the collection sheet and restarts it on dismiss — the two sessions never run
//   on the same camera simultaneously.

@MainActor
class DataCollectionViewModel: ObservableObject {

    // MARK: - UI state

    @Published var selectedLabel: PostureLabel = .normal
    @Published var selectedAngle: CaptureAngle = .front
    @Published var isCapturing: Bool = false
    @Published var statusMessage: String = ""

    // MARK: - Dependencies

    let captureManager = PhotoCaptureManager()
    let store = PoseSampleStore.shared

    private let poseDetector = PoseDetector()

    // MARK: - Session lifecycle

    func startSession() { captureManager.startSession() }
    func stopSession()  { captureManager.stopSession() }

    // MARK: - Recording (FR-19)

    func record() {
        guard !isCapturing else { return }
        isCapturing = true
        statusMessage = "Capturing…"

        Task {
            // 1. Still photo from AVFoundation
            guard let image = await captureManager.capturePhoto() else {
                statusMessage = "Capture failed — check camera permissions"
                isCapturing = false
                return
            }

            // 2. Vision inference on background thread (~100–300 ms)
            let pose = await Task.detached(priority: .userInitiated) { [weak self] in
                await self?.poseDetector.detect(in: image) ?? .empty
            }.value

            // 3. Convert BodyPose → flat keypoint dict
            let keypoints = makeKeypointDict(from: pose)

            // 4. Persist to store
            let angleStr: String
            switch selectedAngle {
            case .front: angleStr = "front"
            case .side:  angleStr = "side"
            case .back:  angleStr = "back"
            }

            store.record(keypoints: keypoints,
                         label: selectedLabel.rawValue,
                         captureAngle: angleStr)

            statusMessage = "Recorded ✓  (\(store.samples.count) total)"
            isCapturing = false
        }
    }

    // MARK: - BodyPose → keypoint dictionary

    // Converts all 18 Vision joints to the flat dict PoseSampleStore writes to disk.
    // Joints not detected by Vision → PoseSample.KeypointData.missing (x: -1, y: -1).
    // Using -1 rather than 0 distinguishes "not detected" from "at the frame edge".
    private func makeKeypointDict(from pose: BodyPose) -> [String: PoseSample.KeypointData] {
        func kp(_ joint: BodyPose.Joint?) -> PoseSample.KeypointData {
            guard let j = joint else { return .missing }
            return PoseSample.KeypointData(
                x: Float(j.position.x),
                y: Float(j.position.y),
                confidence: j.confidence
            )
        }
        return [
            "nose":          kp(pose.nose),
            "neck":          kp(pose.neck),
            "leftEye":       kp(pose.leftEye),
            "rightEye":      kp(pose.rightEye),
            "leftEar":       kp(pose.leftEar),
            "rightEar":      kp(pose.rightEar),
            "leftShoulder":  kp(pose.leftShoulder),
            "rightShoulder": kp(pose.rightShoulder),
            "leftElbow":     kp(pose.leftElbow),
            "rightElbow":    kp(pose.rightElbow),
            "leftWrist":     kp(pose.leftWrist),
            "rightWrist":    kp(pose.rightWrist),
            "leftHip":       kp(pose.leftHip),
            "rightHip":      kp(pose.rightHip),
            "leftKnee":      kp(pose.leftKnee),
            "rightKnee":     kp(pose.rightKnee),
            "leftAnkle":     kp(pose.leftAnkle),
            "rightAnkle":    kp(pose.rightAnkle),
        ]
    }
}
