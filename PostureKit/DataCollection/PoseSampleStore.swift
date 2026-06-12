import Foundation
import Combine

// PoseSampleStore manages the accumulation, persistence, and export of labelled
// pose samples for CoreML training (FR-19, FR-20).
//
// Singleton: the store outlives any individual view so samples survive the
// collection sheet being dismissed and re-opened mid-session.
//
// Persistence:
//   Documents/pose_samples.json — grows on every record() call.
//   Survives app restarts so you can collect across multiple sessions.
//
// Export (FR-20):
//   Documents/createml_export_<timestamp>.json
//   Flat row-per-sample format ready for CreateML's Tabular Classifier:
//     { "label": "forward_head", "capture_angle": "side",
//       "leftEar_x": 0.48, "leftEar_y": 0.82, "leftEar_confidence": 0.97, … }

final class PoseSampleStore: ObservableObject {

    static let shared = PoseSampleStore()

    @Published private(set) var samples: [PoseSample] = []

    private init() { load() }

    // MARK: - Recording

    // Appends a new sample and persists immediately.
    // The caller (DataCollectionViewModel) handles the BodyPose → keypoint conversion
    // so this store remains framework-free.
    func record(keypoints: [String: PoseSample.KeypointData],
                label: String,
                captureAngle: String) {
        let sample = PoseSample(
            id: UUID(),
            timestamp: Date(),
            label: label,
            captureAngle: captureAngle,
            keypoints: keypoints
        )
        samples.append(sample)
        save()
    }

    func clear() {
        samples = []
        try? FileManager.default.removeItem(at: storeURL)
    }

    // MARK: - Derived

    // How many samples exist per label — shown in the collection UI as a balance check.
    // A well-balanced training set has roughly equal counts per class.
    var labelDistribution: [String: Int] {
        Dictionary(grouping: samples, by: \.label).mapValues(\.count)
    }

    // MARK: - CreateML export (FR-20)

    // Writes a flat JSON array to Documents, one object per training row.
    // Each keypoint becomes three columns: <name>_x, <name>_y, <name>_confidence.
    // Missing joints are written as -1.0 (matching PoseSample.KeypointData.missing).
    //
    // To train in CreateML:
    //   1. Open CreateML → New Document → Tabular Classifier
    //   2. Drop in this file
    //   3. Set Target column = "label"
    //   4. Leave all other columns as features
    //   5. Train → evaluate → export .mlmodel
    @discardableResult
    func exportCreateMLJSON() throws -> URL {
        var rows: [[String: Any]] = []

        for sample in samples {
            var row: [String: Any] = [
                "label": sample.label,
                "capture_angle": sample.captureAngle
            ]
            // Flatten nested keypoints into individual columns
            for (name, kp) in sample.keypoints {
                row["\(name)_x"]          = kp.x
                row["\(name)_y"]          = kp.y
                row["\(name)_confidence"] = kp.confidence
            }
            rows.append(row)
        }

        let data = try JSONSerialization.data(
            withJSONObject: rows,
            options: [.prettyPrinted, .sortedKeys]
        )
        let url = makeExportURL()
        try data.write(to: url, options: .atomicWrite)
        return url
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: storeURL, options: .atomicWrite)
    }

    private func load() {
        guard let data  = try? Data(contentsOf: storeURL),
              let saved = try? JSONDecoder().decode([PoseSample].self, from: data)
        else { return }
        samples = saved
    }

    // MARK: - URLs

    private var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var storeURL: URL {
        documentsDir.appendingPathComponent("pose_samples.json")
    }

    private func makeExportURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return documentsDir.appendingPathComponent(
            "createml_export_\(formatter.string(from: Date())).json"
        )
    }
}
