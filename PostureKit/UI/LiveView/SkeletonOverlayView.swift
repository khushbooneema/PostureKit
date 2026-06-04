import SwiftUI

// SkeletonOverlayView draws the detected body skeleton on top of the camera feed.
// Rendering order matters: lines first, dots on top.
// This ensures dots are always visible at joints where lines cross.
//
// Why SwiftUI Canvas instead of Shape or individual views per joint:
// Canvas is a single draw call that redraws the entire skeleton each frame.
// Creating 16 individual Circle() views would produce 16 SwiftUI views each
// with their own layout pass — at 30fps that's 480 view updates per second.
// Canvas handles real-time drawing exactly like SpriteKit or Metal would,
// but with a SwiftUI-native API.

struct SkeletonOverlayView: View {

    let pose: BodyPose

    // Each tuple defines one bone — a line between two joints.
    // If either joint is nil or unreliable, that bone is skipped.
    // Stored as a computed property so it always reflects the current pose.
    private var connections: [(BodyPose.Joint?, BodyPose.Joint?)] {
        [
            // Head & neck
            (pose.nose,         pose.leftEye),
            (pose.nose,         pose.rightEye),
            (pose.neck,         pose.leftShoulder),
            (pose.neck,         pose.rightShoulder),

            // Shoulder bar
            (pose.leftShoulder, pose.rightShoulder),

            // Left arm
            (pose.leftShoulder, pose.leftElbow),
            (pose.leftElbow,    pose.leftWrist),

            // Right arm
            (pose.rightShoulder, pose.rightElbow),
            (pose.rightElbow,    pose.rightWrist),

            // Torso
            (pose.leftShoulder,  pose.leftHip),
            (pose.rightShoulder, pose.rightHip),

            // Hip bar
            (pose.leftHip,  pose.rightHip),

            // Left leg
            (pose.leftHip,  pose.leftKnee),
            (pose.leftKnee, pose.leftAnkle),

            // Right leg
            (pose.rightHip,  pose.rightKnee),
            (pose.rightKnee, pose.rightAnkle)
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            Canvas { context, _ in
                // Lines drawn first so dots render on top at joint intersections.
                drawConnections(context: context, size: size)
                drawJoints(context: context, size: size)
            }
        }
    }

    // MARK: - Drawing

    private func drawConnections(context: GraphicsContext, size: CGSize) {
        for (jointA, jointB) in connections {
            // Both endpoints must be reliable — skip the line if either is absent.
            guard
                let ptA = CoordinateConverter.visionToCanvas(jointA, canvasSize: size),
                let ptB = CoordinateConverter.visionToCanvas(jointB, canvasSize: size)
            else { continue }

            var path = Path()
            path.move(to: ptA)
            path.addLine(to: ptB)

            context.stroke(path, with: .color(.green.opacity(0.9)), lineWidth: 4)
        }
    }

    private func drawJoints(context: GraphicsContext, size: CGSize) {
        let joints: [BodyPose.Joint?] = [
            pose.leftEye,       pose.rightEye,
            pose.nose,
            pose.leftEar,        pose.rightEar,
            pose.neck,
            pose.leftShoulder,   pose.rightShoulder,
            pose.leftElbow,      pose.rightElbow,
            pose.leftWrist,      pose.rightWrist,
            pose.leftHip,        pose.rightHip,
            pose.leftKnee,       pose.rightKnee,
            pose.leftAnkle,      pose.rightAnkle
        ]

        for joint in joints {
            guard let point = CoordinateConverter.visionToCanvas(joint, canvasSize: size) else {
                continue
            }

            // Filled yellow circle centred on the joint point.
            // Drawn after lines so dots sit on top at intersections.
            let dotRadius: CGFloat = 6
            let rect = CGRect(
                x: point.x - dotRadius,
                y: point.y - dotRadius,
                width: dotRadius * 3,
                height: dotRadius * 3
            )
            context.fill(Path(ellipseIn: rect), with: .color(.yellow))
        }
    }
}
