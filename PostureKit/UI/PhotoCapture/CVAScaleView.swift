import SwiftUI

// CVAScaleView shows the user's Craniovertebral Angle reading on a colour-coded
// threshold scale so they can understand both the raw number and what it means.
//
// Layout (top to bottom):
//   "Forward Head Posture — Craniovertebral Angle" label
//   Large angle number + zone name (coloured to match zone)
//   Colour bar with a white position marker
//   Zone labels aligned under each band  ← shows all thresholds at once
//
// Clinical reference:
//   ≥ 50°   Normal     (green)
//   45–49°  Mild FHP   (yellow)
//   35–44°  Moderate   (orange)
//   < 35°   Severe     (red)
//
// Why we show the angle even when posture is good:
// A score of "100" is uninformative — the user doesn't know if they measured 89°
// or 51°. Showing "62° — Normal" makes a good score feel earned and gives a
// concrete target to aim for on follow-up assessments.

struct CVAScaleView: View {

    let angle: Double

    // Display range for the bar. Values outside this range are clamped to the ends.
    private static let scaleMin = 20.0
    private static let scaleMax = 90.0
    private static let scaleRange = scaleMax - scaleMin   // 70°

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Section label
            Text("Forward Head Posture — Craniovertebral Angle")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            // Headline reading: large angle + zone name, both coloured by zone.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f°", angle))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(zoneColor)
                    .contentTransition(.numericText())

                VStack(alignment: .leading, spacing: 1) {
                    Text(zoneName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(zoneColor)
                    Text(zoneGuidance)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Colour bar + position marker
            GeometryReader { geo in
                let w = geo.size.width

                ZStack(alignment: .leading) {
                    // Segmented colour bar
                    HStack(spacing: 0) {
                        Color.red
                            .frame(width: w * barFraction(lo: 20, hi: 35))
                        Color.orange
                            .frame(width: w * barFraction(lo: 35, hi: 45))
                        Color.yellow
                            .frame(width: w * barFraction(lo: 45, hi: 50))
                        Color.green   // fills the remainder
                    }
                    .frame(height: 14)
                    .clipShape(Capsule())

                    // White position marker — a thin pill that stands above the bar.
                    // Clamped so it never overruns either end of the bar.
                    let mx = markerX(totalWidth: w)
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                        .frame(width: 3, height: 22)
                        .offset(x: mx - 1.5)
                }
            }
            .frame(height: 22)

            // Zone labels — four columns proportional to bar widths.
            // Proportions: 15/70, 10/70, 5/70, 40/70
            HStack(spacing: 0) {
                zoneLabel(color: .red,    name: "Severe",   range: "< 35°",   fraction: barFraction(lo: 20, hi: 35))
                zoneLabel(color: .orange, name: "Moderate", range: "35–44°",  fraction: barFraction(lo: 35, hi: 45))
                zoneLabel(color: .yellow, name: "Mild",     range: "45–49°",  fraction: barFraction(lo: 45, hi: 50))
                zoneLabel(color: .green,  name: "Normal",   range: "≥ 50°",   fraction: barFraction(lo: 50, hi: 90))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    // MARK: - Helpers

    // What fraction of the bar [0,1] a zone occupies.
    private func barFraction(lo: Double, hi: Double) -> CGFloat {
        CGFloat((hi - lo) / Self.scaleRange)
    }

    // Pixel x position of the marker within totalWidth.
    private func markerX(totalWidth: CGFloat) -> CGFloat {
        let clamped = min(max(angle, Self.scaleMin), Self.scaleMax)
        return CGFloat((clamped - Self.scaleMin) / Self.scaleRange) * totalWidth
    }

    private var zoneColor: Color {
        switch angle {
        case ..<35:  return .red
        case 35..<45: return .orange
        case 45..<50: return .yellow
        default:     return .green
        }
    }

    private var zoneName: String {
        switch angle {
        case ..<35:  return "Severe FHP"
        case 35..<45: return "Moderate FHP"
        case 45..<50: return "Mild FHP"
        default:     return "Normal"
        }
    }

    // Short plain-English guidance for each zone.
    private var zoneGuidance: String {
        switch angle {
        case ..<35:  return "Significant forward head position — consider a physiotherapy assessment"
        case 35..<45: return "Noticeable forward lean — try chin tucks and shoulder blade squeezes"
        case 45..<50: return "Slight forward lean — focus on keeping ears over shoulders"
        default:     return "Ear is well-aligned over the shoulder — keep it up"
        }
    }

    // MARK: - Zone label column

    private func zoneLabel(color: Color, name: String, range: String, fraction: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(range)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        // Proportional width to match the bar above — uses layoutPriority so the
        // HStack distributes space according to each column's fraction.
        // Simpler than GeometryReader: fractional widths come from matching the bar.
    }
}
