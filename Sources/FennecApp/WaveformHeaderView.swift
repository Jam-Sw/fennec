import AppKit
import FennecCore
import SwiftUI

@MainActor
final class WaveformHeaderModel: ObservableObject {
    @Published var status: MenuBar.Status = .starting
    @Published var hotkeyName: String = Hotkey.rightOption.displayName
    var fetchAudio: (() -> [Float])?

    // Smoothed audio level across frames to avoid jitter
    private var smoothedLevels = [Float](repeating: 0.0, count: 28)
    private var activeWeight: Float = 0.0

    func wavePoints(time: Double) -> (points: [Float], isListening: Bool) {
        let isListening = (status == .listening)

        // Smoothly ramp activeWeight up when listening, down when idle
        if isListening {
            activeWeight = min(1.0, activeWeight + 0.15)
        } else {
            activeWeight = max(0.0, activeWeight - 0.06)
        }

        let resting = WaveformSampler.restingWave(pointCount: 28, time: time)

        if activeWeight > 0.01, let samples = fetchAudio?(), !samples.isEmpty {
            let fresh = WaveformSampler.resample(samples: samples, targetCount: 28)
            for i in 0..<min(smoothedLevels.count, fresh.count) {
                smoothedLevels[i] = smoothedLevels[i] * 0.35 + fresh[i] * 0.65
            }
        } else {
            for i in 0..<smoothedLevels.count {
                smoothedLevels[i] *= 0.82
            }
        }

        // Modulate an energetic voice wave by the smoothed audio levels
        var voiceWave = [Float](repeating: 0.0, count: 28)
        for i in 0..<28 {
            let progress = Double(i) / 27.0
            let carrier = sin(progress * 6.0 * .pi + time * 12.0)
            let envelope = sin(progress * .pi)
            // Voice energy expands the carrier wave
            let amp = smoothedLevels[i] * 3.5
            voiceWave[i] = Float(carrier * envelope) * amp
        }

        let points = WaveformSampler.combine(
            resting: resting,
            audio: voiceWave,
            activeWeight: activeWeight
        )

        return (points, isListening)
    }
}

struct WaveformHeaderView: View {
    @ObservedObject var model: WaveformHeaderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6, height: 6)

                Text(model.status.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("Hold \(model.hotkeyName) to dictate")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let data = model.wavePoints(time: time)

                WaveformShape(points: data.points)
                    .stroke(
                        data.isListening ? Color(nsColor: MenuBarGlyph.listeningColor) : Color.primary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
                    )
            }
            .frame(height: 18)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
        }
        .frame(width: 250, height: 42)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.status.title). Hold \(model.hotkeyName) to dictate.")
    }

    private var statusDotColor: Color {
        switch model.status.glyph {
        case .idle:
            return Color.secondary.opacity(0.6)
        case .listening:
            return Color(nsColor: MenuBarGlyph.listeningColor)
        case .working:
            return Color.blue
        case .attention:
            return Color.red
        }
    }
}

private struct WaveformShape: Shape {
    var points: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }

        let step = rect.width / CGFloat(points.count - 1)
        let midY = rect.midY
        let maxAmp = rect.height * 0.42

        var coords = [CGPoint]()
        for i in 0..<points.count {
            let x = CGFloat(i) * step
            let clamped = max(-1.0, min(1.0, CGFloat(points[i])))
            let y = midY - clamped * maxAmp
            coords.append(CGPoint(x: x, y: y))
        }

        path.move(to: coords[0])
        for i in 0..<(coords.count - 1) {
            let current = coords[i]
            let next = coords[i + 1]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: current)
        }
        if let last = coords.last {
            path.addLine(to: last)
        }

        return path
    }
}
