import SwiftUI

// SkeletonOnPhotoView draws the Vision-detected body pose skeleton over a captured photo,
// with colour-coded highlights for any detected posture issues.
//
// Drawing layers (back to front):
//   1. Reference guide lines  — dashed white lines showing the expected axis
//   2. Normal skeleton bones  — green, 2.5 pt
//   3. Highlighted bones      — severity colour (yellow/orange/red), 3.5 pt
//   4. Normal joints          — white fill + green stroke
//   5. Highlighted joints     — severity colour fill + white stroke, slightly larger
//
// Severity colour coding:
//   Mild     → yellow
//   Moderate → orange
//   Severe   → red
//
// Guide lines per check:
//   shoulderImbalance — horizontal dashed line at average shoulder Y
//   hipImbalance      — horizontal dashed line at average hip Y
//   headTilt          — horizontal dashed line at average ear Y
//   spinalTilt        — vertical dashed line from hip midpoint upward (ideal trunk axis)
//   forwardHead       — vertical dashed line from shoulder upward (ideal ear position)
//
// Coordinate mapping (Vision → Canvas):
//   Vision: origin bottom-left, Y up   → x_canvas = vx * width
//   Canvas: origin top-left,   Y down  → y_canvas = (1 - vy) * height
//
// The Canvas is overlaid directly on Image.scaledToFit(), so its size equals the exact
// rendered image rect — no letterbox offset needed in the conversion formula.

struct SkeletonOnPhotoView: View {

    let result: AngleResult

    var body: some View {
        ZStack {
            Color.black

            Image(uiImage: result.image)
                .resizable()
                .scaledToFit()
                .overlay(
                    Canvas { ctx, size in
                        let pose   = result.pose
                        let issues = result.issues
                        drawGuideLines(ctx,        pose: pose, issues: issues, in: size)
                        drawBones(ctx,             pose: pose,                 in: size)
                        drawHighlightBones(ctx,    pose: pose, issues: issues, in: size)
                        drawJoints(ctx,            pose: pose,                 in: size)
                        drawHighlightJoints(ctx,   pose: pose, issues: issues, in: size)
                    }
                )
        }
    }

    // MARK: - Guide lines

    private func drawGuideLines(_ ctx: GraphicsContext,
                                 pose: BodyPose,
                                 issues: [PostureIssue],
                                 in size: CGSize) {
        let issueTypes = Set(issues.map { $0.type })
        let style = StrokeStyle(lineWidth: 1, dash: [5, 5])
        let guideColor = Color.white.opacity(0.40)

        // Horizontal at average shoulder Y — makes raised-shoulder height difference obvious.
        if issueTypes.contains(.shoulderImbalance),
           let ls = pose.leftShoulder, ls.isReliable,
           let rs = pose.rightShoulder, rs.isReliable {
            let avgVY = (ls.position.y + rs.position.y) / 2
            drawHLine(ctx, at: (1 - avgVY) * size.height, width: size.width,
                      color: guideColor, style: style)
        }

        // Horizontal at average hip Y — makes hip tilt obvious.
        if issueTypes.contains(.hipImbalance),
           let lh = pose.leftHip, lh.isReliable,
           let rh = pose.rightHip, rh.isReliable {
            let avgVY = (lh.position.y + rh.position.y) / 2
            drawHLine(ctx, at: (1 - avgVY) * size.height, width: size.width,
                      color: guideColor, style: style)
        }

        // Horizontal at average ear Y — makes head tilt rotation obvious.
        if issueTypes.contains(.headTilt),
           let le = pose.leftEar, le.isReliable,
           let re = pose.rightEar, re.isReliable {
            let avgVY = (le.position.y + re.position.y) / 2
            drawHLine(ctx, at: (1 - avgVY) * size.height, width: size.width,
                      color: guideColor, style: style)
        }

        // Vertical from hip midpoint upward — ideal trunk axis.
        // The coloured torso bones will visually deviate from this line when leaning.
        if issueTypes.contains(.spinalTilt),
           let lh = pose.leftHip, lh.isReliable,
           let rh = pose.rightHip, rh.isReliable {
            let midVX = (lh.position.x + rh.position.x) / 2
            let midY  = (1 - (lh.position.y + rh.position.y) / 2) * size.height
            drawVLine(ctx,
                      x: midVX * size.width,
                      from: midY, to: 0,
                      color: guideColor, style: style)
        }

        // Vertical from shoulder upward — shows where the ear should be (directly above)
        // when the head is not protruding forward. The coloured CVA line shows where it is.
        if issueTypes.contains(.forwardHead) {
            let sh: BodyPose.Joint?
            if pose.leftShoulder?.isReliable == true  { sh = pose.leftShoulder }
            else if pose.rightShoulder?.isReliable == true { sh = pose.rightShoulder }
            else { sh = nil }
            if let sh {
                let x    = sh.position.x * size.width
                let fromY = (1 - sh.position.y) * size.height
                drawVLine(ctx, x: x, from: fromY, to: 0, color: guideColor, style: style)
            }
        }
    }

