import Foundation

public enum SilenceTrimmer {
    public static func trim(
        _ samples: [Float],
        sampleRate: Double,
        threshold: Float = 0.008,
        pad: TimeInterval = 0.05
    ) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        let frameLength = max(1, Int(0.02 * sampleRate))

        var frames: [(start: Int, length: Int, rms: Float)] = []
        var index = 0
        while index < samples.count {
            let end = min(index + frameLength, samples.count)
            var sum: Float = 0
            for sampleIndex in index ..< end {
                sum += samples[sampleIndex] * samples[sampleIndex]
            }
            let rms = (sum / Float(end - index)).squareRoot()
            frames.append((index, end - index, rms))
            index = end
        }

        guard let first = frames.first(where: { $0.rms >= threshold }),
              let last = frames.last(where: { $0.rms >= threshold }) else {
            return []
        }
        let padSamples = Int(pad * sampleRate)
        let start = max(0, first.start - padSamples)
        let end = min(samples.count, last.start + last.length + padSamples)
        return Array(samples[start ..< end])
    }
}
