import Foundation
import Testing
@testable import FennecCore

@Suite("Waveform Sampler and Processor")
struct WaveformTests {
    @Test("Empty or short buffer produces zeroed points")
    func emptyBufferProducesZeros() {
        let points = WaveformSampler.resample(samples: [], targetCount: 16)
        #expect(points.count == 16)
        #expect(points.allSatisfy { $0 == 0.0 })
    }

    @Test("Resampling divides samples into even buckets and measures RMS energy")
    func resamplingMeasuresBuckets() {
        // 100 samples total, target 2 buckets (50 each).
        // First 50 samples amplitude 0.5, second 50 samples amplitude 0.0.
        let firstHalf = [Float](repeating: 0.5, count: 50)
        let secondHalf = [Float](repeating: 0.0, count: 50)
        let samples = firstHalf + secondHalf

        let points = WaveformSampler.resample(samples: samples, targetCount: 2)
        #expect(points.count == 2)
        #expect(abs(points[0] - 0.5) < 0.01)
        #expect(points[1] == 0.0)
    }

    @Test("Peak normalization scales signals within 0.0 to 1.0")
    func normalizationBoundsOutput() {
        let loud = [Float](repeating: 2.0, count: 20)
        let points = WaveformSampler.resample(samples: loud, targetCount: 4)
        for val in points {
            #expect(val >= 0.0 && val <= 1.0)
        }
    }

    @Test("Resting wave generator produces cyclical smooth values for chill idle state")
    func restingWaveProducesPeriodicSmoothValues() {
        let wave0 = WaveformSampler.restingWave(pointCount: 16, time: 0.0)
        let wave1 = WaveformSampler.restingWave(pointCount: 16, time: 1.0)
        #expect(wave0.count == 16)
        #expect(wave1.count == 16)
        // Values should be non-zero and bounded
        #expect(wave0.contains { $0 != 0.0 })
        #expect(wave0.allSatisfy { $0 >= -1.0 && $0 <= 1.0 })
    }

    @Test("Combining resting wave and audio smoothly interpolates based on activeWeight")
    func combiningRestingAndAudioInterpolates() {
        let resting = [Float](repeating: 0.2, count: 4)
        let audio = [Float](repeating: 0.8, count: 4)

        let atZero = WaveformSampler.combine(resting: resting, audio: audio, activeWeight: 0.0)
        #expect(atZero == resting)

        let atOne = WaveformSampler.combine(resting: resting, audio: audio, activeWeight: 1.0)
        #expect(atOne == audio)

        let atHalf = WaveformSampler.combine(resting: resting, audio: audio, activeWeight: 0.5)
        #expect(atHalf.count == 4)
        for val in atHalf {
            #expect(abs(val - 0.5) < 0.001)
        }
    }
}
