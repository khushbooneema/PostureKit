# PostureKit

An iOS app that analyses your posture from photos using Apple's Vision framework and CoreML.

Take three guided photos — front, side, and back — and PostureKit detects 18 body keypoints, runs a set of clinical posture checks, and shows the results as a colour-coded skeleton overlay with a 0–100 score and plain-English corrective guidance.

## What it checks

| Check | View | Method |
|---|---|---|
| Forward head posture | Side | Craniovertebral angle (CVA) — ear-to-shoulder angle |
| Shoulder symmetry | Front / Back | Vertical asymmetry ratio between shoulders |
| Hip symmetry | Front / Back | Vertical asymmetry ratio between hips |
| Trunk lateral tilt | All | Shoulder-midpoint → hip-midpoint angle from vertical |
| Head tilt | Front | Ear height difference relative to shoulder width |

Each issue is graded mild / moderate / severe and highlighted directly on the skeleton overlay.

## Hybrid analysis

Two independent engines analyse every photo:

- **Rule-based** — geometric checks with thresholds from clinical literature
- **ML classifier** — a CreateML tabular classifier trained on pose keypoints, predicting one of six posture classes with a confidence score

The app also includes a hidden data-collection mode (long-press the step indicator) for recording labelled pose samples and exporting CreateML-ready training data.

## Tech stack

- **SwiftUI** + MVVM, iOS 17+
- **AVFoundation** — guided photo capture with countdown timer
- **Vision** — `VNDetectHumanBodyPoseRequest` for 18-point body pose detection
- **CoreML / CreateML** — tabular posture classifier
- No third-party dependencies

## Getting started

1. Open `PostureKit.xcodeproj` in Xcode 16+
2. Select your team under Signing & Capabilities
3. Build and run on a physical device (camera required)

## Disclaimer

PostureKit is a learning project, not a medical device. Results are informational and not a substitute for professional assessment.


## Github actions for CI