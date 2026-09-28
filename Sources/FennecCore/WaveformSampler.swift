import Foundation

public enum WaveformSampler {
    /// Resamples audio PCM samples into a fixed number of normalized energy points in `0.0 ... 1.0`.
    public static func resample(samples: [Float], targetCount: Int) -> [Float] {
        guard targetCount > 0 else { return [] }
        guard !samples.isEmpty else { return [Float](repeating: 0.0, count: targetCount) }

        let bucketSize = Double(samples.count) / Double(targetCount)
        var result = [Float](repeating: 0.0, count: targetCount)

        for i in 0..<targetCount {
            let start = Int(Double(i) * bucketSize)
            let end = min(samples.count, max(start + 1, Int(Double(i + 1) * bucketSize)))
            guard start < end else { continue }

            var sumSquares: Float = 0.0
            for j in start..<end {
                let sample = samples[j]
                sumSquares += sample * sample
            }
            let rms = sqrt(sumSquares / Float(end - start))
            result[i] = min(1.0, max(0.0, rms))
        }

        return result
    }

    /// Generates smooth cyclical resting wave offsets in `-1.0 ... 1.0` for a chill, relaxing idle state.
    /// Uses compound sine waves with gentle harmonic oscillation (evoking a breathing ribbon).
    public static func restingWave(pointCount: Int, time: Double) -> [Float] {
        guard pointCount > 0 else { return [] }
        var points = [Float](repeating: 0.0, count: pointCount)

        for i in 0..<pointCount {
            let progress = Double(i) / Double(pointCount - 1)
            // Primary breathing wave (slow ~0.4 Hz drift)
            let wave1 = sin(progress * 2.0 * .pi + time * 1.8)
            // Harmonic wave (slightly faster, counter-phase for organic character)
            let wave2 = sin(progress * 4.0 * .pi - time * 1.2) * 0.4
            // Window envelope so the ends taper smoothly into zero
            let envelope = sin(progress * .pi)

            let combined = (wave1 + wave2) * envelope
            points[i] = Float(max(-1.0, min(1.0, combined)))
        }

        return points
    }

    /// Combines the resting wave baseline and the active live audio waveform,
    /// smoothly blending between the two with `activeWeight` (0.0 = purely chill resting, 1.0 = fully live voice).
    public static func combine(resting: [Float], audio: [Float], activeWeight: Float) -> [Float] {
        let count = min(resting.count, audio.count)
        guard count > 0 else { return resting }
        let weight = max(0.0, min(1.0, activeWeight))

        var combined = [Float](repeating: 0.0, count: count)
        for i in 0..<count {
            combined[i] = resting[i] * (1.0 - weight) + audio[i] * weight
        }
        return combined
    }
}