    private func drawHLine(_ ctx: GraphicsContext,
                            at y: CGFloat, width: CGFloat,
                            color: Color, style: StrokeStyle) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: width, y: y))
        ctx.stroke(path, with: .color(color), style: style)
    }

    private func drawVLine(_ ctx: GraphicsContext,
                            x: CGFloat, from fromY: CGFloat, to toY: CGFloat,
                            color: Color, style: StrokeStyle) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: fromY))
        path.addLine(to: CGPoint(x: x, y: toY))
        ctx.stroke(path, with: .color(color), style: style)
    }

    // MARK: - Base skeleton

    private func drawBones(_ ctx: GraphicsContext, pose: BodyPose, in size: CGSize) {
        for (a, b) in boneConnections(pose) {
            var path = Path()
            path.move(to: displayPoint(a.position, in: size))
            path.addLine(to: displayPoint(b.position, in: size))
            ctx.stroke(path, with: .color(.green.opacity(0.85)), lineWidth: 2.5)
        }
    }

    private func drawJoints(_ ctx: GraphicsContext, pose: BodyPose, in size: CGSize) {
        for joint in allJoints(pose) {
            let pt = displayPoint(joint.position, in: size)
            let r: CGFloat = 5
            let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.green), lineWidth: 1.5)
        }
    }

    // MARK: - Issue highlights

    private func drawHighlightBones(_ ctx: GraphicsContext,
                                     pose: BodyPose,
                                     issues: [PostureIssue],
                                     in size: CGSize) {
        // Sort mild → severe so the most-severe colour wins on overlapping joints.
        let sorted = issues.sorted { $0.severityScore < $1.severityScore }
        for (a, b, color) in highlightedBones(for: sorted, in: pose) {
            var path = Path()
            path.move(to: displayPoint(a.position, in: size))
            path.addLine(to: displayPoint(b.position, in: size))
            ctx.stroke(path, with: .color(color), lineWidth: 3.5)
        }
    }

    private func drawHighlightJoints(_ ctx: GraphicsContext,
                                      pose: BodyPose,
                                      issues: [PostureIssue],
                                      in size: CGSize) {
        let sorted = issues.sorted { $0.severityScore < $1.severityScore }
        for (joint, color) in highlightedJoints(for: sorted, in: pose) {
            let pt = displayPoint(joint.position, in: size)
            let r: CGFloat = 7
            let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(color))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)
        }
    }

    // MARK: - Issue → joint mapping

    private func highlightedJoints(for issues: [PostureIssue],
                                    in pose: BodyPose) -> [(BodyPose.Joint, Color)] {
        var result: [(BodyPose.Joint, Color)] = []

        for issue in issues {
            let color  = issueColor(issue.severity)
            var joints: [BodyPose.Joint] = []

            switch issue.type {
            case .forwardHead:
                // Prefer left ear/shoulder pair (matches CVA detection preference).
                if let ear = pose.leftEar, let sh = pose.leftShoulder,
                   ear.isReliable, sh.isReliable {
                    joints = [ear, sh]
                } else if let ear = pose.rightEar, let sh = pose.rightShoulder,
                          ear.isReliable, sh.isReliable {
                    joints = [ear, sh]
                }

            case .shoulderImbalance:
                joints = [pose.leftShoulder, pose.rightShoulder]
                    .compactMap { $0 }.filter { $0.isReliable }

            case .spinalTilt:
                joints = [pose.leftShoulder, pose.rightShoulder,
                          pose.leftHip,      pose.rightHip]
                    .compactMap { $0 }.filter { $0.isReliable }

            case .hipImbalance:
                joints = [pose.leftHip, pose.rightHip]
                    .compactMap { $0 }.filter { $0.isReliable }

            case .headTilt:
                joints = [pose.leftEar, pose.rightEar]
                    .compactMap { $0 }.filter { $0.isReliable }
            }

            result.append(contentsOf: joints.map { ($0, color) })
        }

        return result
    }

    // MARK: - Issue → bone mapping

    private func highlightedBones(for issues: [PostureIssue],
                                   in pose: BodyPose) -> [(BodyPose.Joint, BodyPose.Joint, Color)] {
        var result: [(BodyPose.Joint, BodyPose.Joint, Color)] = []

        for issue in issues {
            let color = issueColor(issue.severity)

            switch issue.type {
            case .forwardHead:
                // The CVA line — from ear diagonally down to same-side shoulder.
                // This bone does not exist in the base skeleton, so it stands out clearly.
                if let ear = pose.leftEar, let sh = pose.leftShoulder,
                   ear.isReliable, sh.isReliable {
                    result.append((ear, sh, color))
                } else if let ear = pose.rightEar, let sh = pose.rightShoulder,
                          ear.isReliable, sh.isReliable {
                    result.append((ear, sh, color))
                }

            case .shoulderImbalance:
                // Shoulder-to-shoulder horizontal crossbar (not in base skeleton).
                // Its tilt angle makes the height difference immediately obvious.
                if let ls = pose.leftShoulder, let rs = pose.rightShoulder,
                   ls.isReliable, rs.isReliable {
                    result.append((ls, rs, color))
                }

            case .spinalTilt:
                // Both torso vertical columns + hip crossbar.
                // Together these three bones form the trunk "frame" — its lean is visible.
                if let ls = pose.leftShoulder,  let lh = pose.leftHip,
                   ls.isReliable, lh.isReliable { result.append((ls, lh, color)) }
                if let rs = pose.rightShoulder, let rh = pose.rightHip,
                   rs.isReliable, rh.isReliable { result.append((rs, rh, color)) }
                if let lh = pose.leftHip, let rh = pose.rightHip,
                   lh.isReliable, rh.isReliable { result.append((lh, rh, color)) }

            case .hipImbalance:
                // Hip-to-hip crossbar. Its tilt shows which hip is raised.
                if let lh = pose.leftHip, let rh = pose.rightHip,
                   lh.isReliable, rh.isReliable {
                    result.append((lh, rh, color))
                }

            case .headTilt:
                // Ear-to-ear line (not in base skeleton).
                // Its tilt angle makes the head rotation directly readable.
                if let le = pose.leftEar, let re = pose.rightEar,
                   le.isReliable, re.isReliable {
                    result.append((le, re, color))
                }
            }
        }

        return result
    }

    // MARK: - Colour mapping

    private func issueColor(_ severity: PostureIssue.Severity) -> Color {
        switch severity {
        case .mild:     return .yellow
        case .moderate: return .orange
        case .severe:   return .red
        }
    }

    // MARK: - Coordinate conversion

    private func displayPoint(_ visionPoint: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: visionPoint.x * size.width,
            y: (1.0 - visionPoint.y) * size.height
        )
    }

    // MARK: - Skeleton topology

    private func boneConnections(_ p: BodyPose) -> [(BodyPose.Joint, BodyPose.Joint)] {
        let candidates: [(BodyPose.Joint?, BodyPose.Joint?)] = [
            // Head
            (p.nose, p.leftEye),    (p.nose, p.rightEye),
            (p.leftEye, p.leftEar), (p.rightEye, p.rightEar),
            // Neck hub
            (p.nose, p.neck),
            (p.neck, p.leftShoulder), (p.neck, p.rightShoulder),
            // Left arm
            (p.leftShoulder, p.leftElbow), (p.leftElbow, p.leftWrist),
            // Right arm
            (p.rightShoulder, p.rightElbow), (p.rightElbow, p.rightWrist),
            // Torso
            (p.leftShoulder, p.leftHip), (p.rightShoulder, p.rightHip),
            (p.leftHip, p.rightHip),
            // Left leg
            (p.leftHip, p.leftKnee), (p.leftKnee, p.leftAnkle),
            // Right leg
            (p.rightHip, p.rightKnee), (p.rightKnee, p.rightAnkle),
        ]
        return candidates.compactMap { a, b in
            guard let a, let b, a.isReliable, b.isReliable else { return nil }
            return (a, b)
        }
    }

    private func allJoints(_ p: BodyPose) -> [BodyPose.Joint] {
        [p.nose, p.neck,
         p.leftEye, p.rightEye, p.leftEar, p.rightEar,
         p.leftShoulder, p.rightShoulder,
         p.leftElbow, p.rightElbow,
         p.leftWrist, p.rightWrist,
         p.leftHip, p.rightHip,
         p.leftKnee, p.rightKnee,
         p.leftAnkle, p.rightAnkle]
        .compactMap { $0 }
        .filter { $0.isReliable }
    }
}
